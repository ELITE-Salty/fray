import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
import json
import re
from threading import Barrier
from unittest import skipUnless
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core import mail
from django.core.cache import cache
from django.db import close_old_connections, connection
from django.test import Client, TestCase, TransactionTestCase, override_settings
from django.utils import timezone
from django_otp.oath import totp

from .models import AccountProfile, AuthChallenge, Authenticator, RecoveryCode

PASSWORD = 'A-private-testing-password-927!'
MAIL_SETTINGS = dict(DEBUG=False, SECURE_SSL_REDIRECT=False, SIGNUP_ENABLED=True,
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend', EMAIL_HOST='smtp.example.test',
    EMAIL_HOST_USER='test-key', EMAIL_HOST_PASSWORD='test-secret', DEFAULT_FROM_EMAIL='fray@example.test')


@override_settings(**MAIL_SETTINGS)
class AuthenticationTests(TestCase):
    def setUp(self):
        cache.clear()

    def post(self, path, data=None, client=None):
        return (client or self.client).post('/api/auth/' + path, json.dumps(data or {}), content_type='application/json')

    def existing(self):
        user = get_user_model().objects.create_user('existing@example.test', password=PASSWORD)
        device = Authenticator(user=user, name='test', confirmed=True)
        device.set_key(b'12345678901234567890')
        device.save()
        return user, device

    def start_login(self, user):
        return self.post('login/start', {'email': user.username, 'password': PASSWORD})

    def signup(self, email='new@example.test'):
        return self.post('signup', {'email': email, 'password': PASSWORD, 'name': 'New Person'})

    def email_code(self):
        return re.search(r'code is: (\d{6})', mail.outbox[-1].body).group(1)

    def enroll(self):
        self.assertEqual(self.signup().status_code, 201)
        response = self.post('signup/email', {'code': self.email_code()})
        self.assertEqual(response.status_code, 200)
        return response.json()

    def test_password_then_mfa_and_consumed_challenge(self):
        user, device = self.existing()
        self.assertEqual(self.start_login(user).json()['stage'], 'mfa')
        self.assertNotIn('_auth_user_id', self.client.session)
        self.assertEqual(self.client.get('/api/items').status_code, 401)
        self.assertEqual(self.client.get('/api/auth/challenge').json()['stage'], 'mfa')
        self.assertEqual(self.post('login/verify', {'code': f'{totp(device.get_key()):06d}'}, Client()).status_code, 401)
        with patch('django_otp.oath.time', return_value=1800000000):
            code = f'{totp(device.get_key()):06d}'
            response = self.post('login/verify', {'code': code})
            self.assertEqual(response.status_code, 200)
            self.assertIn('no-store', response.headers['Cache-Control'])
            self.assertEqual(self.client.get('/api/items').status_code, 200)
            self.assertEqual(self.post('login/verify', {'code': code}).status_code, 401)
            self.post('logout')
            self.start_login(user)
            self.assertEqual(self.post('login/verify', {'code': code}).status_code, 400)

    def test_password_failure_and_cancellation(self):
        user, _ = self.existing()
        self.assertEqual(self.post('login/start', {'email': user.username, 'password': 'wrong'}).status_code, 401)
        self.assertFalse(AuthChallenge.objects.exists())
        self.start_login(user)
        self.post('cancel')
        self.assertFalse(AuthChallenge.objects.exists())
        self.assertEqual(self.client.get('/api/auth/challenge').json()['stage'], 'credentials')

    def test_expiry_password_change_and_disabled_user(self):
        user, device = self.existing()
        code = f'{totp(device.get_key()):06d}'
        self.start_login(user)
        AuthChallenge.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.post('login/verify', {'code': code}).status_code, 401)
        self.start_login(user)
        user.set_password('A-different-new-password-824!')
        user.save()
        self.assertEqual(self.post('login/verify', {'code': code}).status_code, 401)
        user.set_password(PASSWORD)
        user.save()
        self.start_login(user)
        user.is_active = False
        user.save()
        self.assertEqual(self.post('login/verify', {'code': code}).status_code, 401)

    def test_bounded_attempts_and_single_use_recovery(self):
        user, _ = self.existing()
        recovery = '1234567890abcdef1234'
        RecoveryCode.objects.create(user=user, digest=make_password(recovery))
        self.start_login(user)
        for _ in range(5):
            self.assertEqual(self.post('login/verify', {'code': 'wrong'}).status_code, 400)
        self.assertEqual(self.post('login/verify', {'code': recovery}).status_code, 401)
        self.start_login(user)
        self.assertEqual(self.post('login/verify', {'code': recovery}).status_code, 200)
        self.post('logout')
        self.start_login(user)
        self.assertEqual(self.post('login/verify', {'code': recovery}).status_code, 400)
        self.assertFalse(RecoveryCode.objects.exists())

    def test_signup_requires_email_then_authenticator_before_creating_user(self):
        response = self.signup()
        self.assertEqual(response.status_code, 201)
        self.assertNotIn('secret', response.json())
        self.assertFalse(get_user_model().objects.exists())
        challenge = AuthChallenge.objects.get()
        self.assertNotEqual(challenge.password_hash, PASSWORD)
        self.assertNotEqual(challenge.email_code_hash, self.email_code())
        self.assertEqual(self.post('signup/finish', {'code': '123456'}).status_code, 401)
        self.assertEqual(self.post('signup/email', {'code': self.email_code()}, Client()).status_code, 401)
        enrollment = self.post('signup/email', {'code': self.email_code()}).json()
        self.assertEqual(enrollment['stage'], 'enroll')
        secret = base64.b32decode(enrollment['secret'])
        challenge.refresh_from_db()
        self.assertNotIn(secret, bytes(challenge.encrypted_key))
        self.assertEqual(challenge.email_code_hash, '')
        self.assertFalse(get_user_model().objects.exists())
        self.assertEqual(self.client.get('/api/auth/me').status_code, 401)
        self.assertEqual(self.post('signup/finish', {'code': 'invalid'}).status_code, 400)
        with patch('django_otp.oath.time', return_value=1800000000):
            response = self.post('signup/finish', {'code': f'{totp(secret):06d}'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()['recoveryCodes']), 8)
        self.assertIn('no-store', response.headers['Cache-Control'])
        self.assertTrue(AccountProfile.objects.get().email_verified_at)
        self.assertTrue(get_user_model().objects.get().check_password(PASSWORD))
        self.assertEqual(RecoveryCode.objects.count(), 8)
        self.assertFalse(AuthChallenge.objects.exists())
        self.assertEqual(self.client.get('/api/items').status_code, 200)
        self.assertEqual(self.post('signup/finish', {'code': '123456'}).status_code, 401)

    def test_email_attempt_budget_and_expiry(self):
        self.signup()
        valid = self.email_code()
        for _ in range(5):
            self.assertEqual(self.post('signup/email', {'code': 'wrong'}).status_code, 400)
        self.assertEqual(self.post('signup/email', {'code': valid}).status_code, 401)
        self.signup()
        AuthChallenge.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.post('signup/email', {'code': self.email_code()}).status_code, 401)
        self.assertFalse(get_user_model().objects.exists())

    def test_resend_rotates_code_without_resetting_budget_or_expiry(self):
        with patch('tracker.auth_views.secrets.randbelow', side_effect=[123456, 654321]):
            self.signup()
            self.assertEqual(self.post('signup/resend').status_code, 429)
            self.post('signup/email', {'code': 'wrong'})
            challenge = AuthChallenge.objects.get()
            expiry = challenge.expires_at
            AuthChallenge.objects.update(email_sent_at=timezone.now() - timedelta(seconds=61))
            self.assertEqual(self.post('signup/resend').status_code, 200)
        challenge.refresh_from_db()
        self.assertEqual(challenge.expires_at, expiry)
        self.assertEqual(challenge.attempts, 1)
        self.assertEqual(self.post('signup/email', {'code': '123456'}).status_code, 400)
        self.assertEqual(self.post('signup/email', {'code': '654321'}).status_code, 200)

    def test_existing_account_is_never_overwritten(self):
        user, _ = self.existing()
        self.assertEqual(self.signup(user.username).status_code, 201)
        self.assertEqual(self.post('signup/email', {'code': self.email_code()}).status_code, 409)
        self.assertEqual(get_user_model().objects.count(), 1)
        self.assertFalse(AccountProfile.objects.exists())
        user.refresh_from_db()
        self.assertTrue(user.check_password(PASSWORD))

    def test_duplicate_race_does_not_replace_account(self):
        enrollment = self.enroll()
        user = get_user_model().objects.create_user('new@example.test', password='Original-user-password-331!')
        secret = base64.b32decode(enrollment['secret'])
        self.assertEqual(self.post('signup/finish', {'code': f'{totp(secret):06d}'}).status_code, 409)
        user.refresh_from_db()
        self.assertTrue(user.check_password('Original-user-password-331!'))
        self.assertFalse(Authenticator.objects.exists())

    def test_email_failure_disabled_signup_and_missing_credentials(self):
        with patch('tracker.auth_views.send_mail', side_effect=OSError('failed')):
            self.assertEqual(self.signup().status_code, 503)
        self.assertFalse(AuthChallenge.objects.exists())
        with override_settings(SIGNUP_ENABLED=False):
            self.assertEqual(self.signup().status_code, 503)
        with override_settings(EMAIL_HOST_PASSWORD=''):
            self.assertEqual(self.signup().status_code, 503)
        self.assertFalse(get_user_model().objects.exists())

    def test_validation_email_limits_and_global_limit(self):
        self.assertEqual(self.post('signup', {'email': 'broken', 'password': PASSWORD}).status_code, 400)
        self.assertEqual(self.post('signup', {'email': 'valid@example.test', 'password': 'short'}).status_code, 400)
        self.assertEqual(self.post('signup', {'email': [], 'password': PASSWORD}).status_code, 400)
        with override_settings(SIGNUP_EMAIL_LIMIT=1):
            self.assertEqual(self.signup().status_code, 201)
            self.assertEqual(self.signup('another@example.test').status_code, 429)
        self.assertEqual(len(mail.outbox), 1)

    def test_csrf_required_for_every_new_mutation(self):
        client = Client(enforce_csrf_checks=True)
        for path in ['login/start', 'login/verify', 'signup', 'signup/email', 'signup/resend', 'signup/finish', 'cancel']:
            self.assertEqual(self.post(path, client=client).status_code, 403, path)


@skipUnless(connection.vendor == 'postgresql', 'Row-lock race requires PostgreSQL')
@override_settings(**MAIL_SETTINGS)
class ConcurrentLoginTests(TransactionTestCase):
    def test_same_challenge_and_recovery_code_cannot_authenticate_twice(self):
        cache.clear()
        user = get_user_model().objects.create_user('race@example.test', password=PASSWORD)
        device = Authenticator(user=user, name='test', confirmed=True)
        device.set_key(b'12345678901234567890')
        device.save()
        recovery = '1234567890abcdef1234'
        RecoveryCode.objects.create(user=user, digest=make_password(recovery))
        self.client.post('/api/auth/login/start', json.dumps({'email': user.username, 'password': PASSWORD}), content_type='application/json')
        cookie = self.client.cookies['sessionid'].value
        barrier = Barrier(2)
        def verify():
            close_old_connections()
            try:
                client = Client()
                client.cookies['sessionid'] = cookie
                barrier.wait(timeout=10)
                return client.post('/api/auth/login/verify', json.dumps({'code': recovery}), content_type='application/json').status_code
            finally:
                close_old_connections()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: verify(), range(2)))
        self.assertEqual(sorted(results), [200, 401])
        self.assertFalse(RecoveryCode.objects.exists())
