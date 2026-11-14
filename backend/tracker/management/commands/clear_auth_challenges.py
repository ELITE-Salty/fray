from django.core.management.base import BaseCommand
from django.utils import timezone
from tracker.models import AuthChallenge


class Command(BaseCommand):
    help = 'Remove expired login/signup challenges and their pending personal data.'

    def handle(self, *args, **options):
        count, _ = AuthChallenge.objects.filter(expires_at__lte=timezone.now()).delete()
        self.stdout.write(f'Removed {count} expired authentication challenges.')
