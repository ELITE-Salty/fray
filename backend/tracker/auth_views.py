"""Two-step sign-in and email-verified, mandatory-TOTP self registration."""
import base64
from datetime import timedelta
import secrets
import time
import smtplib
from urllib.parse import quote, urlencode

from cryptography.fernet import Fernet
from django.conf import settings
from django.contrib.auth import authenticate, get_user_model, login
from django.contrib.auth.hashers import check_password, make_password
from django.contrib.auth.password_validation import validate_password
from django.core.cache import cache
from django.core.mail import send_mail
from django.core.validators import validate_email
from django.db import IntegrityError, transaction
from django.http import JsonResponse
from django.middleware.csrf import get_token
from django.utils.translation import gettext as _
from django.utils import timezone
from django.utils.crypto import constant_time_compare, salted_hmac
from django.views.decorators.cache import never_cache
from django.views.decorators.http import require_GET, require_POST
from django_otp import login as otp_login
from django_otp.oath import TOTP

from .mail_support import record_failure, MAIL
from .models import AccountProfile, AuthChallenge, Authenticator, RecoveryCode
from .views import audit, error, payload

SESSION_KEY = 'fray_auth_challenge'


def limited(scope, identity, maximum, seconds):
    # Shared cache counters; no forwarded-IP header is trusted for security limits.
    import hashlib
    key = scope + ':' + hashlib.sha256(identity.encode()).hexdigest()
    if cache.add(key, 1, seconds):
        cache.set(key + ':until', time.time() + seconds, seconds)
        return False
    try:
        return cache.incr(key) > maximum
    except ValueError:
        return not cache.add(key, 1, seconds) and limited(scope, identity, maximum, seconds)


def rate_error(scope, identity, seconds, message):
    import hashlib
    key = scope + ':' + hashlib.sha256(identity.encode()).hexdigest()
    remaining = max(1, int(cache.get(key + ':until', time.time() + seconds) - time.time()) + 1)
    return error(message, 429, code='rate_limited', retry_after=remaining)


def mail_limit(email):
    if limited('signup-email', email, 3, 600):
        return rate_error('signup-email', email, 600, _('Too many verification emails. Please try again later.'))
    if limited('signup-total', 'all', settings.SIGNUP_EMAIL_LIMIT, 3600):
        return rate_error('signup-total', 'all', 3600, _('Too many verification emails. Please try again later.'))
    return None


def field(data, name, maximum):
    value = data.get(name, '')
    if not isinstance(value, str) or len(value) > maximum:
        raise ValueError(_('Invalid %(field)s.') % {'field': name})
    return value


def email_code_hash(challenge, code):
    return salted_hmac('fray.signup.email', f'{challenge.pk}:{code}', algorithm='sha256').hexdigest()


def discard(request):
    identity = request.session.pop(SESSION_KEY, None)
    if identity:
        AuthChallenge.objects.filter(pk=identity).delete()


def bind(request, challenge):
    discard(request)
    request.session.cycle_key()
    request.session[SESSION_KEY] = str(challenge.pk)


def pending(request, lock=False):
    identity = request.session.get(SESSION_KEY)
    if not identity:
        return None
    rows = AuthChallenge.objects.select_for_update() if lock else AuthChallenge.objects
    challenge = rows.filter(pk=identity).first()
    if challenge and challenge.expires_at > timezone.now() and challenge.attempts < 5:
        return challenge
    if challenge:
        challenge.delete()
    # Do not rewrite a stale session here: another request may just have consumed
    # this challenge and rotated/deleted that session during a successful login.
    return None


def challenge_json(challenge):
    result = {'stage': challenge.stage, 'email': challenge.email,
              'expiresAt': challenge.expires_at.isoformat()}
    if challenge.stage == 'email' and challenge.email_sent_at:
        result['resendAfter'] = max(0, 60 - int((timezone.now() - challenge.email_sent_at).total_seconds()))
    if challenge.stage == 'enroll':
        key = Fernet(settings.MFA_ENCRYPTION_KEY.encode()).decrypt(bytes(challenge.encrypted_key))
        secret = base64.b32encode(key).decode().rstrip('=')
        result.update(secret=secret, uri='otpauth://totp/' + quote('Fray:' + challenge.email, safe='') + '?' +
                      urlencode({'secret': secret, 'issuer': 'Fray', 'digits': 6, 'period': 30}))
    return result


def authenticated(request, user, device, codes=None):
    login(request, user, backend='django.contrib.auth.backends.ModelBackend')
    otp_login(request, device)
    request.session.pop(SESSION_KEY, None)
    result = {'id': str(user.pk), 'name': user.first_name or user.username, 'email': user.username,
              'csrfToken': get_token(request)}
    if codes is not None:
        result['recoveryCodes'] = codes
    audit.info('login_success user=%s', user.pk)
    return JsonResponse(result)


