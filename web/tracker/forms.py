from datetime import UTC
from zoneinfo import available_timezones
from django import forms
from django.utils import timezone
from .models import Activity, Entry, Project


class TargetForm(forms.Form):
    target = forms.ChoiceField(label="Activity / project", required=False)
    description = forms.CharField(max_length=240, label="What are you working on?")
    notes = forms.CharField(required=False, max_length=4000, widget=forms.Textarea(attrs={"rows": 3}))

    def __init__(self, *args, user, entry=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.user = user
        self.entry = entry
        # Until collaboration rules are confirmed, only owned projects are usable.
        self.projects = Project.objects.filter(owner=user, archived=False).order_by("name")
        self.activities = Activity.objects.filter(owner=user, archived=False).order_by("name")
        choices = [("", "General work — no project")]
        choices += [("p:" + str(p.pk), "Project · " + p.name) for p in self.projects]
        choices += [("a:" + str(a.pk), "Activity · " + a.name) for a in self.activities]
        if entry:
            for kind, target in [("p", entry.project), ("a", entry.activity)]:
                if target and target.archived:
                    choices.append((f"{kind}:{target.pk}", str(target) + " (archived)"))
        self.fields["target"].choices = choices

    def targets(self):
        value = self.cleaned_data.get("target")
        if not value:
            return {"project": None, "activity": None}
        kind, pk = value.split(":")
        model = Project if kind == "p" else Activity
        # Recheck authorization at use time, not only while rendering the selector.
        target = model.objects.get(pk=pk, owner=self.user)
        return {"project": target if kind == "p" else None, "activity": target if kind == "a" else None}


class EntryForm(TargetForm):
    mode = forms.ChoiceField(choices=[("duration", "Duration only"), ("timed", "Start and end")])
    local_date = forms.DateField(
        label="Date (duration only)", widget=forms.DateInput(attrs={"type": "date"}, format="%Y-%m-%d"), required=False
    )
    minutes = forms.IntegerField(min_value=1, max_value=1440, required=False, label="Minutes (duration only)")
    started_at = forms.DateTimeField(
        required=False,
        label="Start (your timezone)",
        widget=forms.DateTimeInput(attrs={"type": "datetime-local"}, format="%Y-%m-%dT%H:%M"),
        input_formats=["%Y-%m-%dT%H:%M"],
    )
    ended_at = forms.DateTimeField(
        required=False,
        label="End (your timezone)",
        widget=forms.DateTimeInput(attrs={"type": "datetime-local"}, format="%Y-%m-%dT%H:%M"),
        input_formats=["%Y-%m-%dT%H:%M"],
    )

    def clean(self):
        data = super().clean()
        if data.get("mode") == "duration":
            if not data.get("local_date"):
                self.add_error("local_date", "Choose the date this work belongs to.")
            if not data.get("minutes"):
                self.add_error("minutes", "Enter 1–1440 minutes.")
            data.update(started_at=None, ended_at=None, duration_seconds=(data.get("minutes") or 0) * 60)
        else:
            start, end = data.get("started_at"), data.get("ended_at")
            if not start or not end:
                if not self.errors:
                    self.add_error(None, "Enter both start and end, including the end date for overnight work.")
            else:
                seconds = int((end.astimezone(UTC) - start.astimezone(UTC)).total_seconds())
                if seconds <= 0 or seconds > 86400:
                    self.add_error("ended_at", "End must follow start by no more than 24 elapsed hours.")
                data["duration_seconds"] = seconds
                data["local_date"] = timezone.localtime(start).date()
        return data

    def save(self):
        entry = self.entry or Entry(author=self.user)
        for key in ["description", "notes", "mode", "local_date", "started_at", "ended_at", "duration_seconds"]:
            setattr(entry, key, self.cleaned_data[key])
        for key, value in self.targets().items():
            setattr(entry, key, value)
        entry.timezone = timezone.get_current_timezone_name()
        entry.full_clean()
        entry.save()
        return entry


class ItemForm(forms.ModelForm):
    color = forms.RegexField(
        regex=r"^#[0-9a-fA-F]{6}$", initial="#7047eb", widget=forms.TextInput(attrs={"type": "color"})
    )

    class Meta:
        model = Project
        fields = ["name", "description", "color"]
        widgets = {"description": forms.Textarea(attrs={"rows": 3})}


class ActivityForm(ItemForm):
    class Meta(ItemForm.Meta):
        model = Activity


class ProfileForm(forms.Form):
    timezone = forms.ChoiceField(choices=[(tz, tz) for tz in sorted(available_timezones())])
