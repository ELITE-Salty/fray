import csv
import hashlib
import io
import json
import logging
import re
import uuid
from datetime import date, datetime, timedelta
from functools import wraps
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.contrib.auth import authenticate, login, logout, get_user_model
from django.contrib.auth.hashers import check_password
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.db import connection, transaction
from django.db.models import Sum, Q
from django.http import HttpResponse, JsonResponse
from django.middleware.csrf import get_token
from django.shortcuts import get_object_or_404
from django.utils.translation import gettext as _
from django.views.decorators.http import require_GET, require_http_methods
from django_otp import login as otp_login
from prometheus_client import CONTENT_TYPE_LATEST, Gauge, generate_latest

from .models import AuthChallenge, Authenticator, Item, RecoveryCode, TimeEntry, EntryReceipt, ProjectMember

audit = logging.getLogger('fray.audit')
DEPENDENCIES = Gauge('fray_dependency_ready', 'Database/cache readiness', ['dependency'])


def error(message, status=400, *, code=None, retry_after=None):
    body = {'error': message}
    if code:
        body['code'] = code
    if retry_after is not None:
        body['retryAfter'] = max(1, int(retry_after))
    response = JsonResponse(body, status=status)
    if retry_after is not None:
        response['Retry-After'] = str(body['retryAfter'])
    return response


def private(view):
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        if not request.user.is_authenticated or not request.user.is_verified():
            return error(_('Sign in with your password and MFA code.'), 401)
        response = view(request, *args, **kwargs)
        response['Cache-Control'] = 'no-store'
        return response
    return wrapped


def payload(view):
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        try:
            body = json.loads(request.body or '{}')
            if not isinstance(body, dict):
                raise ValueError(_('Expected a JSON object.'))
            return view(request, body, *args, **kwargs)
        except (ValueError, TypeError, KeyError, OverflowError, ValidationError, ZoneInfoNotFoundError) as exc:
            return error('; '.join(exc.messages) if isinstance(exc, ValidationError) else str(exc) or _('Invalid request.'))
    return wrapped


@require_GET
def csrf(request):
    response = JsonResponse({'csrfToken': get_token(request)})
    response['Cache-Control'] = 'no-store'
    return response


@require_http_methods(['POST'])
@payload
def sign_in(request, data):
    email = str(data.get('email', '')).strip().lower()[:254]
    password = str(data.get('password', ''))[:1024]
    token = str(data.get('code', '')).strip()[:64]
    # Per-account limit is shared by workers and cannot be bypassed by changing IP.
    key = 'login:' + hashlib.sha256(email.encode()).hexdigest()
    if cache.add(key, 1, 300):
        attempts = 1
    else:
        try:
            attempts = cache.incr(key)
        except ValueError:  # Another successful login or expiry removed the key.
            cache.add(key, 1, 300)
            attempts = 1
    if attempts > 10:
        return error(_('Too many attempts. Wait five minutes.'), 429)
    user = authenticate(request, username=email, password=password)
    verified = False
    device = None
    if user:
        with transaction.atomic():
            # Serialize device verification and recovery-code consumption across workers.
            get_user_model().objects.select_for_update().get(pk=user.pk)
            device = Authenticator.objects.select_for_update().filter(user=user, confirmed=True).first()
            if device:
                if len(token) == 6 and token.isdigit():
                    verified = device.verify_token(token)
                elif len(token) >= 16:
                    for recovery in RecoveryCode.objects.select_for_update().filter(user=user):
                        if check_password(token, recovery.digest):
                            recovery.delete()
                            verified = True
                            audit.info('recovery_code_used user=%s', user.pk)
                            break
    if not verified:
        audit.info('login_failed')
        return error(_('Email, password, or authenticator code is incorrect.'), 401)
    login(request, user)
    otp_login(request, device)
    cache.delete(key)
    audit.info('login_success user=%s', user.pk)
    response = JsonResponse({'id': str(user.pk), 'name': user.first_name or user.username, 'email': user.username,
                             'csrfToken': get_token(request)})
    response['Cache-Control'] = 'no-store'
    return response


@require_http_methods(['POST'])
def sign_out(request):
    if request.session.get('fray_auth_challenge'):
        AuthChallenge.objects.filter(pk=request.session['fray_auth_challenge']).delete()
    logout(request)
    return JsonResponse({'ok': True})


@require_GET
@private
def me(request):
    return JsonResponse({'id': str(request.user.pk), 'name': request.user.first_name or request.user.username,
                         'email': request.user.username})


def visible_items(user):
    return Item.objects.filter(Q(owner=user) | Q(memberships__user=user) | Q(timeentry__author=user)).distinct()


def loggable_items(user):
    return Item.objects.filter(Q(owner=user) | Q(memberships__user=user)).distinct()