@never_cache
@require_POST
@payload
def begin_login(request, data):
    discard(request)
    email = field(data, 'email', 254).strip().lower()
    password = field(data, 'password', 1024)
    if limited('login', email, 10, 300):
        return rate_error('login', email, 300, _('Too many attempts. Wait five minutes.'))
    user = authenticate(request, username=email, password=password)
    if not user or not Authenticator.objects.filter(user=user, confirmed=True).exists():
        return error(_('Email or password is incorrect.'), 401)
    challenge = AuthChallenge.objects.create(user=user, stage='mfa', email=email,
        password_hash=user.get_session_auth_hash(), expires_at=timezone.now() + timedelta(minutes=10))
    bind(request, challenge)
    return JsonResponse(challenge_json(challenge))


@never_cache
@require_GET
def status(request):
    challenge = pending(request)
    return JsonResponse(challenge_json(challenge) if challenge else {'stage': 'credentials'})


@never_cache
@require_POST
def cancel(request):
    discard(request)
    return JsonResponse({'ok': True})


@never_cache
@require_POST
@payload
def verify_login(request, data):
    code = field(data, 'code', 64).strip()
    with transaction.atomic():
        challenge = pending(request, lock=True)
        if not challenge or challenge.stage != 'mfa':
            return error(_('Sign-in expired. Enter your email and password again.'), 401)
        if limited('mfa', challenge.email, 10, 300):
            return rate_error('mfa', challenge.email, 300, _('Too many attempts. Wait five minutes.'))
        user = get_user_model().objects.select_for_update().get(pk=challenge.user_id)
        if not user.is_active or not constant_time_compare(challenge.password_hash, user.get_session_auth_hash()):
            discard(request)
            return error(_('Sign-in expired. Enter your email and password again.'), 401)
        challenge.attempts += 1
        challenge.save(update_fields=['attempts'])
        device = Authenticator.objects.select_for_update().filter(user=user, confirmed=True).first()
        verified = False
        if device:
            if len(code) == 6 and code.isascii() and code.isdigit():
                verified = device.verify_token(code)
            elif len(code) >= 16:
                for recovery in RecoveryCode.objects.select_for_update().filter(user=user):
                    if check_password(code, recovery.digest):
                        recovery.delete()
                        verified = True
                        audit.info('recovery_code_used user=%s', user.pk)
                        break
        if not verified:
            return error(_('Security code is incorrect or already used. Try a new code.'), 400)
        challenge.delete()
        return authenticated(request, user, device)


def send_verification(challenge, code):
    delivered = send_mail(_('Your Fray verification code'),
        _('Your Fray email verification code is: %(code)s\n\nEnter it in the Fray app or browser where you started creating your account. Setup expires 10 minutes after your initial request; resending does not extend it. Never share this code.\n\nIf you did not request a Fray account, ignore this email.') % {'code': code},
        settings.DEFAULT_FROM_EMAIL, [challenge.email], fail_silently=False)
    if delivered != 1:
        raise OSError('Email delivery was not accepted')
    MAIL.labels('sent').inc()


def signup_available():
    return settings.SIGNUP_ENABLED and (settings.DEBUG or (
        settings.EMAIL_HOST and settings.EMAIL_HOST_USER and settings.EMAIL_HOST_PASSWORD and
        settings.DEFAULT_FROM_EMAIL and (settings.EMAIL_USE_TLS or settings.EMAIL_USE_SSL)))


@never_cache
@require_POST
@payload
def begin_signup(request, data):
    if not signup_available():
        return error(_('Account creation is not available yet. Please try again later.'), 503, code='signup_unavailable')
    email = field(data, 'email', 150).strip().lower()
    name = field(data, 'name', 150).strip()
    password = field(data, 'password', 1024)
    validate_email(email)
    validate_password(password, get_user_model()(username=email, email=email, first_name=name))
    limit = mail_limit(email)
    if limit is not None:
        return limit
    # Pending registrations reserve no usernames and cannot access any workspace.
    code = f'{secrets.randbelow(1000000):06d}'
    challenge = AuthChallenge(stage='email', email=email, name=name, password_hash=make_password(password),
        expires_at=timezone.now() + timedelta(minutes=10), email_sent_at=timezone.now())
    challenge.email_code_hash = email_code_hash(challenge, code)
    try:
        send_verification(challenge, code)
    except (smtplib.SMTPException, OSError) as exc:
        record_failure(exc)
        return error(_('We could not send your verification email. Please try again later.'), 503, code='email_unavailable', retry_after=60)
    challenge.save()
    bind(request, challenge)
    return JsonResponse(challenge_json(challenge), status=201)


