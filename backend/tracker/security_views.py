"""Account recovery and sensitive operations require email/MFA or fresh reauthentication."""
import base64
import secrets
import smtplib
from datetime import timedelta
from urllib.parse import quote, urlencode

from cryptography.fernet import Fernet
from django.conf import settings
from django.contrib.auth import get_user_model, logout, update_session_auth_hash
from django.contrib.auth.hashers import check_password, make_password
from django.contrib.auth.password_validation import validate_password
from django.core.mail import send_mail
from django.core.validators import validate_email
from django.db import transaction
from django.http import JsonResponse
from django.middleware.csrf import get_token
from django.utils import timezone
from django.utils.crypto import constant_time_compare
from django.utils.translation import gettext as _
from django.views.decorators.cache import never_cache
from django.views.decorators.http import require_POST
from django_otp import login as otp_login
from django_otp.oath import TOTP

from .auth_views import bind, pending, field, email_code_hash, limited, rate_error
from .mail_support import record_failure, MAIL
from .models import AccountProfile, AuthChallenge, Authenticator, RecoveryCode, Item, TimeEntry, ProjectInvitation
from .views import private, payload, error, audit


def verify_second_factor(user, token):
    device = Authenticator.objects.select_for_update().filter(user=user, confirmed=True).first()
    if not device:
        return False
    if len(token) == 6 and token.isascii() and token.isdigit():
        return device.verify_token(token)
    if 16 <= len(token) <= 64:
        for recovery in RecoveryCode.objects.select_for_update().filter(user=user):
            if check_password(token, recovery.digest):
                recovery.delete()
                return True
    return False


def reauthenticate(user, data):
    return user.check_password(field(data, 'password', 1024)) and verify_second_factor(user, field(data, 'code', 64).strip())


def new_recovery_codes(user):
    codes = [secrets.token_hex(10) for _ in range(8)]
    RecoveryCode.objects.filter(user=user).delete()
    RecoveryCode.objects.bulk_create([RecoveryCode(user=user, digest=make_password(code)) for code in codes])
    return codes


def security_limit(user):
    if limited('security', str(user.pk), 10, 300):
        return rate_error('security', str(user.pk), 300, _('Too many attempts. Wait five minutes.'))
    return None


@never_cache
@require_POST
@payload
def reset_request(request, data):
    # Recovery stays available even if self-service registration is switched off.
    ready = settings.DEBUG or (settings.EMAIL_HOST and settings.EMAIL_HOST_USER and
        settings.EMAIL_HOST_PASSWORD and settings.DEFAULT_FROM_EMAIL and (settings.EMAIL_USE_TLS or settings.EMAIL_USE_SSL))
    if not ready:
        return error(_('Email delivery is not available. Please try again later.'), 503, code='email_unavailable')
    email = field(data, 'email', 150).strip().lower()
    validate_email(email)
    if limited('reset-email', email, 3, 600):
        return rate_error('reset-email', email, 600, _('Too many verification emails. Please try again later.'))
    if limited('signup-total', 'all', settings.SIGNUP_EMAIL_LIMIT, 3600):
        return rate_error('signup-total', 'all', 3600, _('Too many verification emails. Please try again later.'))
    user = get_user_model().objects.filter(username=email, is_active=True).first()
    if user and not user.has_usable_password():
        user = None
    code = f'{secrets.randbelow(1000000):06d}'
    challenge = AuthChallenge(user=user, stage='reset', email=email,
        password_hash=user.get_session_auth_hash() if user else '',
        expires_at=timezone.now() + timedelta(minutes=10))
    challenge.email_code_hash = email_code_hash(challenge, code)
    challenge.save()
    bind(request, challenge)
    if user:
        try:
            sent = send_mail(_('Reset your Fray password'),
                _('Your password reset code is: %(code)s\n\nIt expires in 10 minutes. Your authenticator or a recovery code is also required. If you did not request this, ignore this email.') % {'code': code},
                settings.DEFAULT_FROM_EMAIL, [email], fail_silently=False)
            if sent != 1:
                raise OSError('Mail not accepted')
            MAIL.labels('sent').inc()
        except (smtplib.SMTPException, OSError) as exc:
            # Same public response for unknown users and delivery failures.
            record_failure(exc)
    return JsonResponse({'stage': 'reset', 'email': email, 'expiresAt': challenge.expires_at.isoformat(),
        'message': _('If this account exists, a reset code has been sent. Check your spam folder too.')})


