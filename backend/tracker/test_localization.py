import json
import re

from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings

from .test_auth import MAIL_SETTINGS, PASSWORD


@override_settings(**MAIL_SETTINGS)
class LocalizationTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_errors_follow_requested_language_and_unsupported_falls_back(self):
        for language, message in [
            ('sl-SI', 'E-poštni naslov ali geslo ni pravilno.'),
            ('hr-HR', 'Adresa e-pošte ili lozinka nije ispravna.'),
            ('de', 'Email or password is incorrect.'),
        ]:
            response = self.client.post('/api/auth/login/start', json.dumps({
                'email': 'missing@example.test', 'password': 'wrong',
            }), content_type='application/json', HTTP_ACCEPT_LANGUAGE=language)
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response.json()['error'], message)
            self.assertIn('Accept-Language', response.headers['Vary'])

    def test_signup_mail_and_verification_use_selected_language(self):
        for language, subject, phrase in [
            ('sl', 'Vaša potrditvena koda Fray', 'Kode nikoli ne delite'),
            ('hr', 'Vaš kod za potvrdu za Fray', 'Nikada ne dijelite'),
        ]:
            response = self.client.post('/api/auth/signup', json.dumps({
                'email': f'{language}@example.test', 'password': PASSWORD,
            }), content_type='application/json', HTTP_ACCEPT_LANGUAGE=language)
            self.assertEqual(response.status_code, 201)
            self.assertEqual(mail.outbox[-1].subject, subject)
            self.assertIn(phrase, mail.outbox[-1].body)
            code = re.search(r'\b\d{6}\b', mail.outbox[-1].body).group()
            verified = self.client.post('/api/auth/signup/email', json.dumps({'code': code}),
                content_type='application/json', HTTP_ACCEPT_LANGUAGE=language)
            self.assertEqual(verified.json()['stage'], 'enroll')
            self.assertNotIn('_auth_user_id', self.client.session)

    def test_django_password_validation_is_localized(self):
        response = self.client.post('/api/auth/signup', json.dumps({
            'email': 'weak@example.test', 'password': '123',
        }), content_type='application/json', HTTP_ACCEPT_LANGUAGE='sl')
        self.assertEqual(response.status_code, 400)
        self.assertNotIn('This password', response.json()['error'])
        self.assertNotIn("['", response.json()['error'])
