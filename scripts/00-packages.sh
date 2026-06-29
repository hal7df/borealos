#!/bin/bash

set -euxo pipefail

### Change packages

# This script removes a number of packages that are included by default, as many
# of these packages duplicate functionality provided by KDE (or even other
# packages added by the base image!). The intent of this build is to provide a
# slimmer Aurora image while still providing minimally sufficient tooling for
# power users and developers.

INCLUDED_RPMS=($(jq -r '.rpm.include[]' /tmp/packages.json))
EXCLUDED_RPMS=($(jq -r '.rpm.exclude[]' /tmp/packages.json))
INSTALLED_EXCLUDED_RPMS=($(rpm -qa --queryformat='%{name} ' ${EXCLUDED_RPMS[@]}))

if [[ "${#INCLUDED_RPMS[@]}" -gt 0 ]]; then
    dnf install -y "${INCLUDED_RPMS[@]}"
fi
if [[ "${#INSTALLED_EXCLUDED_RPMS[@]}" -gt 0 ]]; then
    dnf remove -y "${INSTALLED_EXCLUDED_RPMS[@]}"
fi

dnf clean all
