import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from unittest.mock import patch

from allauth.account.models import EmailAddress, EmailConfirmationHMAC
from allauth.mfa.models import Authenticator
from allauth.mfa.recovery_codes.internal.auth import RecoveryCodes
from allauth.mfa.totp.internal.auth import TOTP, format_hotp_value, hotp_value
from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.db import IntegrityError, close_old_connections, connection, transaction
from django.test import Client, TestCase, TransactionTestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from .forms import TargetForm
from .models import Activity, Entry, Membership, Profile, Project
from .services import start_timer

PASSWORD = "Example-time-tracker-483!"
SECRET = "JBSWY3DPEHPK3PXP"


def user(email="alice@example.test", mfa=True, verified=True):
    u = get_user_model().objects.create_user(username=email, email=email, password=PASSWORD)
    EmailAddress.objects.create(user=u, email=email, primary=True, verified=verified)
    if mfa:
        TOTP.activate(u, SECRET)
    return u


def code():
    return format_hotp_value(hotp_value(SECRET, int(time.time()) // 30))


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class AuthenticationTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_signup_verification_and_enrollment_gate(self):
        response = self.client.post(
            reverse("account_signup"), {"email": "new@example.test", "password1": PASSWORD, "password2": PASSWORD}
        )
        self.assertEqual(response.status_code, 302)
        account = get_user_model().objects.get(email="new@example.test")
        self.assertFalse(EmailAddress.objects.get(user=account).verified)
        self.assertTrue(mail.outbox)
        self.assertIn("confirm-email", mail.outbox[0].body)
        self.assertFalse(self.client.session.get("_auth_user_id"))
        address = EmailAddress.objects.get(user=account)
        key = EmailConfirmationHMAC(address).key
        response = self.client.post(reverse("account_confirm_email", args=[key]))
        address.refresh_from_db()
        self.assertTrue(address.verified)
        self.client.force_login(account)
        response = self.client.get("/")
        self.assertRedirects(response, reverse("mfa_activate_totp"), fetch_redirect_response=False)
        self.assertRedirects(
            self.client.post("/timer/start/", {"description": "Bypass attempt"}),
            reverse("mfa_activate_totp"),
            fetch_redirect_response=False,
        )
        self.assertEqual(Entry.objects.count(), 0)
        # Enroll through the actual allauth view, using its session secret.
        self.client.post(reverse("account_logout"))
        self.client.post(reverse("account_login"), {"login": account.email, "password": PASSWORD})
        self.client.post(
            reverse("account_reauthenticate") + "?next=" + reverse("mfa_activate_totp"), {"password": PASSWORD}
        )
        self.assertEqual(self.client.get(reverse("mfa_activate_totp")).status_code, 200)
        secret = self.client.session["mfa.totp.secret"]
        enrollment_code = format_hotp_value(hotp_value(secret, int(time.time()) // 30))
        response = self.client.post(reverse("mfa_activate_totp"), {"code": enrollment_code})
        self.assertEqual(response.status_code, 302)
        self.assertTrue(Authenticator.objects.filter(user=account, type="totp").exists())
        self.assertEqual(self.client.get("/").status_code, 200)

    def test_unverified_email_cannot_access_app_even_with_session(self):
        account = user(verified=False)
        self.client.force_login(account)
        self.assertRedirects(self.client.get("/"), reverse("account_email"), fetch_redirect_response=False)

    def test_password_alone_does_not_complete_mfa_login(self):
        account = user()
        response = self.client.post(reverse("account_login"), {"login": account.email, "password": PASSWORD})
        self.assertEqual(response.status_code, 302)
        self.assertIn("authenticate", response.url)
        self.assertFalse(self.client.session.get("_auth_user_id"))
        response = self.client.post(reverse("mfa_authenticate"), {"code": "invalid"})
        self.assertEqual(response.status_code, 200)
        self.assertFalse(self.client.session.get("_auth_user_id"))
        response = self.client.post(reverse("mfa_authenticate"), {"code": code()})
        self.assertEqual(response.status_code, 302)
        self.assertEqual(int(self.client.session["_auth_user_id"]), account.pk)
        self.assertEqual(self.client.get("/").status_code, 200)

    def test_mfa_secrets_are_encrypted_and_codes_cannot_be_replayed(self):
        account = user()
        factor = Authenticator.objects.get(user=account, type="totp")
        self.assertNotIn(SECRET, str(factor.data))
        self.assertTrue(TOTP(factor).validate_code(code()))
        self.assertFalse(TOTP(factor).validate_code(code()))

    def test_recovery_code_is_single_use(self):
        account = user()
        recovery = RecoveryCodes.activate(account)
        codes = recovery.get_unused_codes()
        self.assertTrue(recovery.validate_code(codes[0]))
        self.assertFalse(recovery.validate_code(codes[0]))

    def test_bad_password_is_rejected_and_rate_limited(self):
        account = user()
        responses = [
            self.client.post(reverse("account_login"), {"login": account.email, "password": "wrong"}) for _ in range(8)
        ]
        self.assertContains(responses[-1], "Too many failed login attempts")
        self.assertFalse(self.client.session.get("_auth_user_id"))

    def test_password_reset_sends_email_and_logout_is_post_only(self):
        account = user()
        self.client.post(reverse("account_reset_password"), {"email": account.email})
        self.assertEqual(len(mail.outbox), 1)
        self.client.force_login(account)
        self.assertEqual(self.client.get(reverse("account_logout")).status_code, 200)
        self.assertIn("_auth_user_id", self.client.session)
        self.client.post(reverse("account_logout"))
        self.assertNotIn("_auth_user_id", self.client.session)

    def test_csrf_and_anonymous_routes(self):
        account = user()
        client = Client(enforce_csrf_checks=True)
        client.force_login(account)
        self.assertEqual(client.post("/timer/start/", {"description": "CSRF attempt"}).status_code, 403)
        for url in ["/", "/entries/", "/items/", "/reports/", "/profile/"]:
            self.assertEqual(self.client.get(url).status_code, 302)
        self.assertEqual(self.client.get("/health/").json(), {"status": "ok"})


class PersonalTrackingTests(TestCase):
    def setUp(self):
        cache.clear()
        self.alice = user()
        self.bob = user("bob@example.test")
        self.client.force_login(self.alice)
        Profile.objects.create(user=self.alice, timezone="Europe/Ljubljana")
        self.project = Project.objects.create(owner=self.alice, name="Depot operations")
        Membership.objects.create(project=self.project, user=self.alice)
        self.activity = Activity.objects.create(owner=self.alice, name="Dispatch")
        self.base = {
            "description": "Route planning",
            "notes": "Private route notes",
            "target": "",
            "mode": "duration",
            "local_date": "2026-11-04",
            "minutes": 90,
        }

    def entry(self, author=None, **kwargs):
        data = dict(
            author=author or self.alice,
            mode="duration",
            local_date=date(2026, 11, 4),
            timezone="Europe/Ljubljana",
            duration_seconds=3600,
            description="Private work",
            notes="secret notes",
        )
        data.update(kwargs)
        return Entry.objects.create(**data)

    def test_duration_general_work_has_no_fabricated_timestamps(self):
        self.assertEqual(self.client.post("/entries/new/", self.base).status_code, 302)
        entry = Entry.objects.get()
        self.assertIsNone(entry.started_at)
        self.assertIsNone(entry.ended_at)
        self.assertEqual(entry.duration_seconds, 5400)
        self.assertIsNone(entry.project_id)
        self.assertEqual(entry.timezone, "Europe/Ljubljana")

    def test_timed_overnight_and_dst_elapsed_duration(self):
        for start, end, seconds in [
            ("2026-11-04T23:30", "2026-11-05T01:00", 5400),
            ("2026-03-29T01:30", "2026-03-29T03:30", 3600),
            ("2026-10-25T01:30", "2026-10-25T03:30", 10800),
        ]:
            with self.subTest(start=start):
                data = {**self.base, "mode": "timed", "started_at": start, "ended_at": end}
                self.assertEqual(self.client.post("/entries/new/", data).status_code, 302)
                entry = Entry.objects.latest("created_at")
                self.assertEqual(entry.duration_seconds, seconds)
                self.assertEqual(entry.local_date.isoformat(), start[:10])

    def test_invalid_and_ambiguous_intervals_are_rejected(self):
        for start, end in [
            ("2026-11-04T10:00", "2026-11-04T09:00"),
            ("2026-11-04T10:00", "2026-11-06T10:00"),
            ("2026-03-29T02:30", "2026-03-29T03:30"),
            ("2026-10-25T02:30", "2026-10-25T03:30"),
        ]:
            response = self.client.post(
                "/entries/new/", {**self.base, "mode": "timed", "started_at": start, "ended_at": end}
            )
            self.assertEqual(response.status_code, 200)
            self.assertTrue(response.context["form"].errors)
        self.assertEqual(Entry.objects.count(), 0)

    def test_invalid_durations_and_foreign_targets_are_rejected(self):
        foreign_project = Project.objects.create(owner=self.bob, name="Unrelated project")
        foreign_activity = Activity.objects.create(owner=self.bob, name="Unrelated activity")
        for data in [
            {**self.base, "minutes": 0},
            {**self.base, "minutes": -1},
            {**self.base, "minutes": 1441},
            {**self.base, "target": "p:" + str(foreign_project.pk)},
            {**self.base, "target": "a:" + str(foreign_activity.pk)},
        ]:
            self.assertEqual(self.client.post("/entries/new/", data).status_code, 200)
        self.assertEqual(Entry.objects.count(), 0)

    def test_independent_timers_idempotence_and_durable_seconds(self):
        now = timezone.now()
        with patch("tracker.services.timezone.now", return_value=now):
            self.client.post("/timer/start/", {"description": "Alice dispatch"})
            self.client.post("/timer/start/", {"description": "Double-click"})
            alice_timer = Entry.objects.get(author=self.alice)
            self.client.force_login(self.bob)
            self.client.post("/timer/start/", {"description": "Bob dispatch"})
        self.assertEqual(Entry.objects.count(), 2)
        self.assertEqual(self.client.post(f"/timer/{alice_timer.pk}/stop/").status_code, 404)
        self.client.force_login(self.alice)
        with patch("tracker.services.timezone.now", return_value=now + timedelta(seconds=3671)):
            self.client.post(f"/timer/{alice_timer.pk}/stop/")
        self.client.post(f"/timer/{alice_timer.pk}/stop/")
        alice_timer.refresh_from_db()
        self.assertEqual(alice_timer.duration_seconds, 3671)
        self.assertTrue(Entry.objects.get(author=self.bob).running)
        self.assertEqual(self.client.get("/timer/start/").status_code, 405)
        self.assertEqual(self.client.get(f"/timer/{alice_timer.pk}/stop/").status_code, 405)

    def test_entries_reports_csv_and_calendar_do_not_expose_another_users_records(self):
        self.entry(description="Alice visible")
        other = self.entry(self.bob, description="Bob hidden", notes="Bob secret")
        for url in [
            "/?month=2026-11&day=2026-11-04",
            "/entries/?month=2026-11",
            "/reports/?month=2026-11",
            "/reports/?month=2026-11&format=csv",
        ]:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200)
            self.assertNotContains(response, "Bob hidden")
            self.assertNotContains(response, "Bob secret")
        self.assertEqual(self.client.get(f"/entries/{other.pk}/edit/").status_code, 404)
        self.assertEqual(self.client.post(f"/entries/{other.pk}/edit/", self.base).status_code, 404)
        self.assertEqual(self.client.get("/reports/?month=2026-11").context["total"], 3600)

    def test_archive_retains_entries_and_prevents_new_tracking(self):
        entry = self.entry(project=self.project)
        self.client.post(f"/items/project/{self.project.pk}/archive/")
        self.project.refresh_from_db()
        self.assertTrue(self.project.archived)
        self.assertTrue(Entry.objects.filter(pk=entry.pk).exists())
        response = self.client.post("/entries/new/", {**self.base, "target": "p:" + str(self.project.pk)})
        self.assertTrue(response.context["form"].errors)
        self.assertEqual(
            self.client.post(
                f"/entries/{entry.pk}/edit/", {**self.base, "target": "p:" + str(self.project.pk)}
            ).status_code,
            302,
        )
        self.client.post(f"/items/project/{self.project.pk}/archive/")
        self.project.refresh_from_db()
        self.assertFalse(self.project.archived)

    def test_foreign_project_and_activity_cannot_be_archived_or_read(self):
        project = Project.objects.create(owner=self.bob, name="Hidden depot")
        activity = Activity.objects.create(owner=self.bob, name="Hidden task")
        self.assertEqual(self.client.get(f"/projects/{project.pk}/").status_code, 404)
        self.assertEqual(self.client.post(f"/items/project/{project.pk}/archive/").status_code, 404)
        self.assertEqual(self.client.post(f"/items/activity/{activity.pk}/archive/").status_code, 404)
        self.assertNotContains(self.client.get("/items/"), "Hidden depot")

    def test_item_creation_and_profile_timezone(self):
        self.client.post("/items/new/project/", {"name": "New depot", "description": "Scheduling", "color": "#7047eb"})
        project = Project.objects.get(name="New depot")
        self.assertEqual(project.owner, self.alice)
        self.assertTrue(Membership.objects.filter(project=project, user=self.alice).exists())
        self.client.post("/profile/", {"timezone": "America/New_York"})
        self.assertEqual(Profile.objects.get(user=self.alice).timezone, "America/New_York")
        self.assertEqual(self.client.get("/profile/").status_code, 200)
        response = self.client.post("/items/new/activity/", {"name": "Bad color", "color": "red;position:fixed"})
        self.assertTrue(response.context["form"].errors)

    def test_same_name_projects_have_distinct_report_rows(self):
        duplicate = Project.objects.create(owner=self.alice, name=self.project.name)
        self.entry(project=self.project)
        self.entry(project=duplicate)
        self.assertEqual(len(self.client.get("/reports/?month=2026-11").context["groups"]), 2)

    def test_csv_formula_escaping_and_private_notes_excluded(self):
        self.entry(description='=IMPORTDATA("https://example.test")')
        response = self.client.get("/reports/?month=2026-11&format=csv")
        self.assertIn("'=IMPORTDATA", response.content.decode())
        self.assertNotIn("secret notes", response.content.decode())

    def test_database_constraints_prevent_invalid_entry_shapes(self):
        for values in [
            dict(duration_seconds=None),
            dict(duration_seconds=0),
            dict(project=self.project, activity=self.activity),
            dict(mode="duration", started_at=timezone.now()),
        ]:
            with self.subTest(values=values), self.assertRaises(IntegrityError), transaction.atomic():
                self.entry(**values)

    def test_page_and_month_bounds(self):
        for month in ["bad", "0001-01", "9999-12"]:
            self.assertEqual(self.client.get("/?month=" + month).status_code, 200)
        self.assertEqual(self.client.get("/entries/?page=not-a-page").status_code, 200)
        self.assertContains(Client().get("/accounts/login/"), 'rel="stylesheet"')


class TimerConcurrencyTests(TransactionTestCase):
    def test_postgres_serializes_simultaneous_start(self):
        if connection.vendor != "postgresql":
            self.skipTest("Row-lock concurrency requires PostgreSQL; CI runs this test against PostgreSQL.")
        account = user()

        def start(_):
            close_old_connections()
            try:
                u = get_user_model().objects.get(pk=account.pk)
                form = TargetForm({"description": "Concurrent timer"}, user=u)
                assert form.is_valid()
                return start_timer(u, form)[1]
            finally:
                connection.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(start, range(2)))
        self.assertEqual(sorted(results), [False, True])
        self.assertEqual(Entry.objects.filter(author=account, ended_at__isnull=True).count(), 1)
