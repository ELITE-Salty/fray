"""Operator diagnostics without SMTP replies, addresses, secrets or message bodies."""
import logging
import smtplib
import socket
import ssl
from prometheus_client import Counter

MAIL = Counter('fray_mail_deliveries_total', 'Mail delivery attempts', ['result'])


def failure_kind(exc):
    if isinstance(exc, socket.gaierror):
        return 'dns'
    if isinstance(exc, smtplib.SMTPAuthenticationError):
        return 'authentication'
    if isinstance(exc, ssl.SSLError):
        return 'tls'
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return 'timeout'
    if isinstance(exc, smtplib.SMTPSenderRefused):
        return 'sender'
    if isinstance(exc, smtplib.SMTPRecipientsRefused):
        return 'recipient'
    return 'smtp' if isinstance(exc, smtplib.SMTPException) else 'connection'


def record_failure(exc):
    kind = failure_kind(exc)
    MAIL.labels(kind).inc()
    code = getattr(exc, 'smtp_code', None)
    logging.getLogger('fray.audit').warning('mail_delivery_failed reason=%s smtp_status=%s', kind,
                                           code if isinstance(code, int) else 'none')
