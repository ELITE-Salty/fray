import uuid
from cryptography.fernet import Fernet
from django.conf import settings
from django.db import models
from django_otp.models import Device, ThrottlingMixin
from django_otp.oath import TOTP


class Authenticator(ThrottlingMixin, Device):
    """Encrypted TOTP seed; verification and throttling use django-otp primitives."""
    encrypted_key = models.BinaryField()
    last_t = models.BigIntegerField(default=-1)

    def set_key(self, key):
        self.encrypted_key = Fernet(settings.MFA_ENCRYPTION_KEY.encode()).encrypt(key)

    def get_key(self):
        return Fernet(settings.MFA_ENCRYPTION_KEY.encode()).decrypt(bytes(self.encrypted_key))

    def get_throttle_factor(self):
        return 1

    def verify_token(self, token):
        allowed, _ = self.verify_is_allowed()
        if not allowed:
            return False
        try:
            valid_shape = len(str(token)) == 6 and str(token).isascii() and str(token).isdigit()
            totp = TOTP(self.get_key(), step=30, digits=6)
            verified = valid_shape and totp.verify(int(token), tolerance=1, min_t=self.last_t + 1)
        except (ValueError, TypeError):
            verified = False
        if verified:
            self.last_t = totp.t()
            self.throttle_reset(commit=False)
            self.save()
            return True
        self.throttle_increment()
        return False


class RecoveryCode(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    digest = models.CharField(max_length=256)


class AccountProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    email_verified_at = models.DateTimeField()


class AuthChallenge(models.Model):
    """Short-lived, session-bound login/signup state; never an authenticated session."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.CASCADE)
    stage = models.CharField(max_length=8, choices=[('email', 'Email'), ('enroll', 'Enroll'), ('mfa', 'MFA')])
    email = models.EmailField(max_length=150)
    name = models.CharField(max_length=150, blank=True)
    password_hash = models.CharField(max_length=256)
    encrypted_key = models.BinaryField(default=bytes)
    email_code_hash = models.CharField(max_length=64, blank=True)
    email_sent_at = models.DateTimeField(null=True)
    email_verified_at = models.DateTimeField(null=True)
    attempts = models.PositiveSmallIntegerField(default=0)
    expires_at = models.DateTimeField(db_index=True)


class Item(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    kind = models.CharField(max_length=8, choices=[('project', 'Project'), ('activity', 'Activity')])
    name = models.CharField(max_length=120)
    description = models.CharField(max_length=500, blank=True)
    color = models.CharField(max_length=7, default='#7153E8')
    pinned = models.BooleanField(default=False)
    archived = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-pinned', 'name', 'id']
        indexes = [models.Index(fields=['owner', 'archived'])]
        constraints = [models.CheckConstraint(condition=models.Q(kind__in=['project', 'activity']), name='item_kind')]


class TimeEntry(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    item = models.ForeignKey(Item, on_delete=models.PROTECT)
    local_date = models.DateField()
    timezone = models.CharField(max_length=64, default='UTC')
    mode = models.CharField(max_length=8, choices=[('timed', 'Timed'), ('duration', 'Duration')])
    started_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    duration_minutes = models.PositiveIntegerField()
    notes = models.CharField(max_length=2000, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-local_date', 'started_at', 'id']
        indexes = [models.Index(fields=['author', 'local_date'])]
        constraints = [
            models.CheckConstraint(condition=models.Q(duration_minutes__gt=0, duration_minutes__lte=1440), name='positive_duration'),
            models.CheckConstraint(condition=(
                models.Q(mode='duration', started_at__isnull=True, ended_at__isnull=True) |
                models.Q(mode='timed', started_at__isnull=False, ended_at__isnull=False, ended_at__gt=models.F('started_at'))
            ), name='entry_mode_timestamps')]