@never_cache
@require_POST
@payload
def reset_finish(request, data):
    with transaction.atomic():
        challenge = pending(request, lock=True)
        if not challenge or challenge.stage != 'reset':
            return error(_('Password reset expired. Request a new code.'), 401)
        challenge.attempts += 1
        challenge.save(update_fields=['attempts'])
        user = get_user_model().objects.select_for_update().filter(pk=challenge.user_id, is_active=True).first()
        if not user or not constant_time_compare(challenge.password_hash, user.get_session_auth_hash()) or not constant_time_compare(
                challenge.email_code_hash, email_code_hash(challenge, field(data, 'emailCode', 64).strip())):
            return error(_('The reset code or security code is incorrect.'))
        password = field(data, 'newPassword', 1024)
        validate_password(password, user)
        if not verify_second_factor(user, field(data, 'code', 64).strip()):
            return error(_('The reset code or security code is incorrect.'))
        user.set_password(password)
        user.save(update_fields=['password'])
        AccountProfile.objects.update_or_create(user=user, defaults={'email_verified_at': timezone.now()})
        challenge.delete()
        logout(request)
        audit.info('password_reset user=%s', user.pk)
    return JsonResponse({'ok': True, 'csrfToken': get_token(request)})


@never_cache
@require_POST
@private
@payload
def account_action(request, data, action):
    if action not in ['password', 'recovery', 'rotate', 'delete']:
        return error(_('Invalid request.'))
    limit = security_limit(request.user)
    if limit is not None:
        return limit
    with transaction.atomic():
        user = get_user_model().objects.select_for_update().get(pk=request.user.pk)
        if action == 'delete':
            if data.get('confirmation') != 'DELETE':
                return error(_('Type DELETE to confirm account deletion.'))
            if Item.objects.filter(owner=user, memberships__isnull=False).exists() or TimeEntry.objects.filter(item__owner=user).exclude(author=user).exists():
                return error(_('Transfer ownership of shared projects before deleting your account.'), 409)
        if action == 'password':
            password = field(data, 'newPassword', 1024)
            validate_password(password, user)
        if not reauthenticate(user, data):
            return error(_('Password or security code is incorrect.'), 400)
        if action == 'password':
            user.set_password(password)
            user.save(update_fields=['password'])
            update_session_auth_hash(request, user)
            result = {'ok': True, 'csrfToken': get_token(request)}
        elif action == 'recovery':
            result = {'recoveryCodes': new_recovery_codes(user)}
        elif action == 'rotate':
            AuthChallenge.objects.filter(user=user, stage='rotate').delete()
            key = secrets.token_bytes(20)
            challenge = AuthChallenge.objects.create(user=user, stage='rotate', email=user.username,
                password_hash=user.get_session_auth_hash(), encrypted_key=Fernet(settings.MFA_ENCRYPTION_KEY.encode()).encrypt(key),
                expires_at=timezone.now() + timedelta(minutes=5))
            request.session['fray_rotate'] = str(challenge.pk)
            secret = base64.b32encode(key).decode().rstrip('=')
            result = {'secret': secret, 'uri': 'otpauth://totp/' + quote('Fray:' + user.username, safe='') + '?' +
                urlencode({'secret': secret, 'issuer': 'Fray', 'digits': 6, 'period': 30})}
        else:
            TimeEntry.objects.filter(author=user).delete()
            Item.objects.filter(owner=user).delete()
            ProjectInvitation.objects.filter(email=user.username).delete()
            user_id = user.pk
            user.delete()
            logout(request)
            audit.info('account_deleted user=%s', user_id)
            return JsonResponse({'ok': True, 'csrfToken': get_token(request)})
        audit.info('security_change user=%s action=%s', user.pk, action)
        return JsonResponse(result)


@never_cache
@require_POST
@private
@payload
def rotate_finish(request, data):
    limit = security_limit(request.user)
    if limit is not None:
        return limit
    with transaction.atomic():
        user = get_user_model().objects.select_for_update().get(pk=request.user.pk)
        challenge = AuthChallenge.objects.select_for_update().filter(pk=request.session.get('fray_rotate'), user=user, stage='rotate').first()
        if not challenge or challenge.expires_at <= timezone.now() or challenge.attempts >= 5 or not constant_time_compare(challenge.password_hash, user.get_session_auth_hash()):
            return error(_('Authenticator setup expired. Start again.'), 400)
        challenge.attempts += 1
        challenge.save(update_fields=['attempts'])
        key = Fernet(settings.MFA_ENCRYPTION_KEY.encode()).decrypt(bytes(challenge.encrypted_key))
        code = field(data, 'code', 64).strip()
        totp = TOTP(key, step=30, digits=6)
        if not (len(code) == 6 and code.isascii() and code.isdigit() and totp.verify(int(code), tolerance=1)):
            return error(_('Authenticator code is incorrect. Check the setup key and try a new code.'))
        Authenticator.objects.filter(user=user).delete()
        device = Authenticator(user=user, name='Fray', confirmed=True, last_t=totp.t())
        device.set_key(key)
        device.save()
        codes = new_recovery_codes(user)
        challenge.delete()
        request.session.pop('fray_rotate', None)
        request.session.cycle_key()
        otp_login(request, device)
        audit.info('authenticator_replaced user=%s', user.pk)
        return JsonResponse({'recoveryCodes': codes, 'csrfToken': get_token(request)})
