#!/bin/bash

if pgrep -x "noctalia" > /dev/null || pgrep -x "linux-wallpaperengine" > /dev/null; then
    killall -9 noctalia
    killall -9 linux-wallpaperengine
    echo "Services stopped."
else
    linux-wallpaperengine --silent --screen-root DP-1 --bg 2638946149 &
    linux-wallpaperengine --silent --disable-mouse --disable-parallax --set-property timeofday=3 --screen-root HDMI-A-1 --bg 2504353624 &
    noctalia &
    echo "Services started."
fi
