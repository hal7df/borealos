#!/bin/bash

set -euxo pipefail


RELEASE="$(rpm -E %fedora)"

### Change packages

# This script removes a number of packages that are included by default, as many
# of these packages duplicate functionality provided by KDE (or even other
# packages added by the base image!). The intent of this build is to provide a
# slimmer Aurora image while still providing minimally sufficient tooling for
# power users and developers.

INCLUDED_RPMS=($(jq -r '.rpm.include[]' /tmp/packages.json))
EXCLUDED_RPMS=($(jq -r '.rpm.exclude[]' /tmp/packages.json))
INSTALLED_EXCLUDED_RPMS=($(rpm -qa --queryformat='%{name} ' ${EXCLUDED_RPMS[@]}))

if [[ "${#INSTALLED_EXCLUDED_RPMS[@]}" -gt 0 && "${#INCLUDED_RPMS[@]}" -gt 0 ]]; then
    rpm-ostree override remove ${INSTALLED_EXCLUDED_RPMS[@]} \
        $(printf -- "--install=%s " ${INCLUDED_RPMS[@]})
elif [[ "${#INSTALLED_EXCLUDED_RPMS[@]}" -gt 0 ]]; then
    rpm-ostree override remove ${INSTALLED_EXCLUDED_RPMS[@]}
else
    rpm-ostree install ${INCLUDED_RPMS[@]}
fi

# Clean out unused yum repositories
/tmp/build-files/clean-unused.sh

# Setup custom scripts, modify upstream scripts
/tmp/build-files/system-files.sh

# Configure image signing
/tmp/build-files/signing.sh

# Configure image metadata
/tmp/build-files/branding.sh
