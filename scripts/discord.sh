#!/usr/bin/env bash

for variant in discord-canary discord-ptb discord; do
    if command -v "$variant" &>/dev/null; then
        exec "$variant" --enable-features=UseOzonePlatform --ozone-platform=wayland "$@"
    fi
done

echo "No Discord installation found. Install discord, discord-ptb, or discord-canary from the AUR" >&2
exit 1
