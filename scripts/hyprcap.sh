#!/usr/bin/env bash

# Detect recording state
is_recording=false
if pgrep -f "hyprcap.*rec" > /dev/null; then
    is_recording=true
fi

# Build menu dynamically
if [ "$is_recording" = true ]; then
    options="󰓛 Stop Recording
󰆞 Region Screenshot
󰑋 Region Recording
󰖯 Window Screenshot
󰕧 Window Recording"
else
    options="󰆞 Region Screenshot
󰑋 Region Recording
󰖯 Window Screenshot
󰕧 Window Recording"
fi

choice=$(printf "%s\n" "$options" | wofi --dmenu --insensitive --prompt "HyprCap")

case "$choice" in
    *Stop\ Recording*)
        hyprcap rec-stop -n -o $XDG_VIDEOS_DIR/Captures -c
        ;;

    *Region\ Screenshot*)
        hyprcap shot region -n -o $XDG_PICTURES_DIR/Screenshots -c
        ;;

    *Region\ Recording*)
        hyprcap rec-start -n region
        ;;

    *Window\ Screenshot*)
        hyprcap shot window -n -o $XDG_PICTURES_DIR/Screenshots -c
        ;;

    *Window\ Recording*)
        hyprcap rec-start window
        ;;
        
esac
