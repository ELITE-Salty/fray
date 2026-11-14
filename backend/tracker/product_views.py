"""Personal templates/goals and shared projects with private individual records."""
import smtplib
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from django.core.validators import validate_email
from django.db import transaction
from django.db.models import Sum
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.translation import gettext as _
from django.views.decorators.http import require_http_methods, require_POST

from .auth_views import limited, rate_error
from .mail_support import record_failure, MAIL
from .models import AccountProfile, EntryTemplate, Item, ProjectMember, ProjectInvitation, TimeEntry
from .views import private, payload, error, text_field, loggable_items, month_bounds, audit


def template_json(t):
    return {'id': str(t.pk), 'item_id': str(t.item_id), 'name': t.name, 'minutes': t.minutes, 'notes': t.notes}


@require_http_methods(['GET', 'POST', 'DELETE'])
@private
@payload
def templates(request, data, template_id=None):
    if request.method == 'GET':
        return JsonResponse({'templates': [template_json(t) for t in EntryTemplate.objects.filter(user=request.user, item__in=loggable_items(request.user)).order_by('name')]})
    if request.method == 'DELETE':
        get_object_or_404(EntryTemplate, pk=template_id, user=request.user).delete()
        return JsonResponse({'ok': True})
    item = get_object_or_404(loggable_items(request.user), pk=data['item_id'], archived=False)
    name = text_field(data, 'name', 120)
    minutes = data.get('minutes')
    if not name or type(minutes) is not int or not 1 <= minutes <= 1440:
        return error(_('Give the template a name and a duration from 1 to 1440 minutes.'))
    t = EntryTemplate.objects.create(user=request.user, item=item, name=name, minutes=minutes, notes=text_field(data, 'notes', 2000))
    return JsonResponse(template_json(t), status=201)


@require_http_methods(['GET', 'PATCH'])
@private
@payload
def preferences(request, data):
    profile, _created = AccountProfile.objects.get_or_create(user=request.user, defaults={})
    if request.method == 'PATCH':
        minutes = data.get('weeklyGoalMinutes')
        if type(minutes) is not int or not 0 <= minutes <= 10080:
            return error(_('Weekly goals must be between 0 and 10080 minutes.'))
        profile.weekly_goal_minutes = minutes
        profile.save(update_fields=['weekly_goal_minutes'])
    return JsonResponse({'weeklyGoalMinutes': profile.weekly_goal_minutes})


