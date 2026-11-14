import json
import re
import secrets
import socket
import uuid
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core import mail
from django.core.cache import cache
from django.test import TestCase, Client, override_settings
from django.utils import timezone
from django_otp import DEVICE_ID_SESSION_KEY
from django_otp.oath import totp

from .models import AccountProfile, AuthChallenge, Authenticator, RecoveryCode, TimeEntry, Item, ProjectMember, ProjectInvitation
from .tests import TrackingTests
from .test_auth import MAIL_SETTINGS, PASSWORD


@override_settings(**MAIL_SETTINGS)
class FeatureTests(TestCase):
    setUp = TrackingTests.setUp
    verify_session = TrackingTests.verify_session
    post = TrackingTests.post
    entry = TrackingTests.entry

    def proof(self):
        code = secrets.token_hex(10)
        RecoveryCode.objects.create(user=self.user, digest=make_password(code))
        return {'password': 'A-safe-password-for-tests', 'code': code}

    def verified_client(self, user):
        client = Client()
        device = Authenticator(user=user, name='test', confirmed=True)
        device.set_key(b'other1234567890123456')
        device.save()
        client.force_login(user)
        session = client.session
        session[DEVICE_ID_SESSION_KEY] = device.persistent_id
        session.save()
        return client

    def test_retry_metadata_and_safe_mail_diagnostics(self):
        client = Client()
        with patch('tracker.auth_views.send_verification', side_effect=socket.gaierror(-3, 'SECRET-MUST-NOT-APPEAR')):
            with self.assertLogs('fray.audit', 'WARNING') as logs:
                response = client.post('/api/auth/signup', json.dumps({'email': 'blocked@example.test', 'password': PASSWORD}), content_type='application/json')
            self.assertIn('reason=dns', ' '.join(logs.output))
            self.assertNotIn('SECRET-MUST-NOT-APPEAR', ' '.join(logs.output))
            self.assertEqual(response.json()['code'], 'email_unavailable')
            for _ in range(2):
                client.post('/api/auth/signup', json.dumps({'email': 'blocked@example.test', 'password': PASSWORD}), content_type='application/json')
            response = client.post('/api/auth/signup', json.dumps({'email': 'blocked@example.test', 'password': PASSWORD}), content_type='application/json')
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.json()['code'], 'rate_limited')
        self.assertTrue(1 <= response.json()['retryAfter'] <= 600)
        self.assertEqual(response.headers['Retry-After'], str(response.json()['retryAfter']))

    def test_reset_unknown_account_uses_same_public_response(self):
        for email in [self.user.username, 'missing@example.test']:
            response = self.post('/api/auth/password/request', {'email': email})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()['stage'], 'reset')
            self.assertIn('If this account exists', response.json()['message'])
        self.assertEqual(len(mail.outbox), 1)

    def test_password_reset_requires_both_proofs_and_invalidates_old_sessions(self):
        other_session = Client()
        other_session.force_login(self.user)
        self.post('/api/auth/password/request', {'email': self.user.username})
        code = re.search(r'\b\d{6}\b', mail.outbox[-1].body).group()
        body = {'emailCode': code, 'newPassword': PASSWORD, 'code': 'wrong'}
        self.assertEqual(self.post('/api/auth/password/reset', body).status_code, 400)
        body['code'] = self.proof()['code']
        self.assertEqual(self.post('/api/auth/password/reset', body).status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(PASSWORD))
        self.assertEqual(other_session.get('/api/items').status_code, 401)
        self.assertEqual(self.post('/api/auth/password/reset', body).status_code, 401)

    def test_reset_is_session_bound_and_expires(self):
        self.post('/api/auth/password/request', {'email': self.user.username})
        code = re.search(r'\b\d{6}\b', mail.outbox[-1].body).group()
        body = {'emailCode': code, 'newPassword': PASSWORD, 'code': self.proof()['code']}
        self.assertEqual(Client().post('/api/auth/password/reset', json.dumps(body), content_type='application/json').status_code, 401)
        AuthChallenge.objects.filter(stage='reset').update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.post('/api/auth/password/reset', body).status_code, 401)

    def test_change_password_keeps_current_verified_session(self):
        proof = self.proof()
        response = self.post('/api/account/password', {**proof, 'newPassword': PASSWORD})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.get('/api/items').status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(PASSWORD))

    def test_regenerate_codes_requires_password_and_mfa(self):
        proof = self.proof()
        response = self.post('/api/account/recovery', {**proof, 'password': 'wrong'})
        self.assertEqual(response.status_code, 400)
        response = self.post('/api/account/recovery', proof)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()['recoveryCodes']), 8)
        self.assertEqual(RecoveryCode.objects.filter(user=self.user).count(), 8)
        self.assertEqual(self.post('/api/account/recovery', proof).status_code, 400)

    def test_replace_authenticator_keeps_old_until_confirmation(self):
        old_session = Client()
        old_session.force_login(self.user)
        session = old_session.session
        session[DEVICE_ID_SESSION_KEY] = self.device.persistent_id
        session.save()
        response = self.post('/api/account/rotate', self.proof())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Authenticator.objects.get(user=self.user).pk, self.device.pk)
        self.assertEqual(self.post('/api/account/authenticator/finish', {'code': 'wrong'}).status_code, 400)
        import base64
        secret = response.json()['secret']
        key = base64.b32decode(secret + '=' * (-len(secret) % 8))
        response = self.post('/api/account/authenticator/finish', {'code': f'{totp(key):06d}'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()['recoveryCodes']), 8)
        self.assertNotEqual(Authenticator.objects.get(user=self.user).pk, self.device.pk)
        self.assertEqual(old_session.get('/api/items').status_code, 401)
        self.assertEqual(self.client.get('/api/items').status_code, 200)

    def test_delete_account_removes_personal_records_and_requires_confirmation(self):
        self.post('/api/entries', self.entry())
        proof = self.proof()
        self.assertEqual(self.post('/api/account/delete', proof).status_code, 400)
        response = self.post('/api/account/delete', {**proof, 'confirmation': 'DELETE'})
        self.assertEqual(response.status_code, 200)
        self.assertFalse(get_user_model().objects.filter(pk=self.user.pk).exists())
        self.assertFalse(TimeEntry.objects.filter(author_id=self.user.pk).exists())
        self.assertTrue(get_user_model().objects.filter(pk=self.other.pk).exists())

    def test_shared_ownership_blocks_account_deletion(self):
        ProjectMember.objects.create(item=self.item, user=self.other)
        response = self.post('/api/account/delete', {**self.proof(), 'confirmation': 'DELETE'})
        self.assertEqual(response.status_code, 409)
        self.assertTrue(get_user_model().objects.filter(pk=self.user.pk).exists())

    def test_offline_create_is_idempotent_and_payload_changes_conflict(self):
        body = self.entry(operation=str(uuid.uuid4()))
        first = self.post('/api/entries', body)
        second = self.post('/api/entries', body)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()['id'], second.json()['id'])
        self.assertEqual(TimeEntry.objects.filter(author=self.user).count(), 1)
        self.assertEqual(self.post('/api/entries', {**body, 'notes': 'different'}).status_code, 409)
        self.client.delete('/api/entries/' + first.json()['id'])
        self.assertEqual(self.post('/api/entries', body).status_code, 409)
        self.assertFalse(TimeEntry.objects.filter(author=self.user).exists())

    def test_stale_entry_revision_does_not_overwrite_or_delete(self):
        first = self.post('/api/entries', self.entry()).json()
        response = self.post('/api/entries/' + first['id'], {**self.entry(), 'notes': 'new', 'revision': 1}, 'patch')
        self.assertEqual(response.json()['revision'], 2)
        stale = self.post('/api/entries/' + first['id'], {**self.entry(), 'notes': 'old', 'revision': 1}, 'patch')
        self.assertEqual(stale.status_code, 409)
        self.assertEqual(stale.json()['code'], 'sync_conflict')
        deleted = self.client.delete('/api/entries/' + first['id'], json.dumps({'revision': 1}), content_type='application/json')
        self.assertEqual(deleted.status_code, 409)
        self.assertEqual(TimeEntry.objects.get(pk=first['id']).notes, 'new')

    def test_templates_and_goals_are_private_and_validated(self):
        template = self.post('/api/templates', {'item_id': str(self.item.pk), 'name': 'Study', 'minutes': 45, 'notes': 'private'}).json()
        other = self.verified_client(self.other)
        self.assertEqual(other.get('/api/templates').json()['templates'], [])
        self.assertEqual(other.delete('/api/templates/' + template['id']).status_code, 404)
        self.assertEqual(self.post('/api/templates', {'item_id': str(self.other_item.pk), 'name': 'Denied', 'minutes': 45}).status_code, 404)
        self.assertEqual(self.post('/api/preferences', {'weeklyGoalMinutes': True}, 'patch').status_code, 400)
        self.assertEqual(self.post('/api/preferences', {'weeklyGoalMinutes': 300}, 'patch').status_code, 200)
        self.assertEqual(self.client.get('/api/preferences').json()['weeklyGoalMinutes'], 300)
        self.assertEqual(other.get('/api/preferences').json()['weeklyGoalMinutes'], 0)

    def test_shared_members_only_see_aggregate_and_own_entries(self):
        ProjectMember.objects.create(item=self.item, user=self.other)
        self.post('/api/entries', self.entry(notes='owner private note'))
        other = self.verified_client(self.other)
        listed = other.get('/api/items').json()['items']
        self.assertEqual(next(i for i in listed if i['id'] == str(self.item.pk))['role'], 'member')
        response = other.post('/api/entries', json.dumps(self.entry(minutes=30, notes='member private note')), content_type='application/json')
        self.assertEqual(response.status_code, 201)
        own = other.get('/api/entries?month=2026-11').json()['entries']
        self.assertEqual(len(own), 1)
        self.assertEqual(own[0]['notes'], 'member private note')
        aggregate = other.get(f'/api/projects/{self.item.pk}?month=2026-11').json()
        self.assertEqual(aggregate['totalMinutes'], 120)
        self.assertNotIn('owner private note', json.dumps(aggregate))
        self.assertNotIn('member private note', json.dumps(aggregate))
        self.assertEqual(other.patch('/api/items/' + str(self.item.pk), json.dumps({'name': 'Changed'}), content_type='application/json').status_code, 404)
        self.post('/api/projects/' + str(self.item.pk), {'action': 'remove', 'userId': self.other.pk})
        self.assertEqual(other.get('/api/projects/' + str(self.item.pk)).status_code, 403)
        self.assertEqual(other.post('/api/entries', json.dumps(self.entry()), content_type='application/json').status_code, 404)
        historical = next(i for i in other.get('/api/items').json()['items'] if i['id'] == str(self.item.pk))
        self.assertEqual(historical['role'], 'history')
        self.assertFalse(historical['canLog'])
        self.assertEqual(len(other.get('/api/entries?month=2026-11').json()['entries']), 1)

    def test_invitation_acceptance_bound_to_verified_identity_and_transfer(self):
        response = self.post('/api/projects/' + str(self.item.pk), {'action': 'invite', 'email': self.other.username})
        self.assertEqual(response.status_code, 200)
        invitation = ProjectInvitation.objects.get(item=self.item)
        self.assertEqual(self.post('/api/invitations', {'id': str(invitation.pk), 'accept': True}).status_code, 404)
        other = self.verified_client(self.other)
        self.assertEqual(len(other.get('/api/invitations').json()['invitations']), 1)
        accepted = other.post('/api/invitations', json.dumps({'id': str(invitation.pk), 'accept': True}), content_type='application/json')
        self.assertEqual(accepted.status_code, 403)
        AccountProfile.objects.create(user=self.other, email_verified_at=timezone.now())
        accepted = other.post('/api/invitations', json.dumps({'id': str(invitation.pk), 'accept': True}), content_type='application/json')
        self.assertEqual(accepted.status_code, 200)
        self.assertTrue(ProjectMember.objects.filter(item=self.item, user=self.other).exists())
        self.assertFalse(ProjectInvitation.objects.filter(pk=invitation.pk).exists())
        self.assertEqual(self.post('/api/projects/' + str(self.item.pk), {'action': 'transfer', 'userId': self.other.pk}).status_code, 200)
        self.item.refresh_from_db()
        self.assertEqual(self.item.owner_id, self.other.pk)
        self.assertTrue(ProjectMember.objects.filter(item=self.item, user=self.user).exists())
        self.assertEqual(self.post('/api/projects/' + str(self.item.pk), {'action': 'remove', 'userId': self.other.pk}).status_code, 403)
