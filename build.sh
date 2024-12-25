#!/bin/bash

set -ouex pipefail


RELEASE="$(rpm -E %fedora)"

### Change packages

# This Aurora base removes a number of default packages, as:
#
# - Many of the default packages duplicate functionality already provided in
#   the base KDE distribution (and don't integrate well into KDE), and so they
#   are removed to reduce the image size.
# - The base image is rather opinionated in its package selection, they are
#   removed here in an effort to keep things small.

INCLUDED_RPMS=($(jq -r '.include[]' /tmp/packages.json))
EXCLUDED_RPMS=($(jq -r '.exclude[]' /tmp/packages.json))
INSTALLED_EXCLUDED_RPMS=($(rpm -qa --queryformat='%{name} ' ${EXCLUDED_RPMS[@]}))

if [[ "${#INSTALLED_EXCLUDED_RPMS[@]}" -gt 0 ]]; then
    rpm-ostree override remove ${INSTALLED_EXCLUDED_RPMS[@]} \
        $(printf -- "--install=%s " ${INCLUDED_RPMS[@]})
else
    rpm-ostree install ${INCLUDED_RPMS[@]}
fi

# Clean out unused yum repositories
rm -f /etc/yum.repos.d/{google-chrome,vscode}.repo

# Remove config files for packages that are not shipped in this image
rm -f /usr/libexec/aurora-dx-user-vscode
rm -f /usr/lib/systemd/user/aurora-dx-user-vscode.service
rm -f /etc/profile.d/vscode-{aurora,bluefin}-profile.sh
rm -rf /etc/skel/.config/Code
