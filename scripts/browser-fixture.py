"""Disposable CI/demo fixture. Run via manage.py shell --verbosity 0.

Never run against an existing user database: this adds an isolated test account.
It emits a session cookie only to the private temporary state file, not logs or
published screenshots. Actual signup/login/MFA is covered in tracker.tests.
"""

import json
import secrets
from datetime import timedelta

from allauth.account.models import EmailAddress
from allauth.mfa.totp.internal.auth import TOTP, generate_totp_secret
from django.contrib.auth import get_user_model
from django.test import Client
from django.utils import timezone
from tracker.models import Activity, Entry, Membership, Profile, Project

suffix = secrets.token_hex(6)
account = get_user_model().objects.create_user(
    username=f"visual-{suffix}", email=f"visual-{suffix}@example.test", password=secrets.token_urlsafe(32)
)
EmailAddress.objects.create(user=account, email=account.email, primary=True, verified=True)
TOTP.activate(account, generate_totp_secret())
Profile.objects.create(user=account, timezone="Europe/Ljubljana")
project = Project.objects.create(
    owner=account, name="Depot operations", description="Planning the next smooth delivery."
)
Membership.objects.create(project=project, user=account)
activity = Activity.objects.create(owner=account, name="Dispatch", color="#55ad75")
for offset, seconds in [(0, 5400), (1, 3600), (2, 7200)]:
    Entry.objects.create(
        author=account,
        project=project if offset != 1 else None,
        activity=activity if offset == 1 else None,
        description=["Route planning", "Morning dispatch", "Delivery coordination"][offset],
        local_date=timezone.localdate() - timedelta(days=offset),
        timezone="Europe/Ljubljana",
        mode="duration",
        duration_seconds=seconds,
    )
member = get_user_model().objects.create_user(
    username=f"member-{suffix}", email=f"member-{suffix}@example.test", password=secrets.token_urlsafe(32)
)
EmailAddress.objects.create(user=member, email=member.email, primary=True, verified=True)
TOTP.activate(member, generate_totp_secret())


def state(user):
    client = Client()
    client.force_login(user)
    return {
        "cookies": [
            {
                "name": "sessionid",
                "value": client.cookies["sessionid"].value,
                "domain": "127.0.0.1",
                "path": "/",
                "httpOnly": True,
                "secure": False,
                "sameSite": "Lax",
            }
        ],
        "origins": [],
    }


print(json.dumps({"owner": state(account), "member": state(member), "memberEmail": member.email}))
