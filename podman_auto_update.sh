#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./podman_auto_update.sh <container-name> [container-name2 ...]

Examples:
  ./podman_auto_update.sh nginx
  ./podman_auto_update.sh nginx mysql

This script enables Podman auto-update for the specified containers by adding
 the label io.containers.autoupdate=registry.

After enabling, run:
  podman auto-update
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

for name in "$@"; do
  if ! podman ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    echo "Container '$name' was not found."
    exit 1
  fi

  podman update --label "io.containers.autoupdate=registry" "$name" >/dev/null
  echo "Enabled auto-update for container: $name"
done

echo
printf 'You can now run:\n  podman auto-update\n'
printf 'To enable periodic updates via systemd, see:\n  man podman-auto-update\n'
