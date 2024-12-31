#!/bin/bash

# Remove ptyxis integration
rm /usr/bin/kde-ptyxis
rm /usr/share/kglobalaccel/org.gnome.Ptyxis.desktop
sed -i 's/org\.gnome\.Ptyxis/org.kde.konsole/g' /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
sed -i 's/org\.gnome\.Ptyxis/org.kde.konsole/g' /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/config/main.xml
sed -i -e 's/org\.gnome\.Ptyxis/org.kde.konsole/g' -e 's/kde-ptyxis/konsole/g' /usr/share/kde-settings/kde-profile/default/xdg/kdeglobals

# Clean out unused yum repositories
rm -f {,/usr}/etc/yum.repos.d/{google-chrome,vscode,docker-ce}.repo

# Remove config files for packages that are not shipped in this image
rm -f /usr/libexec/aurora-dx-user-vscode
rm -f /usr/lib/systemd/user/aurora-dx-user-vscode.service
rm -f {,/usr}/etc/profile.d/vscode-{aurora,bluefin}-profile.sh
rm -rf {,/usr}/etc/skel/.config/Code

# Remove kind
rm -f /usr/bin/kind

# Remove motd tips that are not relevant to this image
sed -i -e '/Tailscale/d' -e '/kind\.sigs\.k8s\.io/d' /usr/share/ublue-os/motd/tips/10-tips.md
