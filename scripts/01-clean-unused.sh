#!/bin/bash

# Clean out unused rum repositories
rm -f {,/usr}/etc/yum.repos.d/{vscode,docker-ce,tailscale}.repo

# Remove config files for packages that are not shipped in this image
rm -f /usr/libexec/aurora-dx-user-vscode
rm -f /usr/lib/systemd/user/aurora-dx-user-vscode.service
rm -f {,/usr}/etc/profile.d/vscode-{aurora,bluefin}-profile.sh
rm -rf {,/usr}/etc/skel/.config/Code
rm -f /usr/share/ublue-os/privilieged-setup.hooks.d/10-tailscale.sh
rm -f /usr/share/ublue-os/user-setup.hooks.d/10-vscode.sh

# Remove motd tips that are not relevant to this image
sed -i -e '/Tailscale/d' -e '/kind\.sigs\.k8s\.io/d' /usr/share/ublue-os/motd/tips/10-tips.md
