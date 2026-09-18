#!/usr/bin/env bash
# Plays a sound when a USB device is plugged in or unplugged, like Windows does.
# Started once from Hyprland's autostart and runs for the rest of the session.

set -uo pipefail

SOUND_DIR="${HOTPLUG_SOUND_DIR:-$HOME/.local/share/sounds/electris/stereo}"
ADD_SOUND="${HOTPLUG_ADD_SOUND:-$SOUND_DIR/device-added.wav}"
REMOVE_SOUND="${HOTPLUG_REMOVE_SOUND:-$SOUND_DIR/device-removed.wav}"
# matches noctalia's sound_volume so shell and hotplug sounds sit at one level
VOLUME="${HOTPLUG_VOLUME:-0.4}"
DEBOUNCE_MS="${HOTPLUG_DEBOUNCE_MS:-700}"

last_add=0
last_remove=0

play() {
    [ -r "$1" ] || return 0
    pw-play --volume="$VOLUME" "$1" >/dev/null 2>&1 &
}

# One device fires an event per interface as well as for itself, so anything
# inside the debounce window counts as the same plug.
handle() {
    local now sound
    now=$(date +%s%3N)
    case "$1" in
        add)
            (( now - last_add < DEBOUNCE_MS )) && return 0
            last_add=$now
            sound="$ADD_SOUND"
            ;;
        remove)
            (( now - last_remove < DEBOUNCE_MS )) && return 0
            last_remove=$now
            sound="$REMOVE_SOUND"
            ;;
        *) return 0 ;;
    esac
    play "$sound"
}

while true; do
    action=""
    devtype=""
    while IFS= read -r line; do
        case "$line" in
            ACTION=*)  action="${line#ACTION=}" ;;
            DEVTYPE=*) devtype="${line#DEVTYPE=}" ;;
            "")
                [ "$devtype" = "usb_device" ] && handle "$action"
                action=""
                devtype=""
                ;;
        esac
    done < <(stdbuf -oL udevadm monitor --udev --property --subsystem-match=usb)
    sleep 2
done
