#!/bin/bash

set -euxo pipefail

if [[ ! -d "$JUSTFILES" ]]; then
    echo "FATAL: JUSTFILES not set" >&2
    exit 1
fi

cat "${JUSTFILES}/borealos-custom.just" >> /usr/share/ublue-os/just/60-custom.just
