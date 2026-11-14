#!/bin/sh
set -eu
mkdir -p "$GF_PATHS_PROVISIONING"
cp -R /opt/fray-grafana/provisioning/. "$GF_PATHS_PROVISIONING/"
if test -n "${FRAY_ALERT_EMAIL_TO:-}"; then
    cp /opt/fray-grafana/email.yaml "$GF_PATHS_PROVISIONING/alerting/email.yaml"
    export GF_SMTP_ENABLED=true
else
    # Rules still evaluate; configure a contact point before expecting notifications.
    export GF_SMTP_ENABLED=false
fi
exec /run.sh
