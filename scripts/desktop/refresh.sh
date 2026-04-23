#!/bin/bash

if pgrep -x "qs" > /dev/null || pgrep -x "linux-wallpaperengine" > /dev/null; then
    killall -9 qs
    killall -9 linux-wallpaperengine
    echo "Services stopped."
else
    exec linux-wallpaperengine --silent --screen-root DP-1 --bg 2638946149 &
    exec linux-wallpaperengine --silent --disable-mouse --disable-parallax --set-property timeofday=3 --screen-root HDMI-A-1 --bg 2504353624 &
    exec qs -c noctalia-shell &
    echo "Services started."
fi