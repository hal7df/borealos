# vim: set ft=make :
#########################
### borealos-custom.just
#########################
## Standardized verbs:
# configure- = configure something that is pre-installed on the image
# install-   = install something, no uninstall or configuration provided
# setup-     = install something and also provide configuration and/or uninstallation options
# toggle-    = turn something on/off, logic can be automatic or manual selection
# fix-       = apply fix/patch/workaround for something
# foo        = no verb is used for shortcuts or something deemed important enough to use a super memorable name

# Configure MAC address randomization for a WiFi network
[group('System')]
configure-wifi-mac network="" mode="":
    #!/usr/bin/env bash
    set -euo pipefail
    NETWORK="{{ network }}"
    MODE="{{ mode }}"

    if [[ -z "$NETWORK" ]]; then
        NETWORK="$(ugum choose --header="Select the WiFi network you would like to configure." $(nmcli -f name,type conn show | grep wifi | awk '{print $1}'))"
    else
        # Validate that the user provided a valid network connection
        nmcli conn show "$NETWORK" >/dev/null
    fi

    CUR_MODE="$(nmcli conn show "$NETWORK" | grep '802-11-wireless.cloned-mac-address' | awk '{print $2}')"

    if [[ -z "$CUR_MODE" || "$CUR_MODE" == "--" ]]; then
        CUR_MODE="default"
    fi

    echo "Current MAC randomization mode for '$NETWORK': '$CUR_MODE'"

    if [[ -z "$MODE" ]]; then
        echo "======================================================================="
        echo "permanent: use the device hardware MAC"
        echo "preserve: do not change the MAC address when connecting to the network"
        echo "stable: generate a stable MAC address uniquely for this network"
        echo "random: generate a random MAC address every time the device connects to this network"
        echo "======================================================================="
        MODE="$(ugum choose permanent preserve stable random)"
    else
        case "$MODE" in
            permanent|preserve|stable|random)
                ;;
            *)
                echo "Unknown MAC randomization mode '$MODE'"
                exit 1
                ;;
        esac
    fi

    nmcli conn mod "$NETWORK" '802-11-wireless.cloned-mac-address' "$MODE"
    echo "Set MAC randomization mode for '$NETWORK' to '$MODE'"
