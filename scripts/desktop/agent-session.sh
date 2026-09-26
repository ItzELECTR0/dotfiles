#!/bin/bash
# Headless sway session for agents. It has its own seat and never touches the live desktop.
set -euo pipefail

unit=agent-session
envfile="$XDG_RUNTIME_DIR/agent-session.env"
conf="$XDG_RUNTIME_DIR/agent-session.sway"
size=${AGENT_SESSION_SIZE:-1920x1080}
input_dir="$(dirname "$(readlink -f "$0")")/agent-input"
input="$input_dir/build/agent-input"
socket="$XDG_RUNTIME_DIR/agent-input.sock"

load() {
    [[ -f $envfile ]] || { echo "agent session is not running" >&2; exit 1; }
    cat "$envfile"
}

case ${1:-} in
start)
    if systemctl --user -q is-active "$unit"; then load; exit 0; fi
    rm -f "$envfile"
    make -s -C "$input_dir" >&2
    # Type with the same layouts as the live desktop, minus its layout-switching options.
    layout=$(hyprctl getoption input:kb_layout 2>/dev/null | awk '/^str:/ {print $2}')
    variant=$(hyprctl getoption input:kb_variant 2>/dev/null | awk '/^str:/ {print $2}')
    x=42
    while [[ -e /tmp/.X11-unix/X$x || -e /tmp/.X$x-lock ]]; do x=$((x + 1)); done
    cat > "$conf" <<EOF
xwayland disable
swaybg_command -
output HEADLESS-1 resolution $size
exec printf 'export WAYLAND_DISPLAY=%q SWAYSOCK=%q DBUS_SESSION_BUS_ADDRESS=%q DISPLAY=:$x\n' "\$WAYLAND_DISPLAY" "\$SWAYSOCK" "\$DBUS_SESSION_BUS_ADDRESS" > "$envfile"
exec xwayland-satellite :$x
exec env XKB_DEFAULT_LAYOUT=$(printf %q "${layout:-us}") XKB_DEFAULT_VARIANT=$(printf %q "$variant") $(printf %q "$input") serve $size
EOF
    # The user manager carries the live session's DISPLAY and WAYLAND_DISPLAY, so strip them.
    # XWayland is off because xwayland-satellite serves X11 on the session's own display instead.
    systemd-run --user -q --collect --unit="$unit" \
        -E WLR_BACKENDS=headless -E WLR_RENDERER=pixman -E WLR_LIBINPUT_NO_DEVICES=1 \
        -E XDG_CURRENT_DESKTOP=sway -E XDG_SESSION_TYPE=wayland \
        env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        dbus-run-session -- sway --unsupported-gpu -c "$conf"
    for _ in $(seq 50); do
        [[ -s $envfile && -S $socket && -S /tmp/.X11-unix/X$x ]] && { load; exit 0; }
        systemctl --user -q is-active "$unit" || break
        sleep 0.1
    done
    echo "agent session failed to start, see: journalctl --user -u $unit" >&2
    exit 1
    ;;
stop)
    systemctl --user stop "$unit" 2>/dev/null || true
    rm -f "$envfile" "$conf" "$socket"
    ;;
status)
    systemctl --user -q is-active "$unit" && load
    ;;
env)
    load
    ;;
run)
    shift
    eval "$(load)"
    # Each app gets its own unit bound to the session, so stop takes it down too.
    systemd-run --user -q --collect --same-dir \
        -p BindsTo="$unit.service" -p After="$unit.service" \
        -E WAYLAND_DISPLAY="$WAYLAND_DISPLAY" -E SWAYSOCK="$SWAYSOCK" \
        -E DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        -E DISPLAY="$DISPLAY" -E XDG_CURRENT_DESKTOP=sway -E XDG_SESSION_TYPE=wayland \
        env -u HYPRLAND_INSTANCE_SIGNATURE "$@"
    ;;
input)
    shift
    exec "$input" "$@"
    ;;
*)
    echo "usage: ${0##*/} start|stop|status|env|run <command...>|input <command...>" >&2
    exit 2
    ;;
esac
