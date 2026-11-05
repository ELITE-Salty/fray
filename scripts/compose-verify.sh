#!/bin/sh
# Run only on a disposable CI checkout. Uses a distinct Compose project, and
# preserves its volume so a failure can be investigated. No existing app data.
set -eu
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-fray-ci}"
docker compose config --quiet
docker compose up --build --wait --wait-timeout 180
# Test database is separate from the persistent application database.
docker compose exec -T web python manage.py test tracker --noinput
docker compose exec -T web python manage.py makemigrations --check --dry-run
# A one-off persistence probe adds a uniquely named personal activity.
probe="ci-persistence-$(date +%s)"
export FRAY_PROBE="$probe"
docker compose exec -T -e FRAY_PROBE web python manage.py shell -c 'import os; from django.contrib.auth import get_user_model; from tracker.models import Activity; u,_=get_user_model().objects.get_or_create(username=os.environ["FRAY_PROBE"]); Activity.objects.create(owner=u,name=os.environ["FRAY_PROBE"])'
docker compose restart db web
docker compose up --wait --wait-timeout 180
docker compose exec -T -e FRAY_PROBE web python manage.py shell -c 'import os; from tracker.models import Activity; assert Activity.objects.filter(name=os.environ["FRAY_PROBE"]).count()==1; print("PostgreSQL volume restart persistence: PASS")'
curl --fail --silent "http://127.0.0.1:${FRAY_PORT:-8000}/health/"
printf '\nCompose startup, checks and volume restart probe passed.\n'
