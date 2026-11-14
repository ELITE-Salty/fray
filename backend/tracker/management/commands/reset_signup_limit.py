import hashlib
from django.core.cache import cache
from django.core.management.base import BaseCommand
from django.core.validators import validate_email


class Command(BaseCommand):
    help = 'Clear only one email address\'s signup retry counter; keep global abuse protection.'
    def add_arguments(self, parser):
        parser.add_argument('email')
    def handle(self, email, **options):
        email = email.strip().lower()
        validate_email(email)
        key = 'signup-email:' + hashlib.sha256(email.encode()).hexdigest()
        found = cache.delete(key)
        cache.delete(key + ':until')
        self.stdout.write('Signup limit cleared.' if found else 'No signup limit found.')
