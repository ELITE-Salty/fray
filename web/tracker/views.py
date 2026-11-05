import calendar
import csv
from datetime import date
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db import connection, transaction
from django.db.models import Sum
from django.http import HttpResponse, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_GET, require_POST
from django.core.paginator import Paginator
from .forms import ActivityForm, EntryForm, ItemForm, ProfileForm, TargetForm
from .models import Activity, Entry, Membership, Profile, Project
from .services import start_timer, stop_timer


@require_GET
def health(request):
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
    return JsonResponse({"status": "ok"})


def period(request):
    try:
        selected = date.fromisoformat(request.GET.get("month", timezone.localdate().strftime("%Y-%m")) + "-01")
    except ValueError:
        selected = timezone.localdate().replace(day=1)
    # Avoid out-of-range previous/next dates.
    if not 1901 <= selected.year <= 9998:
        selected = timezone.localdate().replace(day=1)
    return selected, date(selected.year + (selected.month == 12), selected.month % 12 + 1, 1)


def personal_entries(user):
    return Entry.objects.filter(author=user).select_related("project", "activity")


@login_required
@require_GET
def dashboard(request):
    month, end = period(request)
    entries = personal_entries(request.user).filter(local_date__gte=month, local_date__lt=end)
    by_date = {}
    for e in entries:
        by_date.setdefault(e.local_date, []).append(e)
    selected = request.GET.get("day", timezone.localdate().isoformat())
    try:
        selected = date.fromisoformat(selected)
    except ValueError:
        selected = timezone.localdate()
    weeks = [
        [
            {"date": d, "current": d.month == month.month, "entries": by_date.get(d, []), "selected": d == selected}
            for d in week
        ]
        for week in calendar.Calendar(firstweekday=0).monthdatescalendar(month.year, month.month)
    ]
    prev = date(month.year - (month.month == 1), (month.month - 2) % 12 + 1, 1)
    return render(
        request,
        "tracker/dashboard.html",
        {
            "month": month,
            "next_month": end,
            "prev_month": prev,
            "weeks": weeks,
            "selected": selected,
            "day_entries": personal_entries(request.user).filter(local_date=selected),
            "total": entries.aggregate(total=Sum("duration_seconds"))["total"] or 0,
            "running": personal_entries(request.user).filter(mode="timer", ended_at__isnull=True).first(),
            "timer_form": TargetForm(user=request.user),
        },
    )


@login_required
@require_GET
def entries(request):
    month, end = period(request)
    qs = personal_entries(request.user).filter(local_date__gte=month, local_date__lt=end)
    return render(
        request, "tracker/entries.html", {"page": Paginator(qs, 50).get_page(request.GET.get("page")), "month": month}
    )


@login_required
def entry_edit(request, pk=None):
    entry = get_object_or_404(personal_entries(request.user), pk=pk) if pk else None
    if entry and entry.running:
        messages.error(request, "Stop this timer before editing its entry.")
        return redirect("dashboard")
    initial = {"mode": "duration", "local_date": timezone.localdate(), "minutes": 30}
    if entry:
        initial = {k: getattr(entry, k) for k in ["description", "notes", "local_date", "started_at", "ended_at"]}
        initial.update(
            mode="duration" if entry.mode == "duration" else "timed",
            minutes=(entry.duration_seconds or 0) // 60,
            target=("p:" + str(entry.project_id))
            if entry.project_id
            else ("a:" + str(entry.activity_id))
            if entry.activity_id
            else "",
        )
    form = EntryForm(request.POST or None, user=request.user, entry=entry, initial=initial)
    if request.method == "POST" and form.is_valid():
        form.save()
        messages.success(request, "Time entry saved.")
        return redirect("entries")
    return render(
        request,
        "tracker/form.html",
        {
            "form": form,
            "title": "Edit time entry" if entry else "Add time entry",
            "hint": "Start/end use your profile timezone. Ambiguous or nonexistent DST times are rejected. Overlaps are permitted; totals count all recorded time.",
        },
    )


@login_required
@require_POST
def timer_start(request):
    form = TargetForm(request.POST, user=request.user)
    if form.is_valid():
        _, created = start_timer(request.user, form)
        messages.success(request, "Timer started." if created else "Your existing timer is still running.")
    else:
        messages.error(request, "Could not start timer. Enter a description and choose an available item.")
    return redirect("dashboard")


