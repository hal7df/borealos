#!/bin/bash

set -euxo pipefail

if [[ -z "${TARGET_IMAGE:-}" ]]; then
    echo "FATAL: TARGET_IMAGE not set" >&2
    exit 1
fi
if [[ -z "${VERSION:-}" ]]; then
    echo "FATAL: VERSION not set" >&2
    exit 1
fi

# Rewrite image-info.json
IMAGE_FLAVOR="main"
IMAGE_REF="ghcr.io/hal7df/borealos"
IMAGE_GIT_REPO="github.com/hal7df/borealos"
BASE_IMAGE_NAME="aurora-dx"

if [[ "$TARGET_IMAGE" =~ "nvidia-open" ]]; then
    IMAGE_FLAVOR="nvidia-open"
    IMAGE_REF="$IMAGE_REF-nvidia-open"
    BASE_IMAGE_NAME="${BASE_IMAGE_NAME}-${IMAGE_FLAVOR}"
fi

cat >/usr/share/ublue-os/image-info.json <<EOF
{
    "image-name": "$TARGET_IMAGE",
    "image-flavor": "$IMAGE_FLAVOR",
    "image-vendor": "hal7df",
    "image-ref": "ostree-image-signed:docker://$IMAGE_REF",
    "image-tag": "${TARGET_RELEASE_TYPE}-${VERSION}",
    "base-image-name": "${BASE_IMAGE_NAME}",
    "fedora-version": "$(rpm -E %fedora)"
}
EOF

# Patch os-release
BASE_IMAGE_VERSION="$(. /usr/lib/os-release; echo "$IMAGE_VERSION")"

sed -i 's;Aurora;BorealOS;g' /usr/lib/os-release
sed -i "s;github.com/ublue-os/aurora;${IMAGE_GIT_REPO};g" /usr/lib/os-release
sed -i "s;\(https://\)getaurora.dev;\1${IMAGE_GIT_REPO};g" /usr/lib/os-release
sed -i 's;aurora\(-dx\)*\("\)*$;borealos\2;g' /usr/lib/os-release
sed -i "s;\(RELEASE_TYPE=\).*\$;\1${TARGET_RELEASE_TYPE};g" /usr/lib/os-release
sed -i "s;${BASE_IMAGE_VERSION};${VERSION};g" /usr/lib/os-release
