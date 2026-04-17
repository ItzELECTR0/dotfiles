#!/bin/bash

DISPLAY=$1
shift
VALUES=("$@")

# Get current brightness
CURRENT=$(ddcutil getvcp 10 --display $DISPLAY | grep -oP 'current value =\s+\K\d+')

# Find next value in cycle
FOUND=0
for i in "${!VALUES[@]}"; do
    if [ $FOUND -eq 1 ]; then
        ddcutil setvcp 10 ${VALUES[$i]} --display $DISPLAY
        exit 0
    fi
    if [ "${VALUES[$i]}" -eq "$CURRENT" ]; then
        FOUND=1
    fi
done

# If we're here, set to first value
ddcutil setvcp 10 ${VALUES[0]} --display $DISPLAY