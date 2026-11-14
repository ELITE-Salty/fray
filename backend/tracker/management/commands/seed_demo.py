from datetime import date, timedelta
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from tracker.models import Item, TimeEntry


class Command(BaseCommand):
    help = 'Add example data to an existing account; safe to rerun.'

    def add_arguments(self, parser):
        parser.add_argument('email')

    def handle(self, *args, **options):
        user = get_user_model().objects.get(username=options['email'].lower())
        for name, kind, color, minutes in [('Website redesign', 'project', '#7153E8', 150),
                ('Faculty project', 'project', '#E39246', 90), ('Office work', 'activity', '#459C85', 60)]:
            item, _ = Item.objects.get_or_create(owner=user, name=name, defaults={'kind': kind, 'color': color})
            for offset in (0, 1, 3, 5):
                TimeEntry.objects.get_or_create(author=user, item=item, local_date=date.today() - timedelta(days=offset),
                    notes='Sample entry — edit or delete me.', defaults={'mode': 'duration', 'duration_minutes': minutes})
        self.stdout.write('Sample data ready.')
