from datetime import UTC
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from .models import Entry


@transaction.atomic
def start_timer(user, form):
    # Serialize start/stop for this account on PostgreSQL, across workers.
    get_user_model().objects.select_for_update().get(pk=user.pk)
    existing = Entry.objects.filter(author=user, mode='timer', ended_at__isnull=True).first()
    if existing:
        return existing, False
    now = timezone.now()
    entry = Entry.objects.create(
        author=user, mode='timer', started_at=now, local_date=timezone.localdate(now),
        timezone=timezone.get_current_timezone_name(), description=form.cleaned_data['description'],
        notes=form.cleaned_data['notes'], **form.targets(),
    )
    return entry, True


@transaction.atomic
def stop_timer(user, entry_id):
    get_user_model().objects.select_for_update().get(pk=user.pk)
    entry = Entry.objects.get(pk=entry_id, author=user, mode='timer')
    if entry.ended_at:
        return entry
    entry.ended_at = timezone.now()
    # Preserve exact elapsed seconds; a sub-second stop is recorded as one second.
    entry.duration_seconds = max(1, int((entry.ended_at.astimezone(UTC) - entry.started_at.astimezone(UTC)).total_seconds()))
    if entry.ended_at <= entry.started_at:
        from datetime import timedelta
        entry.ended_at = entry.started_at + timedelta(seconds=1)
    entry.save(update_fields=['ended_at', 'duration_seconds', 'updated_at'])
    return entry
