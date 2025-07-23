# Add custom ujust commands
cat /tmp/just/*.just >> /usr/share/ublue-os/just/60-custom.just

# Disable unattended installation of flatpaks on user sign in
SYS_FLATPAK_AUTOINSTALL_MSG="# Disabled to avoid changing the system software install without user consent. The below command can be run manually if desired."
sed -i "s/^\\(ujust install-system-flatpaks\\)/$SYS_FLATPAK_AUTOINSTALL_MSG\n#\\1"\
    /usr/libexec/ublue-flatpak-manager

# Modify flatpak management to use the borealos flatpak list
cp /tmp/flatpaks.txt /usr/share/ublue-os/flatpak_list

cat > /tmp/new-install-system-flatpaks.just << EOF
    #!/usr/bin/env bash

    # Ensure the Flathub remote exists
    flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo

    # Disable Fedora Flatpak remotes
    for remote in fedora fedora-testing; do
        if flatpak remote-list | grep -q "\$remote"; then
            flatpak remote-delete "\$remote"
        fi
    done

    # reinstall base flatpaks
    xargs flatpak --system -y --reinstall --or-update < /usr/share/ublue-os/flatpak_list
EOF

sed -i -e '/^install-system-flatpaks/,/^[^[:space:]]/{/^[[:space:]]/d}'\
    -e '/^install-system-flatpaks/r /tmp/new-install-system-flatpaks.just'\
    /usr/share/ublue-os/just/60-custom.just
