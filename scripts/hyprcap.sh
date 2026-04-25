#!/usr/bin/env bash

STATE_FILE="/tmp/hyprcap-recording"

# Read current recording state
recording_type=""
if [ -f "$STATE_FILE" ]; then
    recording_type=$(cat "$STATE_FILE")
fi

# Build menu based on state
if [ "$recording_type" = "region" ]; then
    options="󰆞 Take Region Screenshot
󰓛 Stop Region Recording
󰖯 Window Screenshot
󰕧 Start Window Recording"
elif [ "$recording_type" = "window" ]; then
    options="󰆞 Take Region Screenshot
󰑋 Start Region Recording
󰖯 Window Screenshot
󰓛 Stop Window Recording"
else
    options="󰆞 Take Region Screenshot
󰑋 Start Region Recording
󰖯 Window Screenshot
󰕧 Start Window Recording"
fi

choice=$(printf "%s\n" "$options" | wofi --dmenu --insensitive --prompt "HyprCap")

start_recording() {
    local type="$1"
    pkill -f "hyprcap.*rec" 2>/dev/null
    echo "$type" > "$STATE_FILE"
    hyprcap rec-start "$type" 
}

stop_recording() {
    pkill -f "hyprcap.*rec" 2>/dev/null
    rm -f "$STATE_FILE"
    hyprcap rec-stop -n -o $XDG_VIDEOS_DIR/Captures -c
}

case "$choice" in
    *Take\ Region\ Screenshot*)
        hyprcap shot region -n -o $XDG_PICTURES_DIR/Screenshots -c
        ;;

    *Start\ Region\ Recording*)
        start_recording region
        ;;

    *Stop\ Region\ Recording*)
        stop_recording
        ;;

    *Window\ Screenshot*)
        hyprcap shot window -n -o $XDG_PICTURES_DIR/Screenshots -c
        ;;

    *Start\ Window\ Recording*)
        start_recording window
        ;;

    *Stop\ Window\ Recording*)
        stop_recording
        ;;
esac
