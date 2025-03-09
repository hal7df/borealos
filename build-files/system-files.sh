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
    CURR_LIST_FILE={{ CURR_LIST_FILE  }}
    FLATPAK_LIST=(\$(cat /usr/share/ublue-os/flatpak_list))

    if [[ -n \${CURR_LIST_FILE} ]]; then
        if [[ -f "\${CURR_LIST_FILE}" ]]; then
            mapfile -t CURRENT_FLATPAK_LIST < "\${CURR_LIST_FILE}"
            # convert arrays to sorted newline-separated strings to compare lists and get new flatpaks
            NEW_FLATPAKS=(\$(comm -23 <(printf "%s\n" "\${FLATPAK_LIST[@]}" | sort) <(printf "%s\n" "\${CURRENT_FLATPAK_LIST[@]}" | sort)))
            if [[ \${#NEW_FLATPAKS[@]} -gt 0 ]]; then
                flatpak --system -y install --reinstall --or-update "\${NEW_FLATPAKS[@]}"
                printf "%s\n" "\${FLATPAK_LIST[@]}" > "\${CURR_LIST_FILE}"
                notify-send "Welcome to Aurora" "New flatpak apps have been installed!" --app-name="Flatpak Manager Service" -u NORMAL
            fi
        else
            printf "%s\n" "\${FLATPAK_LIST[@]}" > "\${CURR_LIST_FILE}"
            flatpak --system -y install --or-update "\${FLATPAK_LIST[@]}"
        fi
    else
        flatpak --system -y install --or-update "\${FLATPAK_LIST[@]}"
    fi
EOF

sed -i -e '/^install-system-flatpaks/,/^[^[:space:]]/{/^[[:space:]]/d}'\
    -e '/^install-system-flatpaks/r /tmp/new-install-system-flatpaks.just'\
    /usr/share/ublue-os/just/60-custom.just
