#!/usr/bin/env bash
# Local site helpers: resolve configs, switch app refs, refresh dependencies,
# and manage the development bench started by the local site commands.

set -euo pipefail

LOCAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$LOCAL_SCRIPT_DIR/lib/common.sh"
BENCH_DIR="$(realpath "${BENCH_DIR:-$LOCAL_SCRIPT_DIR/../frappe-bench}")"
PID_FILE="$BENCH_DIR/logs/local-site.pid"
LOCAL_PROCFILE="$BENCH_DIR/logs/Procfile.local-site"

load_local_site() {
    local name="${1:?Usage: command <aljar|alqamzi|config.json>}"
    if [[ -f "$name" ]]; then
        CONFIG_FILE="$(realpath "$name")"
    else
        CONFIG_FILE="$LOCAL_SCRIPT_DIR/sites/${name%.json}.json"
    fi
    SITE_NAME="$(json_field "$CONFIG_FILE" site_name)"
    mapfile -t SITE_APPS < <(json_app_pairs "$CONFIG_FILE" | cut -f1)
    cd "$BENCH_DIR"
}

stop_local_bench() {
    # Only terminate the isolated process group created by start_local_bench.
    python3 - "$BENCH_DIR" "$PID_FILE" <<'PY'
import os
from pathlib import Path
import signal
import sys
import time

bench = Path(sys.argv[1])
pid_file = Path(sys.argv[2])
if pid_file.exists():
    pid = int(pid_file.read_text())
    proc = Path('/proc') / str(pid)
    if proc.exists() and (proc / 'cwd').resolve() == bench:
        args = (proc / 'cmdline').read_bytes().split(b'\0')
        if not any(Path(os.fsdecode(arg)).name in {'bench', 'honcho'} for arg in args if arg):
            raise SystemExit('Recorded PID no longer belongs to bench.')
        if os.getpgid(pid) != pid:
            raise SystemExit('Bench process is not in an isolated process group.')
        os.killpg(pid, signal.SIGTERM)
        for _ in range(150):
            if not proc.exists() or (proc / 'stat').read_text().split()[2] == 'Z':
                break
            time.sleep(0.1)
        else:
            raise SystemExit('Bench did not stop. Stop it before retrying.')
    pid_file.unlink()

for proc in Path('/proc').glob('[0-9]*'):
    try:
        if (proc / 'cwd').resolve() != bench:
            continue
        args = (proc / 'cmdline').read_bytes().split(b'\0')
        commands = {b'start', b'serve', b'worker', b'schedule', b'watch', b'socketio'}
        if any(Path(os.fsdecode(arg)).name in {'bench', 'honcho'} for arg in args if arg):
            if commands.intersection(args):
                raise SystemExit('An external bench process is running. Stop it in its terminal first.')
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        continue
PY
}

check_local_changes() {
    local app
    for app in "${SITE_APPS[@]}"; do
        [[ -d "$BENCH_DIR/apps/$app" ]] || continue
        if [[ -n "$(git -C "$BENCH_DIR/apps/$app" status --porcelain)" ]]; then
            log_err "$app has uncommitted changes. Commit or stash them before switching."
            return 1
        fi
    done
}

checkout_local_apps() {
    local app ref remote
    while IFS=$'\t' read -r app ref; do
        remote="$(git -C "apps/$app" remote | head -n1)"
        git -C "apps/$app" fetch --tags "$remote" "$ref"
        if git -C "apps/$app" show-ref --verify --quiet "refs/heads/$ref"; then
            git -C "apps/$app" checkout "$ref"
        elif git -C "apps/$app" show-ref --verify --quiet "refs/tags/$ref"; then
            git -C "apps/$app" checkout --detach "$ref"
        else
            git -C "apps/$app" checkout -b "$ref" FETCH_HEAD
        fi
    done < <(json_app_pairs "$CONFIG_FILE")
    bench setup requirements --python "${SITE_APPS[@]}"
    bench setup requirements --node "${SITE_APPS[@]}"
}

activate_local_site() {
    bench --site "$SITE_NAME" migrate
    local app
    for app in "${SITE_APPS[@]}"; do
        bench build --app "$app"
    done
    bench use "$SITE_NAME"
    bench --site "$SITE_NAME" set-config host_name "http://$SITE_NAME:8000"
}

start_local_bench() {
    local mode="${1:-web}"
    mkdir -p "$BENCH_DIR/logs"
    # Bench-wide workers can execute queued jobs for sites with incompatible code.
    python3 - "$BENCH_DIR/Procfile" "$LOCAL_PROCFILE" "$mode" "$SITE_NAME" <<'PY'
from pathlib import Path
import shlex
import sys

lines = []
for line in Path(sys.argv[1]).read_text().splitlines():
    name = line.partition(':')[0].strip()
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    if sys.argv[3] == 'services' and not name.startswith('redis'):
        continue
    if name in {'schedule', 'worker'} or name.startswith('worker_'):
        continue
    if name == 'web':
        line = f'web: bench --site {shlex.quote(sys.argv[4])} serve --port 8000'
    lines.append(line)
Path(sys.argv[2]).write_text('\n'.join(lines) + '\n')
PY
    nohup setsid bench start --procfile "$LOCAL_PROCFILE" > "$BENCH_DIR/logs/local-site.log" 2>&1 < /dev/null &
    echo "$!" > "$PID_FILE"
    # Migrations and installation need Redis before web processes can start.
    python3 - "$BENCH_DIR/sites/common_site_config.json" "$!" "$mode" <<'PY'
import json
from pathlib import Path
import socket
import sys
import time
from urllib.parse import urlparse

with open(sys.argv[1]) as handle:
    config = json.load(handle)
proc = Path('/proc') / sys.argv[2]
endpoints = [(key, urlparse(config[key])) for key in ('redis_cache', 'redis_queue', 'redis_socketio')]
if sys.argv[3] == 'web':
    endpoints.append(('web', urlparse('http://127.0.0.1:8000')))
for key, url in endpoints:
    for attempt in range(100):
        if not proc.exists() or (proc / 'stat').read_text().split()[2] == 'Z':
            raise SystemExit('Bench exited. Check logs/local-site.log.')
        try:
            with socket.create_connection((url.hostname, url.port or 6379), timeout=0.2):
                break
        except OSError:
            if attempt == 99:
                raise SystemExit(f'Service unavailable: {key}. Check logs/local-site.log.')
            time.sleep(0.1)
PY
    [[ "$mode" == services ]] && return 0
    log_ok "Bench starting: http://$SITE_NAME:8000"
    log_info "Log: $BENCH_DIR/logs/local-site.log"
    log_info "Bench-wide workers and scheduler are excluded from the local Procfile."
}
