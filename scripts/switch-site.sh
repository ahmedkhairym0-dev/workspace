#!/usr/bin/env bash
# Switch an existing site: select its config, fetch required apps,
# optionally uninstall extra apps, install required apps,
# update configured branches/tags, activate the site, migrate, clear cache, build.
# App failures stop by default; optional continuation skips the failed apps.
# Usage: bash scripts/switch-site.sh [site-name|hostname|config.json]
# Optional: BENCH_DIR=/path/to/frappe-bench

set -euo pipefail

LOG_PREFIX="switch-site"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_DIR="${BENCH_DIR:-$ROOT_DIR/frappe-bench}"
APPS_JSON="$SCRIPT_DIR/apps/apps.json"
SITES_DIR="$SCRIPT_DIR/sites"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/prompts.sh"

declare -A FAILED_APPS=()
CONTINUE_ON_ERROR=false

main() {
    local app ref line pairs

    if (( $# > 1 )); then
        log_err "Usage: $0 [wanted-site]"
        exit 1
    fi
    if [[ -n "${1:-}" ]]; then
        CONFIG_FILE="$(resolve_config "$1")"
    else
        CONFIG_FILE="$(choose_config)"
    fi
    SITE_NAME="$(json_field "$CONFIG_FILE" site_name)"
    SITE_NAME="${SITE_NAME:-$(basename "${CONFIG_FILE%.json}")}"
    pairs="$(json_app_pairs "$CONFIG_FILE")"
    mapfile -t APP_PAIRS <<< "$pairs"

    if [[ ! -d "$BENCH_DIR" ]]; then
        log_err "Bench directory not found: $BENCH_DIR"
        exit 1
    fi
    cd "$BENCH_DIR"
    if [[ ! -f "sites/$SITE_NAME/site_config.json" ]]; then
        log_err "Site does not exist: $SITE_NAME"
        exit 1
    fi
    log_info "Target site: $SITE_NAME (config: $CONFIG_FILE)"
    if prompt_yes_no "Continue if one app fails" false; then
        CONTINUE_ON_ERROR=true
    fi

    log_info "Fetching missing apps..."
    for line in "${APP_PAIRS[@]}"; do
        IFS=$'\t' read -r app ref <<< "$line"
        [[ -n "$app" ]] || continue
        [[ -d "apps/$app" ]] && continue
        run_app_step "$app" fetch fetch_app "$app" "$ref"
    done

    log_info "Checking installed apps for $SITE_NAME..."
    INSTALLED_APPS="$(bench --site "$SITE_NAME" list-apps | awk 'NF {print $1}')"
    uninstall_extra_apps
    for line in "${APP_PAIRS[@]}"; do
        IFS=$'\t' read -r app ref <<< "$line"
        [[ -n "$app" && "$app" != frappe ]] || continue
        [[ -n "${FAILED_APPS[$app]:-}" ]] && continue
        if ! grep -Fxq -- "$app" <<< "$INSTALLED_APPS"; then
            run_app_step "$app" install bench --site "$SITE_NAME" install-app "$app"
        fi
    done

    log_info "Updating configured branches/tags..."
    for line in "${APP_PAIRS[@]}"; do
        IFS=$'\t' read -r app ref <<< "$line"
        [[ -n "$app" && -n "$ref" ]] || continue
        [[ -n "${FAILED_APPS[$app]:-}" ]] && continue
        run_app_step "$app" update checkout_ref "$app" "$ref"
    done

    if (( ${#FAILED_APPS[@]} > 0 )); then
        log_err "Continuing with failed apps: ${!FAILED_APPS[*]}"
    fi
    log_info "Setting active site to $SITE_NAME..."
    bench use "$SITE_NAME"
    log_info "Running migration..."
    bench --site "$SITE_NAME" migrate
    log_info "Clearing cache..."
    bench --site "$SITE_NAME" clear-cache
    log_info "Building assets..."
    bench build

    if (( ${#FAILED_APPS[@]} > 0 )); then
        log_err "Switched to $SITE_NAME with failed apps: ${!FAILED_APPS[*]}"
        exit 1
    fi
    log_ok "Successfully switched to $SITE_NAME"
}

uninstall_extra_apps() {
    local app index required_apps
    local extra_apps=()

    required_apps="$(printf '%s\n' "${APP_PAIRS[@]}" | cut -f1)"
    while IFS= read -r app; do
        [[ -n "$app" && "$app" != frappe ]] || continue
        if ! grep -Fxq -- "$app" <<< "$required_apps"; then
            extra_apps+=("$app")
        fi
    done <<< "$INSTALLED_APPS"
    (( ${#extra_apps[@]} > 0 )) || return 0

    log_info "Installed apps absent from $(basename "$CONFIG_FILE"):"
    printf ' - %s\n' "${extra_apps[@]}"
    log_info "Uninstalling deletes these apps' DocTypes and data from $SITE_NAME."
    if ! prompt_yes_no "Uninstall these apps from $SITE_NAME" false; then
        log_info "Skipping extra app uninstallation."
        return
    fi

    # Remove later-installed apps first so dependents precede their dependencies.
    for ((index=${#extra_apps[@]} - 1; index >= 0; index--)); do
        app="${extra_apps[$index]}"
        run_app_step "$app" uninstall uninstall_app "$app"
    done
}

uninstall_app() {
    local app="$1" installed_apps

    bench --site "$SITE_NAME" uninstall-app "$app" --yes || return
    installed_apps="$(bench --site "$SITE_NAME" list-apps | awk 'NF {print $1}')" || return
    # Bench can refuse to remove a dependency without returning a nonzero status.
    if grep -Fxq -- "$app" <<< "$installed_apps"; then
        log_err "$app is still installed after the uninstall command."
        return 1
    fi
}

resolve_config() {
    python3 - "$1" "$SITES_DIR" <<'PY'
import json
from pathlib import Path
import sys

wanted, sites_dir = sys.argv[1], Path(sys.argv[2])
for path in (Path(wanted), sites_dir / wanted, sites_dir / f"{wanted}.json"):
    if path.is_file():
        print(path.resolve())
        break
else:
    for path in sorted(sites_dir.glob("*.json")):
        with path.open() as handle:
            if json.load(handle).get("site_name") == wanted:
                print(path.resolve())
                break
    else:
        raise SystemExit(f"Could not resolve site config: {wanted}")
PY
}

choose_config() {
    local configs=() config selection index

    for config in "$SITES_DIR"/*.json; do
        [[ -f "$config" ]] && configs+=("$config")
    done
    if (( ${#configs[@]} == 0 )); then
        log_err "No site configs found in $SITES_DIR" >&2
        return 1
    fi
    for index in "${!configs[@]}"; do
        config="${configs[$index]}"
        printf '%d) %s (%s)\n' "$((index + 1))" \
            "$(basename "${config%.json}")" "$(json_field "$config" site_name)" >&2
    done
    while read -r -p "Choose site number: " selection; do
        for index in "${!configs[@]}"; do
            if [[ "$selection" == "$((index + 1))" ]]; then
                printf '%s\n' "${configs[$index]}"
                return
            fi
        done
        echo "Choose a number from 1 to ${#configs[@]}." >&2
    done
    return 1
}

run_app_step() {
    local app="$1" step="$2"
    shift 2

    log_info "$app: $step"
    if "$@"; then
        log_ok "$app: $step completed"
        return
    fi
    FAILED_APPS["$app"]="$step"
    log_err "$app: $step failed"
    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
        exit 1
    fi
    log_info "Skipping remaining app steps for $app."
}

fetch_app() {
    local app="$1" ref="$2" url
    local options=(--skip-assets)

    url="$(python3 - "$APPS_JSON" "$app" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    data = json.load(handle)
apps = data if isinstance(data, list) else data["apps"]
for app in apps:
    url = app.get("url", "")
    folder = url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")
    if app.get("name") == sys.argv[2] or folder == sys.argv[2]:
        print(url or sys.argv[2])
        break
else:
    raise SystemExit("App missing from scripts/apps/apps.json: " + sys.argv[2])
PY
)" || return
    [[ -z "$ref" ]] || options+=(--branch "$ref")
    bench get-app "$url" "${options[@]}"
}

checkout_ref() {
    local app="$1" ref="$2" remote
    local app_dir="apps/$app"

    remote="$(git -C "$app_dir" remote | head -n1)" || return
    git -C "$app_dir" fetch --tags "$remote" "$ref" || return
    # Called from a conditional: Bash disables errexit, so propagate each failure.
    if git -C "$app_dir" show-ref --verify --quiet "refs/heads/$ref"; then
        git -C "$app_dir" checkout "$ref" || return
    elif git -C "$app_dir" show-ref --verify --quiet "refs/tags/$ref"; then
        git -C "$app_dir" checkout --detach "refs/tags/$ref"
        return
    else
        git -C "$app_dir" checkout -b "$ref" FETCH_HEAD || return
    fi
    git -C "$app_dir" pull --ff-only "$remote" "$ref"
}

main "$@"
