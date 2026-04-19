#!/bin/bash

# Kill existing instances
killall -9 qs
killall -9 linux-wallpaperengine

# Restart wallpaper engine instances
exec linux-wallpaperengine --silent --screen-root DP-1 --bg 2638946149 &
exec linux-wallpaperengine --silent --disable-mouse --disable-parallax --set-property timeofday=3 --screen-root HDMI-A-1 --bg 2504353624 &

# Restart waybar and swaync
exec qs -c noctalia-shell &