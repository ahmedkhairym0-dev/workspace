#!/usr/bin/env bash
# Switch an existing local site: stop the managed bench, change app refs,
# refresh dependencies, migrate, build assets, select the site, and restart.
# Usage: bash scripts/switch-local-site.sh aljar

set -euo pipefail
LOG_PREFIX="switch-local-site"
source "$(dirname "${BASH_SOURCE[0]}")/lib/local-site.sh"

load_local_site "${1:-}"
[[ -f "sites/$SITE_NAME/site_config.json" ]] || {
    log_err "Site does not exist: $SITE_NAME. Run setup-local-site.sh first."
    exit 1
}
for app in "${SITE_APPS[@]}"; do
    [[ -d "apps/$app" ]] || {
        log_err "Missing app: $app. Run setup-local-site.sh first."
        exit 1
    }
done
check_local_changes
stop_local_bench
checkout_local_apps
start_local_bench services
activate_local_site
stop_local_bench
start_local_bench
