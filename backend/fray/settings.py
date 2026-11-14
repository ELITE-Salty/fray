import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DEBUG = os.environ.get('FRAY_DEBUG') == '1'
SECRET_KEY = os.environ.get('FRAY_SECRET_KEY', '')
if not SECRET_KEY and not DEBUG:
    raise RuntimeError('Set FRAY_SECRET_KEY (or FRAY_DEBUG=1 for local development only).')
SECRET_KEY = SECRET_KEY or 'insecure-local-development-only'
MFA_ENCRYPTION_KEY = os.environ.get('FRAY_MFA_KEY', '')
if not MFA_ENCRYPTION_KEY and DEBUG:
    import base64
    import hashlib
    MFA_ENCRYPTION_KEY = base64.urlsafe_b64encode(hashlib.sha256(SECRET_KEY.encode()).digest()).decode()
if not MFA_ENCRYPTION_KEY:
    raise RuntimeError('Set FRAY_MFA_KEY to a Fernet key; keep it with your backups.')
ALLOWED_HOSTS = os.environ.get('FRAY_HOSTS', 'localhost,127.0.0.1,testserver').split(',')
CSRF_TRUSTED_ORIGINS = [x for x in os.environ.get('FRAY_ORIGINS', '').split(',') if x]
INSTALLED_APPS = ['django.contrib.auth', 'django.contrib.contenttypes', 'django.contrib.sessions',
                  'django_otp', 'tracker']
MIDDLEWARE = ['tracker.middleware.MetricsMiddleware', 'django.middleware.security.SecurityMiddleware',
              'django.middleware.clickjacking.XFrameOptionsMiddleware',
              'django.contrib.sessions.middleware.SessionMiddleware', 'django.middleware.locale.LocaleMiddleware', 'django.middleware.common.CommonMiddleware',
              'django.middleware.csrf.CsrfViewMiddleware', 'django.contrib.auth.middleware.AuthenticationMiddleware',
              'django_otp.middleware.OTPMiddleware']
ROOT_URLCONF = 'fray.urls'
WSGI_APPLICATION = 'fray.wsgi.application'
if os.environ.get('FRAY_DB_NAME'):
    DATABASES = {'default': {'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ['FRAY_DB_NAME'], 'USER': os.environ.get('FRAY_DB_USER', 'fray'),
        'PASSWORD': os.environ['FRAY_DB_PASSWORD'],
        'HOST': os.environ.get('FRAY_DB_HOST', '127.0.0.1'),
        'PORT': os.environ.get('FRAY_DB_PORT', '5432'), 'CONN_MAX_AGE': 60,
        'CONN_HEALTH_CHECKS': True}}
else:
    if not DEBUG:
        raise RuntimeError('Production requires PostgreSQL configuration.')
    DATABASES = {'default': {'ENGINE': 'django.db.backends.sqlite3', 'NAME': BASE_DIR / 'db.sqlite3'}}
if os.environ.get('FRAY_REDIS_URL'):
    CACHES = {'default': {'BACKEND': 'django.core.cache.backends.redis.RedisCache',
                          'LOCATION': os.environ['FRAY_REDIS_URL'], 'KEY_PREFIX': 'fray'}}
else:
    if not DEBUG:
        raise RuntimeError('Production requires FRAY_REDIS_URL.')
    CACHES = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}
SESSION_ENGINE = 'django.contrib.sessions.backends.cached_db'
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
SESSION_COOKIE_SAMESITE = 'Strict'
CSRF_COOKIE_SAMESITE = 'Strict'
SESSION_COOKIE_AGE = 8 * 60 * 60
SESSION_SAVE_EVERY_REQUEST = False
SECURE_SSL_REDIRECT = not DEBUG
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SECURE_HSTS_SECONDS = 31536000 if not DEBUG else 0
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = 'same-origin'
X_FRAME_OPTIONS = 'DENY'
PASSWORD_HASHERS = ['django.contrib.auth.hashers.Argon2PasswordHasher',
                    'django.contrib.auth.hashers.PBKDF2PasswordHasher']
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 12}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]
USE_TZ = True
TIME_ZONE = 'UTC'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
DATA_UPLOAD_MAX_MEMORY_SIZE = 65536
SIGNUP_ENABLED = os.environ.get('FRAY_SIGNUP_ENABLED', '1') == '1'
SIGNUP_EMAIL_LIMIT = int(os.environ.get('FRAY_SIGNUP_EMAIL_LIMIT', '100'))
# Local development prints mail to the local console; production always uses SMTP.
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend' if DEBUG else 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.environ.get('FRAY_EMAIL_HOST', 'in-v3.mailjet.com')
EMAIL_PORT = int(os.environ.get('FRAY_EMAIL_PORT', '587'))
EMAIL_HOST_USER = os.environ.get('FRAY_EMAIL_USER', '')
EMAIL_HOST_PASSWORD = os.environ.get('FRAY_EMAIL_PASSWORD', '')
EMAIL_USE_TLS = os.environ.get('FRAY_EMAIL_USE_TLS', '1') == '1'
EMAIL_USE_SSL = os.environ.get('FRAY_EMAIL_USE_SSL', '0') == '1'
EMAIL_TIMEOUT = 10
DEFAULT_FROM_EMAIL = os.environ.get('FRAY_EMAIL_FROM', 'Fray <noreply@localhost>' if DEBUG else '')
if EMAIL_USE_TLS and EMAIL_USE_SSL:
    raise RuntimeError('Enable STARTTLS or SSL for SMTP, not both.')
LOGGING = {'version': 1, 'disable_existing_loggers': False,
    'formatters': {'plain': {'format': '{asctime} {levelname} {name} {message}', 'style': '{'}},
    'handlers': {'console': {'class': 'logging.StreamHandler', 'formatter': 'plain'}},
    'root': {'handlers': ['console'], 'level': 'INFO'}}

# Match the Flutter interface; dates and API enum values remain language-neutral.
LANGUAGE_CODE = 'en'
LANGUAGES = [('en', 'English'), ('sl', 'Slovenščina'), ('hr', 'Hrvatski')]
USE_I18N = True
LOCALE_PATHS = [BASE_DIR / 'locale']
