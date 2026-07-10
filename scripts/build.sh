#!/bin/bash

if [[ -z "${SCRIPTS_DIR:-}" || ! -d "$SCRIPTS_DIR" ]]; then
    echo "FATAL: SCRIPTS_DIR unset or invalid" >&2
    exit 1
fi

# Required by some RPM installs
mkdir -p /var/lib/alternatives

set -euo pipefail

find "${SCRIPTS_DIR}" -maxdepth 1 -iname "*-*.sh" -type f | sort --sort=human-numeric | while read -r SCRIPT; do
    printf '::script:: ==%s==\n' "$(basename "$SCRIPT")"
    "$(realpath "$SCRIPT")"
    printf '::endscript::\n'
done
