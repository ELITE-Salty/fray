import json
from datetime import date
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.db import IntegrityError, transaction
from django.test import Client, TestCase
from django_otp import DEVICE_ID_SESSION_KEY
from django_otp.oath import totp

from .models import Authenticator, Item, RecoveryCode, TimeEntry


class TrackingTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = get_user_model().objects.create_user('alex@example.org', password='A-safe-password-for-tests')
        self.other = get_user_model().objects.create_user('other@example.org', password='Another-safe-password')
        self.device = Authenticator(user=self.user, name='test', confirmed=True)
        self.secret = b'12345678901234567890'
        self.device.set_key(self.secret)
        self.device.save()
        self.item = Item.objects.create(owner=self.user, kind='project', name='Website')
        self.other_item = Item.objects.create(owner=self.other, kind='activity', name='Private')
        self.verify_session()

    def verify_session(self):
        self.client.force_login(self.user)
        session = self.client.session
        session[DEVICE_ID_SESSION_KEY] = self.device.persistent_id
        session.save()

    def post(self, path, data, method='post'):
        return getattr(self.client, method)(path, json.dumps(data), content_type='application/json')

    def entry(self, **kwargs):
        return {'item_id': str(self.item.pk), 'date': '2026-11-13', 'timezone': 'UTC',
                'mode': 'duration', 'minutes': 90, **kwargs}

    def test_password_session_without_mfa_is_denied(self):
        self.client.logout()
        self.client.force_login(self.user)
        for path in ['/api/auth/me', '/api/items', '/api/entries', '/api/reports/monthly']:
            self.assertEqual(self.client.get(path).status_code, 401)

    def test_totp_encrypted_and_replay_rejected(self):
        self.assertNotIn(self.secret, bytes(self.device.encrypted_key))
        self.client.logout()
        with patch('django_otp.oath.time', return_value=1800000000):
            code = f'{totp(self.secret):06d}'
            data = {'email': self.user.username, 'password': 'A-safe-password-for-tests', 'code': code}
            self.assertEqual(self.post('/api/auth/login', data).status_code, 200)
            self.assertEqual(self.client.get('/api/items').status_code, 200)
            self.post('/api/auth/logout', {})
            self.assertEqual(self.post('/api/auth/login', data).status_code, 401)

    def test_recovery_code_is_single_use(self):
        code = '0123456789abcdef0123'
        RecoveryCode.objects.create(user=self.user, digest=make_password(code))
        self.client.logout()
        data = {'email': self.user.username, 'password': 'A-safe-password-for-tests', 'code': code}
        self.assertEqual(self.post('/api/auth/login', data).status_code, 200)
        self.post('/api/auth/logout', {})
        self.assertEqual(self.post('/api/auth/login', data).status_code, 401)
        self.assertFalse(RecoveryCode.objects.exists())

    def test_login_rate_limit(self):
        for _ in range(10):
            self.assertEqual(self.post('/api/auth/login', {'email': 'missing@example.org'}).status_code, 401)
        self.assertEqual(self.post('/api/auth/login', {'email': 'missing@example.org'}).status_code, 429)

    def test_csrf_required_for_login_and_mutations(self):
        client = Client(enforce_csrf_checks=True)
        self.assertEqual(client.post('/api/auth/login', '{}', content_type='application/json').status_code, 403)
        csrf = client.get('/api/auth/csrf').json()['csrfToken']
        self.assertEqual(client.post('/api/auth/login', '{}', content_type='application/json', HTTP_X_CSRFTOKEN=csrf).status_code, 401)

    def test_private_items_and_entries(self):
        response = self.client.get('/api/items').json()
        self.assertEqual([i['id'] for i in response['items']], [str(self.item.pk)])
        self.assertEqual(self.post('/api/entries', self.entry(item_id=str(self.other_item.pk))).status_code, 404)
        self.assertEqual(self.post(f'/api/items/{self.other_item.pk}', {'name': 'stolen'}, 'patch').status_code, 404)
        other_entry = TimeEntry.objects.create(author=self.other, item=self.other_item, local_date=date(2026, 11, 13), mode='duration', duration_minutes=45, notes='Private note')
        for method in ('patch', 'delete'):
            self.assertEqual(self.post(f'/api/entries/{other_entry.pk}', self.entry(), method).status_code, 404)
        self.assertNotContains(self.client.get('/api/entries?month=2026-11'), 'Private note')

    def test_duration_has_no_fabricated_timestamps(self):
        response = self.post('/api/entries', self.entry())
        self.assertEqual(response.status_code, 201)
        self.assertIsNone(response.json()['start'])
        self.assertIsNone(response.json()['end'])
        self.assertEqual(response.json()['minutes'], 90)

    def test_invalid_durations(self):
        for value in (0, -3, 1441, True, '90', 1.5):
            self.assertEqual(self.post('/api/entries', self.entry(minutes=value)).status_code, 400)
        self.assertEqual(self.post('/api/entries', self.entry(start='2026-11-13T09:00:00Z')).status_code, 400)

    def test_overnight_and_overlap(self):
        data = self.entry(mode='timed', start='2026-11-13T23:00:00Z', end='2026-11-14T01:00:00Z')
        response = self.post('/api/entries', data)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()['minutes'], 120)
        self.assertEqual(self.post('/api/entries', data).status_code, 409)
        self.assertEqual(self.post('/api/entries/' + response.json()['id'], data, 'patch').status_code, 200)
        adjacent = self.entry(mode='timed', date='2026-11-14', start='2026-11-14T01:00:00Z', end='2026-11-14T02:00:00Z')
        self.assertEqual(self.post('/api/entries', adjacent).status_code, 201)

    def test_dst_elapsed_time_and_local_date(self):
        data = self.entry(mode='timed', date='2026-10-25', timezone='Europe/Ljubljana',
                          start='2026-10-25T02:30:00+02:00', end='2026-10-25T02:30:00+01:00')
        response = self.post('/api/entries', data)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()['minutes'], 60)
        self.assertEqual(self.post('/api/entries', {**data, 'date': '2026-10-26'}).status_code, 400)

    def test_naive_and_reversed_intervals_rejected(self):
        for start, end in [('2026-11-13T09:00:00', '2026-11-13T10:00:00'),
                           ('2026-11-13T10:00:00Z', '2026-11-13T09:00:00Z')]:
            self.assertEqual(self.post('/api/entries', self.entry(mode='timed', start=start, end=end)).status_code, 400)

    def test_archive_preserves_reports_but_blocks_new_time(self):
        self.post('/api/entries', self.entry())
        self.assertEqual(self.post(f'/api/items/{self.item.pk}', {'archived': True}, 'patch').status_code, 200)
        self.assertEqual(self.post('/api/entries', self.entry()).status_code, 400)
        self.assertEqual(self.client.get('/api/reports/monthly?month=2026-11').json()['total_minutes'], 90)

    def test_report_scope_month_and_csv_injection(self):
        self.item.name = '=HYPERLINK("bad")'
        self.item.save()
        self.post('/api/entries', self.entry(notes='Never export this'))
        self.post('/api/entries', self.entry(date='2026-12-01', minutes=20))
        TimeEntry.objects.create(author=self.other, item=self.other_item, local_date=date(2026, 11, 13), mode='duration', duration_minutes=600)
        report = self.client.get('/api/reports/monthly?month=2026-11').json()
        self.assertEqual(report['total_minutes'], 90)
        response = self.client.get('/api/reports/monthly?month=2026-11&format=csv')
        self.assertContains(response, "'=HYPERLINK")
        self.assertNotContains(response, 'Never export this')
        self.assertNotContains(response, 'Private')
        self.assertEqual(response.headers['Cache-Control'], 'no-store')

    def test_malformed_requests_return_client_errors(self):
        self.assertEqual(self.post('/api/entries', self.entry(item_id='invalid')).status_code, 400)
        self.assertEqual(self.post('/api/entries', []).status_code, 400)
        self.assertEqual(self.post('/api/items', {'name': 123}).status_code, 400)
        self.assertEqual(self.client.get('/api/entries?month=garbage').status_code, 400)
        self.assertEqual(self.client.get('/api/reports/monthly?month=2026-99').status_code, 400)

    def test_database_constraints(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            TimeEntry.objects.create(author=self.user, item=self.item, local_date=date.today(), mode='duration', duration_minutes=0)

    def test_health_and_metrics(self):
        self.assertEqual(self.client.get('/api/health').json(), {'status': 'ok'})
        self.assertContains(self.client.get('/metrics'), 'fray_http_requests_total')
        with patch('tracker.views.cache.get', return_value=None):
            self.assertEqual(self.client.get('/api/health').status_code, 503)

    def test_localized_csv_keeps_user_content_and_json_enums(self):
        self.item.name = 'Moj čudoviti projekt'
        self.item.save()
        self.assertEqual(self.post('/api/entries', self.entry()).status_code, 201)
        for language, header, kind in [
            ('sl', 'Projekt / dejavnost,Vrsta,Minute', 'Projekt'),
            ('hr', 'Projekt / aktivnost,Vrsta,Minute', 'Projekt'),
            ('en', 'Project / activity,Type,Minutes', 'project'),
        ]:
            response = self.client.get('/api/reports/monthly?month=2026-11&format=csv', HTTP_ACCEPT_LANGUAGE=language)
            text = response.content.decode('utf-8-sig')
            self.assertTrue(text.startswith(header))
            self.assertIn(f'Moj čudoviti projekt,{kind},90', text)
            result = self.client.get('/api/reports/monthly?month=2026-11', HTTP_ACCEPT_LANGUAGE=language).json()
            self.assertEqual(result['items'][0]['item__kind'], 'project')
            self.assertEqual(result['items'][0]['item__name'], self.item.name)