def item_json(item, user=None):
    result = {k: str(item.id) if k == 'id' else getattr(item, k)
              for k in ['id', 'name', 'kind', 'description', 'color', 'pinned', 'archived']}
    if user is not None:
        member = item.memberships.filter(user=user).exists()
        result.update(role='owner' if item.owner_id == user.pk else 'member' if member else 'history',
                      canLog=not item.archived and (item.owner_id == user.pk or member),
                      memberCount=item.memberships.count())
    return result


def entry_json(entry):
    return {'id': str(entry.id), 'item_id': str(entry.item_id), 'date': entry.local_date.isoformat(),
            'timezone': entry.timezone, 'mode': entry.mode, 'minutes': entry.duration_minutes,
            'start': entry.started_at.isoformat() if entry.started_at else None,
            'end': entry.ended_at.isoformat() if entry.ended_at else None, 'notes': entry.notes, 'revision': entry.revision}


def text_field(data, key, max_length, default=''):
    value = data.get(key, default)
    if not isinstance(value, str) or len(value) > max_length:
        raise ValueError(_('%(field)s must be text of at most %(limit)s characters.') % {'field': key, 'limit': max_length})
    return value.strip()


@require_http_methods(['GET', 'POST', 'PATCH'])
@private
@payload
@transaction.atomic
def items(request, data, item_id=None):
    if request.method == 'GET':
        return JsonResponse({'items': [item_json(i, request.user) for i in visible_items(request.user)]})
    if request.method == 'PATCH' and item_id is None:
        return error(_('An item ID is required.'))
    if request.method == 'POST' and item_id is not None:
        return error(_('Create items at /api/items.'))
    item = get_object_or_404(Item.objects.select_for_update(), pk=item_id, owner=request.user) if item_id else Item(owner=request.user)
    name = text_field(data, 'name', 120, item.name)
    kind = data.get('kind', item.kind)
    color = data.get('color', item.color)
    if not name or kind not in ('project', 'activity') or not isinstance(color, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', color):
        return error(_('Provide a name, project/activity kind, and a hex color.'))
    if item.pk and kind == 'activity' and (item.memberships.exists() or TimeEntry.objects.filter(item=item).exclude(author=request.user).exists()):
        return error(_('Shared projects cannot become personal activities.'), 409)
    item.name, item.kind, item.color = name, kind, color
    item.description = text_field(data, 'description', 500, item.description)
    for field in ('pinned', 'archived'):
        if field in data:
            if not isinstance(data[field], bool):
                return error(_('%(field)s must be true or false.') % {'field': field})
            setattr(item, field, data[field])
    item.save()
    audit.info('item_saved user=%s item=%s', request.user.pk, item.id)
    return JsonResponse(item_json(item, request.user), status=200 if item_id else 201)


def month_bounds(request):
    value = request.GET.get('month', date.today().strftime('%Y-%m'))
    if not re.fullmatch(r'\d{4}-\d{2}', value):
        raise ValueError(_('Month must be YYYY-MM.'))
    first = date.fromisoformat(value + '-01')
    end = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    return first, end


@require_http_methods(['GET', 'POST', 'PATCH', 'DELETE'])
@private
@payload
@transaction.atomic
def entries(request, data, entry_id=None):
    if request.method == 'GET':
        if 'from' in request.GET and 'to' in request.GET:
            first, end = date.fromisoformat(request.GET['from']), date.fromisoformat(request.GET['to'])
            if not 0 < (end - first).days <= 93:
                return error(_('Choose a date range of at most 93 days.'))
        else:
            first, end = month_bounds(request)
        rows = TimeEntry.objects.filter(author=request.user, local_date__gte=first, local_date__lt=end)
        return JsonResponse({'entries': [entry_json(e) for e in rows]})
    if request.method in ('PATCH', 'DELETE') and entry_id is None:
        return error(_('An entry ID is required.'))
    if request.method == 'POST' and entry_id is not None:
        return error(_('Create entries at /api/entries.'))
    get_user_model().objects.select_for_update().get(pk=request.user.pk)
    operation = uuid.UUID(data['operation']) if request.method == 'POST' and data.get('operation') else None
    fingerprint = hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if operation:
        receipt = EntryReceipt.objects.filter(user=request.user, operation=operation).first()
        if receipt:
            if receipt.fingerprint != fingerprint:
                return error(_('This offline operation has different content. Review it before retrying.'), 409, code='sync_conflict')
            if not receipt.entry_id:
                return error(_('This entry was already deleted on the server.'), 409, code='sync_conflict')
            return JsonResponse(entry_json(receipt.entry))
    entry = get_object_or_404(TimeEntry, pk=entry_id, author=request.user) if entry_id else TimeEntry(author=request.user)
    if entry_id and 'revision' in data and (type(data['revision']) is not int or data['revision'] != entry.revision):
        return error(_('This entry changed on another device. Reload it before saving.'), 409, code='sync_conflict')
    if request.method == 'DELETE':
        entry.delete()
        audit.info('entry_deleted user=%s entry=%s', request.user.pk, entry_id)
        return JsonResponse({'ok': True})
    item = get_object_or_404(loggable_items(request.user), pk=data['item_id'])
    if item.archived:
        return error(_('Unarchive this item before logging time.'))
    day = date.fromisoformat(data['date'])
    zone = ZoneInfo(data.get('timezone', 'UTC'))
    mode = data['mode']
    start = end = None
    if mode == 'timed':
        start, end = (datetime.fromisoformat(data[k]) for k in ('start', 'end'))
        if start.utcoffset() is None or end.utcoffset() is None:
            return error(_('Timed entries require explicit UTC offsets.'))
        if start.astimezone(zone).date() != day:
            return error(_('The date must match the start in the selected timezone.'))
        seconds = (end - start).total_seconds()
        if seconds % 60:
            return error(_('Use whole-minute intervals.'))
        minutes = int(seconds / 60)
    elif mode == 'duration':
        minutes = data['minutes']
        if type(minutes) is not int:
            return error(_('Duration must be an integer number of minutes.'))
        if data.get('start') or data.get('end'):
            return error(_('Duration-only entries cannot contain timestamps.'))
    else:
        return error(_('Choose timed or duration mode.'))
    if not 1 <= minutes <= 1440:
        return error(_('Duration must be between 1 minute and 24 hours.'))
    notes = text_field(data, 'notes', 2000)
    with transaction.atomic():
        # Lock the author, so concurrent requests cannot both pass overlap checks.
        get_user_model().objects.select_for_update().get(pk=request.user.pk)
        if mode == 'timed' and TimeEntry.objects.filter(author=request.user, mode='timed',
                started_at__lt=end, ended_at__gt=start).exclude(pk=entry.id).exists():
            return error(_('This interval overlaps another timed entry.'), 409)
        entry.item, entry.local_date, entry.timezone = item, day, str(zone)
        entry.mode, entry.started_at, entry.ended_at = mode, start, end
        entry.duration_minutes, entry.notes = minutes, notes
        if entry_id:
            entry.revision += 1
        entry.save()
        if operation:
            EntryReceipt.objects.create(user=request.user, operation=operation, entry=entry, fingerprint=fingerprint)
    audit.info('entry_saved user=%s entry=%s', request.user.pk, entry.id)
    return JsonResponse(entry_json(entry), status=200 if entry_id else 201)


@require_GET
@private
@payload
def report(request, data):
    first, end = month_bounds(request)
    rows = TimeEntry.objects.filter(author=request.user, local_date__gte=first, local_date__lt=end)
    totals = list(rows.values('item_id', 'item__name', 'item__kind', 'item__color').annotate(minutes=Sum('duration_minutes')).order_by('-minutes', 'item_id'))
    if request.GET.get('format') == 'csv':
        stream = io.StringIO()
        writer = csv.writer(stream)
        writer.writerow([_('Project / activity'), _('Type'), _('Minutes')])
        for row in totals:
            name = row['item__name']
            # Prevent spreadsheet formula injection, including whitespace-prefixed formulas.
            if name.lstrip().startswith(('=', '+', '-', '@', '\t', '\r')):
                name = "'" + name
            writer.writerow([name, _(row['item__kind']), row['minutes']])
        response = HttpResponse('\ufeff' + stream.getvalue(), content_type='text/csv; charset=utf-8')
        response['Content-Disposition'] = f'attachment; filename="fray-{first:%Y-%m}.csv"'
        return response
    return JsonResponse({'month': first.strftime('%Y-%m'), 'total_minutes': sum(r['minutes'] for r in totals), 'items': totals})


def dependency_status():
    status = {'database': False, 'cache': False}
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
        status['database'] = True
    except Exception:
        pass
    try:
        cache.set('health', 'ok', 10)
        status['cache'] = cache.get('health') == 'ok'
    except Exception:
        pass
    for name, ready in status.items():
        DEPENDENCIES.labels(name).set(int(ready))
    return all(status.values())


@require_GET
def health(request):
    if not dependency_status():
        return JsonResponse({'status': 'unavailable'}, status=503)
    return JsonResponse({'status': 'ok'})


@require_GET
def metrics(request):
    # Nginx blocks /metrics externally. The API has no public host port in Docker.
    dependency_status()
    return HttpResponse(generate_latest(), content_type=CONTENT_TYPE_LATEST)
