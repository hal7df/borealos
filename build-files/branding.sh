#!/bin/bash

IMAGE_FLAVOR="main"
IMAGE_REF="ghcr.io/hal7df/borealos"
if [[ "$TARGET_IMAGE" =~ nvidia ]]; then
    IMAGE_FLAVOR="nvidia"
    IMAGE_REF="$IMAGE_REF-nvidia"
fi

cat >/usr/share/ublue-os/image-info.json <<EOF
{
    "image-name": "borealos",
    "image-flavor": "$IMAGE_FLAVOR",
    "image-vendor": "hal7df",
    "image-ref": "ostree-image-signed:docker://$IMAGE_REF",
    "image-tag": "$SOURCE_TAG",
    "base-image-name": "aurora-dx",
    "fedora-version": "$(rpm -E %fedora)"
}
EOF
