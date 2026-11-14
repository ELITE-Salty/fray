# Sourced by backup and restore tools after changing to this directory.
compose_file=${FRAY_COMPOSE_FILE:-$PWD/compose.yaml}
compose_env=${FRAY_COMPOSE_ENV:-$PWD/.env}
compose_project=${FRAY_COMPOSE_PROJECT:-fray}
case "$compose_file:$compose_env" in /*:/*) ;; *) echo 'Compose and environment paths must be absolute.' >&2; exit 1;; esac
test -f "$compose_file" && test -f "$compose_env"
compose() { docker compose --project-name "$compose_project" --env-file "$compose_env" -f "$compose_file" "$@"; }
