import base64
import getpass
import json
import os
import secrets
from urllib.parse import quote, urlencode

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.contrib.auth.password_validation import validate_password
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from tracker.models import Authenticator, RecoveryCode


class Command(BaseCommand):
    help = 'Create an MFA-enrolled account; deliver credentials through a private channel.'

    def add_arguments(self, parser):
        parser.add_argument('email')
        parser.add_argument('--name', default='')
        parser.add_argument('--output', help='Write credentials to a new 0600 file instead of stdout.')

    def handle(self, *args, **options):
        email = options['email'].strip().lower()
        from django.core.validators import validate_email
        validate_email(email)
        if get_user_model().objects.filter(username=email).exists():
            raise CommandError('Account already exists; no credentials were changed.')
        password = os.environ.get('FRAY_INITIAL_PASSWORD') or getpass.getpass('Password (12+ characters): ')
        user = get_user_model()(username=email, email=email, first_name=options['name'][:150])
        validate_password(password, user)
        key = secrets.token_bytes(20)
        secret = base64.b32encode(key).decode().rstrip('=')
        codes = [secrets.token_hex(10) for _ in range(8)]
        uri = 'otpauth://totp/' + quote('Fray:' + email, safe='') + '?' + urlencode({'secret': secret, 'issuer': 'Fray'})
        credentials = json.dumps({'email': email, 'password': password, 'authenticator_secret': secret,
                                  'otpauth_uri': uri, 'recovery_codes': codes}, indent=2)
        # Open before writing the database, so a bad path never strands an account.
        output = None
        if options['output']:
            output = os.fdopen(os.open(options['output'], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w')
        try:
            with transaction.atomic():
                user.set_password(password)
                user.save()
                device = Authenticator(user=user, name='Authenticator', confirmed=True)
                device.set_key(key)
                device.save()
                RecoveryCode.objects.bulk_create([RecoveryCode(user=user, digest=make_password(code)) for code in codes])
                if output:
                    output.write(credentials + '\n')
                    output.flush()
            if not output:
                self.stdout.write(credentials)
        finally:
            if output:
                output.close()