@require_http_methods(['GET', 'POST', 'DELETE'])
@private
@payload
@transaction.atomic
def project(request, data, item_id):
    item = get_object_or_404(Item.objects.select_for_update(), pk=item_id, kind='project')
    owner = item.owner_id == request.user.pk
    member = item.memberships.filter(user=request.user).exists()
    if not owner and not member:
        return error(_('You no longer have access to this shared project.'), 403)
    if request.method == 'GET':
        first, end = month_bounds(request)
        total = TimeEntry.objects.filter(item=item, local_date__gte=first, local_date__lt=end).aggregate(total=Sum('duration_minutes'))['total'] or 0
        members = [{'id': item.owner_id, 'name': item.owner.first_name or item.owner.username, 'role': 'owner'}]
        members += [{'id': m.user_id, 'name': m.user.first_name or m.user.username, 'role': 'member'} for m in item.memberships.select_related('user')]
        invitations = [{'id': str(i.pk), 'email': i.email, 'expiresAt': i.expires_at.isoformat()} for i in ProjectInvitation.objects.filter(item=item)] if owner else []
        return JsonResponse({'name': item.name, 'totalMinutes': total, 'members': members, 'invitations': invitations, 'isOwner': owner})
    if request.method == 'DELETE':
        if owner:
            return error(_('Transfer ownership before leaving this project.'), 409)
        item.memberships.filter(user=request.user).delete()
        return JsonResponse({'ok': True})
    if not owner:
        return error(_('Only the project owner can manage members.'), 403)
    action = data.get('action')
    if action == 'remove':
        item.memberships.filter(user_id=data.get('userId')).delete()
    elif action == 'transfer':
        membership = get_object_or_404(ProjectMember, item=item, user_id=data.get('userId'))
        # The recipient has already accepted membership; transfer preserves both users' history.
        old_owner = item.owner
        item.owner = membership.user
        item.save(update_fields=['owner'])
        membership.delete()
        ProjectMember.objects.get_or_create(item=item, user=old_owner)
        ProjectInvitation.objects.filter(item=item).delete()
    elif action == 'revoke':
        ProjectInvitation.objects.filter(item=item, pk=data.get('invitationId')).delete()
    elif action == 'invite':
        email = text_field(data, 'email', 150).lower()
        validate_email(email)
        if email == request.user.username or item.memberships.filter(user__username=email).exists():
            return error(_('This person already belongs to the project.'))
        if item.archived:
            return error(_('Unarchive this item before logging time.'))
        if limited('project-invite', str(request.user.pk), 20, 3600):
            return rate_error('project-invite', str(request.user.pk), 3600, _('Too many invitations. Please try again later.'))
        if limited('invite-email', email, 3, 600):
            return rate_error('invite-email', email, 600, _('Too many verification emails. Please try again later.'))
        if limited('signup-total', 'all', settings.SIGNUP_EMAIL_LIMIT, 3600):
            return rate_error('signup-total', 'all', 3600, _('Too many verification emails. Please try again later.'))
        try:
            sent = send_mail(_('Invitation to a Fray project'),
                _('You have been invited to %(project)s. Sign in to Fray with this email address and open Projects → Invitations. Your individual entries and notes stay private. This invitation expires in seven days.') % {'project': item.name},
                settings.DEFAULT_FROM_EMAIL, [email], fail_silently=False)
            if sent != 1:
                raise OSError('Mail not accepted')
            MAIL.labels('sent').inc()
        except (smtplib.SMTPException, OSError) as exc:
            record_failure(exc)
            return error(_('We could not send your verification email. Please try again later.'), 503, code='email_unavailable', retry_after=60)
        ProjectInvitation.objects.update_or_create(item=item, email=email, defaults={
            'expires_at': timezone.now() + timedelta(days=7), 'sent_at': timezone.now()})
    else:
        return error(_('Invalid request.'))
    audit.info('project_membership_changed user=%s project=%s action=%s', request.user.pk, item.pk, action)
    return JsonResponse({'ok': True})


@require_http_methods(['GET', 'POST'])
@private
@payload
@transaction.atomic
def invitations(request, data):
    if request.method == 'GET':
        rows = ProjectInvitation.objects.filter(email=request.user.username, expires_at__gt=timezone.now(), item__archived=False).select_related('item')
        return JsonResponse({'invitations': [{'id': str(i.pk), 'project': i.item.name, 'expiresAt': i.expires_at.isoformat()} for i in rows]})
    invitation = get_object_or_404(ProjectInvitation, pk=data.get('id'), email=request.user.username)
    # Match the owner operation's lock order; recheck after acquiring the project lock.
    item = Item.objects.select_for_update().get(pk=invitation.item_id)
    invitation = get_object_or_404(ProjectInvitation, pk=invitation.pk, email=request.user.username, expires_at__gt=timezone.now())
    if data.get('accept') is True:
        if not AccountProfile.objects.filter(user=request.user, email_verified_at__isnull=False).exists():
            return error(_('Verify your email through password reset before accepting invitations.'), 403)
        if item.archived or item.kind != 'project':
            return error(_('This project is no longer available.'), 409)
        if item.owner_id != request.user.pk:
            ProjectMember.objects.get_or_create(item=item, user=request.user)
    elif data.get('accept') is not False:
        return error(_('Invalid request.'))
    invitation.delete()
    return JsonResponse({'ok': True})
