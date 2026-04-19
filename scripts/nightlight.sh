#!/usr/bin/env bash

# ── Configuration ─────────────────────────────────────────
DAY_TEMP=6500
NIGHT_TEMP=3000

FADE_EVE_START_H=19   # 7:00 PM  → fade begins
FADE_EVE_END_H=20     # 8:00 PM  → full night temp
FADE_MORN_START_H=6   # 6:00 AM  → fade begins
FADE_MORN_END_H=7     # 7:00 AM  → full day temp

TICK_SECONDS=30       # update interval (lower = smoother)
# ──────────────────────────────────────────────────────────

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# Wait for the Wayland socket to actually exist before doing anything
while [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; do
    sleep 2
done

lerp() {
    local from=$1 to=$2 progress=$3  # progress: 0–1000
    echo $(( from + (to - from) * progress / 1000 ))
}

get_target_temp() {
    local now
    now=$(date +%s)
    local h m
    h=$(date +%-H)
    m=$(date +%-M)

    local mins=$(( h * 60 + m ))

    local eve_start=$(( FADE_EVE_START_H  * 60 ))
    local eve_end=$(( FADE_EVE_END_H    * 60 ))
    local morn_start=$(( FADE_MORN_START_H * 60 ))
    local morn_end=$(( FADE_MORN_END_H   * 60 ))

    if (( mins >= eve_start && mins < eve_end )); then
        # Evening fade: day → night
        local progress=$(( (mins - eve_start) * 1000 / (eve_end - eve_start) ))
        lerp $DAY_TEMP $NIGHT_TEMP $progress

    elif (( mins >= morn_start && mins < morn_end )); then
        # Morning fade: night → day
        local progress=$(( (mins - morn_start) * 1000 / (morn_end - morn_start) ))
        lerp $NIGHT_TEMP $DAY_TEMP $progress

    elif (( mins >= eve_end || mins < morn_start )); then
        echo $NIGHT_TEMP

    else
        echo $DAY_TEMP
    fi
}

apply_temp() {
    local temp=$1
    pkill -x wlsunset 2>/dev/null
    # -t and -T both set to the same value forces a fixed temperature
    # -l 90 keeps wlsunset permanently in "night" mode so it never overrides
    wlsunset -t "$temp" -T "$temp" -l 90 -L 0 &
    disown
}

LAST_TEMP=""

while true; do
    TEMP=$(get_target_temp)

    if [[ "$TEMP" != "$LAST_TEMP" ]]; then
        apply_temp "$TEMP"
        LAST_TEMP="$TEMP"
    fi

    sleep "$TICK_SECONDS"
done