@never_cache
@require_POST
@payload
def verify_email(request, data):
    code = field(data, 'code', 64).strip()
    with transaction.atomic():
        challenge = pending(request, lock=True)
        if not challenge or challenge.stage != 'email':
            return error(_('Verification expired. Start creating your account again.'), 401)
        if limited('email-verify', challenge.email, 10, 600):
            return rate_error('email-verify', challenge.email, 600, _('Too many attempts. Please try again later.'))
        challenge.attempts += 1
        challenge.save(update_fields=['attempts'])
        if not constant_time_compare(email_code_hash(challenge, code), challenge.email_code_hash):
            return error(_('Email code is incorrect. Check your email and try again.'), 400)
        if get_user_model().objects.filter(username=challenge.email).exists():
            discard(request)
            return error(_('An account already exists for this email. Please sign in.'), 409)
        challenge.stage = 'enroll'
        challenge.email_verified_at = timezone.now()
        challenge.email_code_hash = ''
        challenge.encrypted_key = Fernet(settings.MFA_ENCRYPTION_KEY.encode()).encrypt(secrets.token_bytes(20))
        challenge.attempts = 0
        challenge.expires_at = timezone.now() + timedelta(minutes=10)
        challenge.save()
        return JsonResponse(challenge_json(challenge))


@never_cache
@require_POST
def resend_email(request):
    if not signup_available():
        return error(_('Email delivery is not available. Please try again later.'), 503)
    with transaction.atomic():
        challenge = pending(request, lock=True)
        if not challenge or challenge.stage != 'email':
            return error(_('Verification expired. Start creating your account again.'), 401)
        if (timezone.now() - challenge.email_sent_at).total_seconds() < 60:
            return error(_('Wait a minute before requesting another email.'), 429, code='rate_limited', retry_after=60 - (timezone.now() - challenge.email_sent_at).total_seconds())
        limit = mail_limit(challenge.email)
        if limit is not None:
            return limit
        code = f'{secrets.randbelow(1000000):06d}'
        try:
            send_verification(challenge, code)
        except (smtplib.SMTPException, OSError) as exc:
            record_failure(exc)
            return error(_('We could not send your verification email. Please try again later.'), 503, code='email_unavailable', retry_after=60)
        challenge.email_code_hash = email_code_hash(challenge, code)
        challenge.email_sent_at = timezone.now()
        # Resending neither extends expiry nor resets the attempt budget.
        challenge.save(update_fields=['email_code_hash', 'email_sent_at'])
        return JsonResponse({'ok': True})


@never_cache
@require_POST
@payload
def finish_signup(request, data):
    if not settings.SIGNUP_ENABLED:
        return error(_('Account creation is not available.'), 503)
    code = field(data, 'code', 64).strip()
    try:
        with transaction.atomic():
            challenge = pending(request, lock=True)
            if not challenge or challenge.stage != 'enroll' or not challenge.email_verified_at:
                return error(_('Setup expired. Start creating your account again.'), 401)
            if limited('signup-totp', challenge.email, 10, 600):
                return rate_error('signup-totp', challenge.email, 600, _('Too many attempts. Please try again later.'))
            challenge.attempts += 1
            challenge.save(update_fields=['attempts'])
            key = Fernet(settings.MFA_ENCRYPTION_KEY.encode()).decrypt(bytes(challenge.encrypted_key))
            totp = TOTP(key, step=30, digits=6)
            if not (len(code) == 6 and code.isascii() and code.isdigit() and totp.verify(int(code), tolerance=1)):
                return error(_('Authenticator code is incorrect. Check the setup key and try a new code.'), 400)
            user = get_user_model().objects.create(username=challenge.email, email=challenge.email,
                first_name=challenge.name, password=challenge.password_hash)
            device = Authenticator.objects.create(user=user, name='Authenticator', confirmed=True,
                encrypted_key=challenge.encrypted_key, last_t=totp.t())
            AccountProfile.objects.create(user=user, email_verified_at=challenge.email_verified_at)
            codes = [secrets.token_hex(10) for _ in range(8)]
            RecoveryCode.objects.bulk_create([RecoveryCode(user=user, digest=make_password(c)) for c in codes])
            challenge.delete()
            audit.info('signup_success user=%s', user.pk)
            return authenticated(request, user, device, codes)
    except IntegrityError:
        discard(request)
        return error(_('An account already exists for this email. Please sign in.'), 409)