@login_required
@require_POST
def timer_stop(request, pk):
    get_object_or_404(Entry, pk=pk, author=request.user, mode="timer")
    stop_timer(request.user, pk)
    messages.success(request, "Timer stopped and time saved.")
    return redirect("dashboard")


@login_required
@require_GET
def items(request):
    query = request.GET.get("q", "")[:120]
    archived = request.GET.get("archived") == "1"
    project_list = Project.objects.filter(owner=request.user, archived=archived, name__icontains=query).order_by("name")
    activity_list = Activity.objects.filter(owner=request.user, archived=archived, name__icontains=query).order_by(
        "name"
    )
    return render(
        request,
        "tracker/items.html",
        {
            "projects": Paginator(project_list, 30).get_page(request.GET.get("projects_page")),
            "activities": Paginator(activity_list, 30).get_page(request.GET.get("activities_page")),
            "query": query,
            "archived": archived,
        },
    )


@login_required
def item_create(request, kind):
    form_class = ItemForm if kind == "project" else ActivityForm
    form = form_class(request.POST or None)
    if request.method == "POST" and form.is_valid():
        with transaction.atomic():
            item = form.save(commit=False)
            item.owner = request.user
            item.save()
            if kind == "project":
                Membership.objects.create(project=item, user=request.user)
        messages.success(request, f"{kind.title()} created.")
        return redirect("items")
    return render(request, "tracker/form.html", {"form": form, "title": "New " + kind})


@login_required
@require_POST
def item_archive(request, kind, pk):
    model = Project if kind == "project" else Activity
    item = get_object_or_404(model, pk=pk, owner=request.user)
    item.archived = not item.archived
    item.save(update_fields=["archived"])
    messages.success(request, "Item archived. Existing records are retained." if item.archived else "Item restored.")
    return redirect("items")


@login_required
@require_GET
def project_detail(request, pk):
    project = get_object_or_404(Project, pk=pk, owner=request.user)
    month, end = period(request)
    total = (
        personal_entries(request.user)
        .filter(project=project, local_date__gte=month, local_date__lt=end)
        .aggregate(total=Sum("duration_seconds"))["total"]
        or 0
    )
    return render(request, "tracker/project.html", {"project": project, "total": total, "month": month})


@login_required
@require_GET
def reports(request):
    month, end = period(request)
    qs = personal_entries(request.user).filter(
        local_date__gte=month, local_date__lt=end, duration_seconds__isnull=False
    )
    groups = (
        qs.order_by()
        .values("project_id", "activity_id", "project__name", "activity__name")
        .annotate(total=Sum("duration_seconds"))
        .order_by("-total")
    )
    if request.GET.get("format") == "csv":
        response = HttpResponse(content_type="text/csv; charset=utf-8")
        response["Content-Disposition"] = f'attachment; filename="fray-my-time-{month:%Y-%m}.csv"'
        writer = csv.writer(response)
        writer.writerow(["Date", "Item", "Description", "Mode", "Start (UTC)", "End (UTC)", "Seconds", "Timezone"])
        for e in qs:
            # Neutralize spreadsheet formulas in user-controlled fields.
            safe = lambda v: "'" + v if v.startswith(("=", "+", "-", "@", "\t", "\r", "\n")) else v
            writer.writerow(
                [
                    e.local_date.isoformat(),
                    safe(str(e.label)),
                    safe(e.description),
                    e.mode,
                    e.started_at.isoformat() if e.started_at else "",
                    e.ended_at.isoformat() if e.ended_at else "",
                    e.duration_seconds,
                    e.timezone,
                ]
            )
        return response
    return render(
        request,
        "tracker/reports.html",
        {"month": month, "groups": groups, "total": qs.aggregate(total=Sum("duration_seconds"))["total"] or 0},
    )


@login_required
def profile(request):
    profile, _ = Profile.objects.get_or_create(user=request.user)
    form = ProfileForm(request.POST or None, initial={"timezone": profile.timezone})
    if request.method == "POST" and form.is_valid():
        profile.timezone = form.cleaned_data["timezone"]
        profile.save(update_fields=["timezone"])
        messages.success(request, "Timezone saved. Existing dates remain as recorded.")
        return redirect("profile")
    return render(request, "tracker/profile.html", {"form": form})
