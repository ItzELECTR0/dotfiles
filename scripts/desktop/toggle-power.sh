#!/bin/bash

DISPLAY=$1
STATE_FILE="/tmp/monitor_${DISPLAY}_power_state"

# Set power-off code based on display
if [ "$DISPLAY" -eq 2 ]; then
    # Display 2 (secondary) - use 0x04 to avoid blinking light
    POWER_OFF_CODE=0x04
else
    # Display 1 (main) - use 0x02 to stay connected
    POWER_OFF_CODE=0x02
fi

# Track state manually since reading might not work
if [ -f "$STATE_FILE" ]; then
    # Monitor is marked as off, turn it on
    ddcutil setvcp d6 0x01 --display $DISPLAY --sleep-multiplier 0.1
    rm "$STATE_FILE"
else
    # Monitor is marked as on, turn it off
    ddcutil setvcp d6 $POWER_OFF_CODE --display $DISPLAY --sleep-multiplier 0.1
    touch "$STATE_FILE"
fi