#!/usr/bin/env python3
"""Generate a server-local Compose .env without printing or overwriting secrets."""
import argparse
import base64
import os
from pathlib import Path
import re
import secrets

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--domain', default='frayapi.klanija.com')
parser.add_argument('--http-port', type=int, default=8090)
parser.add_argument('--metrics-port', type=int, default=9090)
parser.add_argument('--output', type=Path, help='Destination for a Portainer environment file; never overwritten')
parser.add_argument('--image-tag', default='local', help='Use release or a published version for Portainer')
args = parser.parse_args()
if not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?', args.domain):
    parser.error('Use a hostname, without scheme, path, or port.')
if not all(1024 <= p <= 65535 for p in (args.http_port, args.metrics_port)):
    parser.error('Choose unprivileged ports from 1024 to 65535.')
if args.http_port == args.metrics_port:
    parser.error('HTTP and metrics ports must be different.')
if not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}', args.image_tag):
    parser.error('Use a valid Docker image tag.')
target = args.output or Path(__file__).with_name('.env')
values = {'FRAY_DOMAIN': args.domain.lower(), 'FRAY_HTTP_PORT': args.http_port,
          'FRAY_METRICS_PORT': args.metrics_port, 'FRAY_IMAGE_TAG': args.image_tag,
          'FRAY_SECRET_KEY': secrets.token_hex(48),
          'FRAY_MFA_KEY': base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(),
          'FRAY_DB_PASSWORD': secrets.token_hex(32), 'FRAY_POSTGRES_PASSWORD': secrets.token_hex(32),
          'FRAY_REDIS_PASSWORD': secrets.token_hex(32)}
try:
    with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        output.write(''.join(f'{key}={value}\n' for key, value in values.items()))
except FileExistsError:
    parser.error('.env already exists; existing secrets were preserved.')
print(f'Created {target} with mode 0600. Keep it on the server and back it up privately.')
