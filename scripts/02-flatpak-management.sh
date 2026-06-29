#!/bin/bash

set -euxo pipefail

if [[ ! -d "$JUSTFILES" ]]; then
    echo "FATAL: JUSTFILES not set" >&2
    exit 1
fi

if [[ ! -f "$FLATPAK_LIST" ]]; then
    echo "FATAL: FLATPAK_LIST not set" >&2
    exit 1
fi

# Remove old script for unattended installation of flatpaks on user sign in
rm /usr/libexec/ublue-flatpak-manager

# Modify flatpak management to use the borealos flatpak list
awk -F'/' '{print "flatpak \"" $2 "\""}' "$FLATPAK_LIST" > /usr/share/ublue-os/homebrew/system-flatpaks.Brewfile
rm -f /usr/share/ublue-os/homebrew/system-dx-flatpaks.Brewfile

sed -i -e '/^install-system-flatpaks/,/^[^[:space:]]/{/^[[:space:]]/d}' \
    -e "/^install-system-flatpaks/r ${JUSTFILES}/install-system-flatpaks.sh" \
    "$(grep -rlm 1 'install-system-flatpaks' /usr/share/ublue-os/just)"
