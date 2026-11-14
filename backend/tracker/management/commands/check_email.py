from django.conf import settings
from django.core.mail import get_connection
from django.core.management.base import BaseCommand, CommandError
from tracker.mail_support import failure_kind


class Command(BaseCommand):
    help = 'Check mail configuration, optionally connect/authenticate. Never sends email or prints credentials.'
    def add_arguments(self, parser):
        parser.add_argument('--connect', action='store_true')
    def handle(self, **options):
        keys = ['EMAIL_HOST', 'EMAIL_HOST_USER', 'EMAIL_HOST_PASSWORD', 'DEFAULT_FROM_EMAIL']
        missing = [key for key in keys if not getattr(settings, key)]
        self.stdout.write('Signup enabled: ' + str(settings.SIGNUP_ENABLED))
        for key in keys:
            self.stdout.write(key + ': ' + ('missing' if key in missing else 'configured'))
        if missing:
            raise CommandError('Configure missing SMTP settings in the API container environment.')
        if options['connect']:
            connection = get_connection()
            try:
                connection.open()
                self.stdout.write('SMTP connection and authentication: OK (sender acceptance not tested)')
            except Exception as exc:
                raise CommandError('SMTP check failed: ' + failure_kind(exc)) from None
            finally:
                try:
                    connection.close()
                except Exception:
                    pass
