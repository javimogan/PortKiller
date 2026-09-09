#!/bin/bash
# Live-reload loop: rebuilds on every save and relaunches the app in dev mode
# (floating window + menu bar item), keeping the window where you left it.
# No dependencies — plain mtime polling.
set -uo pipefail
cd "$(dirname "$0")"

BIN=".build/debug/PortKiller"
APP_PID=""

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'

stop_app() {
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null
  APP_PID=""
}
trap 'stop_app; echo; echo "${dim}dev loop stopped${reset}"; exit 0' INT TERM EXIT

fingerprint() {
  find Sources Package.swift -type f -newer /dev/null -exec stat -f '%m %N' {} + 2>/dev/null | sort | cksum
}

rebuild_and_run() {
  printf '%s' "${dim}build…${reset}"
  local start=$SECONDS
  local output
  if ! output=$(swift build 2>&1); then
    printf '\r%s\n' "${red}✗ build failed${reset}                    "
    echo "$output" | grep -E 'error:|warning:' | head -20
    return 1
  fi
  stop_app
  PORTKILLER_DEV=1 "$BIN" &
  APP_PID=$!
  printf '\r%s\n' "${green}✓${reset} reloaded in $((SECONDS - start))s ${dim}(pid $APP_PID)${reset}        "
}

echo "${bold}PortKiller dev${reset} ${dim}— save a file and it reloads. Ctrl+C to quit.${reset}"
rebuild_and_run
last=$(fingerprint)

while true; do
  sleep 0.7
  current=$(fingerprint)
  if [[ "$current" != "$last" ]]; then
    last="$current"
    rebuild_and_run
    last=$(fingerprint)   # ignore changes made by the build itself
  fi
done
