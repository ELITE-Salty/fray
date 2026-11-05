import uuid
from django.conf import settings
from django.db import models
from django.db.models import Q


class Profile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    timezone = models.CharField(max_length=64, default="Europe/Ljubljana")


class Project(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="owned_projects")
    name = models.CharField(max_length=120)
    description = models.TextField(blank=True, max_length=2000)
    color = models.CharField(max_length=7, default="#7047eb")
    archived = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    @classmethod
    def visible_to(cls, user):
        return cls.objects.filter(Q(owner=user) | Q(memberships__user=user)).distinct()

    def __str__(self):
        return self.name


class Invitation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    project = models.ForeignKey(Project, on_delete=models.PROTECT, related_name="invitations")
    email = models.EmailField()
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    accepted_at = models.DateTimeField(null=True, blank=True)
    sent_at = models.DateTimeField(null=True, blank=True)
    last_attempt_at = models.DateTimeField(null=True, blank=True)


class Membership(models.Model):
    project = models.ForeignKey(Project, on_delete=models.PROTECT, related_name="memberships")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["project", "user"], name="one_project_membership")]


class Activity(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    name = models.CharField(max_length=120)
    description = models.TextField(blank=True, max_length=2000)
    color = models.CharField(max_length=7, default="#55ad75")
    archived = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name


class Entry(models.Model):
    class Mode(models.TextChoices):
        DURATION = "duration", "Duration only"
        TIMED = "timed", "Start and end"
        TIMER = "timer", "Live timer"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    project = models.ForeignKey(Project, null=True, blank=True, on_delete=models.PROTECT)
    activity = models.ForeignKey(Activity, null=True, blank=True, on_delete=models.PROTECT)
    description = models.CharField(max_length=240)
    notes = models.TextField(blank=True, max_length=4000)
    local_date = models.DateField()
    timezone = models.CharField(max_length=64)
    mode = models.CharField(max_length=8, choices=Mode.choices)
    started_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-local_date", "-created_at"]
        indexes = [models.Index(fields=["author", "local_date"]), models.Index(fields=["project", "local_date"])]
        constraints = [
            models.CheckConstraint(
                condition=~(Q(project__isnull=False) & Q(activity__isnull=False)), name="one_entry_target"
            ),
            models.UniqueConstraint(
                fields=["author"], condition=Q(mode="timer", ended_at__isnull=True), name="one_running_timer"
            ),
            models.CheckConstraint(
                condition=(
                    Q(
                        mode="duration",
                        started_at__isnull=True,
                        ended_at__isnull=True,
                        duration_seconds__gt=0,
                        duration_seconds__isnull=False,
                    )
                    | (
                        Q(
                            mode__in=["timed", "timer"],
                            started_at__isnull=False,
                            ended_at__isnull=False,
                            duration_seconds__gt=0,
                            duration_seconds__isnull=False,
                        )
                        & Q(ended_at__gt=models.F("started_at"))
                    )
                    | Q(mode="timer", started_at__isnull=False, ended_at__isnull=True, duration_seconds__isnull=True)
                ),
                name="valid_entry_shape",
            ),
        ]

    @property
    def running(self):
        return self.mode == self.Mode.TIMER and self.ended_at is None

    @property
    def label(self):
        return self.project or self.activity or "General work"

    @property
    def color(self):
        target = self.project or self.activity
        return target.color if target else "#6683d5"


class RateLimitCache(models.Model):
    """Django DatabaseCache schema; shared across workers and restarts."""

    cache_key = models.CharField(max_length=255, primary_key=True)
    value = models.TextField()
    expires = models.DateTimeField(db_index=True)

    class Meta:
        db_table = "fray_cache"
