#!/usr/bin/env bash
# Set up a configured local site: fetch missing apps, select app refs,
# create the database, install apps, complete company setup, and activate it.
# Usage: bash scripts/setup-local-site.sh aljar
# Optional: BENCH_DIR, DB_ROOT_USERNAME, DB_ROOT_PASSWORD, ADMIN_PASSWORD.
# Database host/type settings come from the existing bench configuration.

set -euo pipefail
LOG_PREFIX="setup-local-site"
source "$(dirname "${BASH_SOURCE[0]}")/lib/local-site.sh"

fetch_missing_apps() {
    local app ref url
    while IFS=$'\t' read -r app ref; do
        [[ -d "apps/$app" ]] && continue
        url="$(python3 - "$LOCAL_SCRIPT_DIR/apps/apps.json" "$app" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    apps = json.load(handle)['apps']
for app in apps:
    url = app.get('url', '')
    if app.get('name') == sys.argv[2] or url.rstrip('/').rsplit('/', 1)[-1].removesuffix('.git') == sys.argv[2]:
        print(url or sys.argv[2])
        break
else:
    raise SystemExit('App URL missing from scripts/apps/apps.json: ' + sys.argv[2])
PY
)"
        bench get-app "$url" --branch "$ref" --skip-assets
    done < <(json_app_pairs "$CONFIG_FILE")
}

create_local_site() {
    [[ -f "sites/$SITE_NAME/site_config.json" ]] && return
    local options=(--db-root-username "${DB_ROOT_USERNAME:-root}" --admin-password "${ADMIN_PASSWORD:-admin}")
    if [[ -n "${DB_ROOT_PASSWORD:-}" ]]; then
        options+=(--db-root-password "$DB_ROOT_PASSWORD")
    fi
    bench new-site "$SITE_NAME" "${options[@]}"
}

install_local_apps() {
    local app
    for app in "${SITE_APPS[@]}"; do
        [[ "$app" == frappe ]] && continue
        bench --site "$SITE_NAME" install-app "$app"
        if [[ "$app" == hrms ]]; then
            # Complete ERPNext setup before custom apps install their fixtures.
            bench --site "$SITE_NAME" execute \
                frappe.desk.page.setup_wizard.setup_wizard.setup_complete \
                --args "$(json_setup_args "$CONFIG_FILE" | python3 -c 'import json,sys; args=json.load(sys.stdin); args[0]["setup_demo"]=0; print(json.dumps(args))')"
        fi
    done
}

load_local_site "${1:-}"
check_local_changes
stop_local_bench
fetch_missing_apps
checkout_local_apps
start_local_bench services
create_local_site
install_local_apps
activate_local_site
stop_local_bench
start_local_bench
