from zoneinfo import ZoneInfo
from django.shortcuts import redirect
from django.utils import timezone
from allauth.account.models import EmailAddress
from allauth.mfa.models import Authenticator


class RequireMFAMiddleware:
    """Protect every application route, including direct POSTs, during enrollment.

    allauth handles the actual login challenge, replay protection and recovery.
    Account endpoints stay available for email verification and MFA enrollment.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated and not request.path.startswith(("/accounts/", "/static/", "/health/")):
            if not EmailAddress.objects.filter(
                user=request.user, verified=True, email__iexact=request.user.email
            ).exists():
                return redirect("account_email")
            if not Authenticator.objects.filter(user=request.user, type=Authenticator.Type.TOTP).exists():
                return redirect("mfa_activate_totp")
        return self.get_response(request)


class TimezoneMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated:
            from .models import Profile

            profile, _ = Profile.objects.get_or_create(user=request.user)
            timezone.activate(ZoneInfo(profile.timezone))
        try:
            return self.get_response(request)
        finally:
            timezone.deactivate()
