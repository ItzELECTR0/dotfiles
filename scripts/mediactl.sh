#!/bin/bash

# Extract cover art from FLAC files for Jellyfin
# Usage: ./extract_covers.sh [--dry-run] [--check-all] [--jobs N]

MUSIC_DIR="/home/ELECTRO/Media/Music"
DRY_RUN=false
CHECK_ALL=false
JOBS=4

COLOR_ARTIST='\033[1;36m'
COLOR_ALBUM='\033[1;33m'
COLOR_RESET='\033[0m'

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)   DRY_RUN=true ;;
        --check-all) CHECK_ALL=true ;;
        --jobs)
            # $2 must exist and be a positive integer before shifting
            [[ "${2-}" =~ ^[1-9][0-9]*$ ]] \
                || { printf 'Error: --jobs requires a positive integer\n' >&2; exit 1; }
            JOBS="$2"; shift
            ;;
        --jobs=*)
            val="${1#*=}"
            [[ "$val" =~ ^[1-9][0-9]*$ ]] \
                || { printf 'Error: --jobs= requires a positive integer\n' >&2; exit 1; }
            JOBS="$val"
            ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

# Dependency checks
command -v metaflac &>/dev/null || { printf 'metaflac not found (flac package)\n' >&2; exit 1; }
command -v flock    &>/dev/null || { printf 'flock not found (util-linux)\n'      >&2; exit 1; }

# Parallel stats flock file
STATS_DIR=$(mktemp -d)

stat_inc() {
    {
        flock -x 9
        printf '%s\n' "$1" >> "$STATS_DIR/counts"
    } 9>>"$STATS_DIR/counts.lock"
}

count_stat() {
    if [[ -f "$STATS_DIR/counts" ]]; then
        grep -c "^$1$" "$STATS_DIR/counts"
    else
        echo 0
    fi
}

print_stats() {
    local cover_proc cover_skip cover_fail nfo_proc nfo_skip nfo_fail
    cover_proc=$(count_stat cover_proc)
    cover_skip=$(count_stat cover_skip)
    cover_fail=$(count_stat cover_fail)
    nfo_proc=$(count_stat nfo_proc)
    nfo_skip=$(count_stat nfo_skip)
    nfo_fail=$(count_stat nfo_fail)

    printf '\n========================================\n'
    printf 'Total checked : %s\n'   "$(count_stat total)"
    printf 'Processed     : %s\n'   "$(( cover_proc + nfo_proc ))"
    printf '  ├─ Covers   : %s\n'   "$cover_proc"
    printf '  └─ Metadata : %s\n'   "$nfo_proc"
    printf 'Skipped       : %s\n'   "$(( cover_skip + nfo_skip ))"
    printf '  ├─ Covers   : %s\n'   "$cover_skip"
    printf '  └─ Metadata : %s\n'   "$nfo_skip"
    printf 'Failed        : %s\n'   "$(( cover_fail + nfo_fail ))"
    printf '  ├─ Covers   : %s\n'   "$cover_fail"
    printf '  └─ Metadata : %s\n'   "$nfo_fail"
    printf '========================================\n'
}

# Signal / exit handlers
_INTERRUPTED=false

_on_interrupt() {
    _INTERRUPTED=true
    printf '\n\n========================================\n'
    printf 'Interrupted by user (CTRL+C)\n'
    find "$MUSIC_DIR" -name ".cover.*.tmp"        -type f -delete 2>/dev/null
    find "$MUSIC_DIR" -name ".cover_extract.lock" -type f -delete 2>/dev/null
    printf 'Cleaned up temporary files\n'
    print_stats
    rm -rf "$STATS_DIR"
    exit 130
}

_on_exit() {
    [[ "$_INTERRUPTED" == true ]] && return
    find "$MUSIC_DIR" -name ".cover_extract.lock" -type f -delete 2>/dev/null
    print_stats
    rm -rf "$STATS_DIR"
}

trap '_on_interrupt' INT
trap '_on_exit'      EXIT

# find helpers
TRASH_PRUNE=(
    ! -ipath '*/.Trash*'
    ! -ipath '*/$RECYCLE.BIN*'
    ! -iname 'RECYCLER'
)

# Check all mode
if [[ "$CHECK_ALL" == true ]]; then
    printf 'Listing all artists and albums...\n========================================\n'
    while IFS= read -r artist_dir; do
        artist_name="${artist_dir##*/}"
        albums=()
        while IFS= read -r album_dir; do
            albums+=( "${album_dir##*/}" )
        done < <(find "$artist_dir" -mindepth 1 -maxdepth 1 -type d \
                     "${TRASH_PRUNE[@]}" | sort)
        if [[ ${#albums[@]} -gt 0 ]]; then
            printf "${COLOR_ARTIST}%s${COLOR_RESET}: " "$artist_name"
            for (( i=0; i<${#albums[@]}; i++ )); do
                printf "${COLOR_ALBUM}%s${COLOR_RESET}" "${albums[$i]}"
                (( i < ${#albums[@]}-1 )) && printf ', '
            done
            printf '\n'
        fi
    done < <(find "$MUSIC_DIR" -mindepth 1 -maxdepth 1 -type d \
                 "${TRASH_PRUNE[@]}" | sort)
    exit 0
fi

# export so xargs workers can call it
process_album() {
    local album_dir="$1"
    local out=''
    local cover_status=''   # proc | skip | fail
    local nfo_status=''     # proc | skip | fail

    # Per-album advisory lock
    local lock_file="$album_dir/.cover_extract.lock"
    exec {lock_fd}<>"$lock_file"
    if ! flock -n "$lock_fd"; then
        exec {lock_fd}>&-
        return # silently skip
    fi

    stat_inc total
    out+="\nChecking: $album_dir\n"

    # cover
    if [[ -f "$album_dir/folder.jpg" ]]; then
        out+="  → Cover   : Skipped (folder.jpg already exists)\n"
        cover_status=skip

    elif [[ -f "$album_dir/cover.jpg" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            out+="  → Cover   : [DRY RUN] Would rename cover.jpg → folder.jpg\n"
        else
            mv -- "$album_dir/cover.jpg" "$album_dir/folder.jpg"
            out+="  → Cover   : Renamed cover.jpg → folder.jpg\n"
        fi
        cover_status=proc

    elif [[ -f "$album_dir/folder.png" ]]; then
        out+="  → Cover   : Skipped (folder.png already exists)\n"
        cover_status=skip

    elif [[ -f "$album_dir/cover.png" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            out+="  → Cover   : [DRY RUN] Would rename cover.png → folder.png\n"
        else
            mv -- "$album_dir/cover.png" "$album_dir/folder.png"
            out+="  → Cover   : Renamed cover.png → folder.png\n"
        fi
        cover_status=proc

    else
        # FLAC extraction
        local flac_file
        flac_file=$(find "$album_dir" -type f -name '*.flac' -print -quit)

        if [[ -z "$flac_file" ]]; then
            out+="  → Cover   : Skipped (no FLAC files found)\n"
            cover_status=skip
        else
            # Read the MIME type from the FLAC picture block metadata
            local mime
            mime=$(metaflac --list --block-type=PICTURE "$flac_file" 2>/dev/null \
                   | awk '/MIME type:/ { print $NF; exit }')

            if [[ -z "$mime" ]]; then
                out+="  → Cover   : Skipped (no embedded picture in ${flac_file##*/})\n"
                cover_status=skip

            elif [[ "$DRY_RUN" == true ]]; then
                out+="  → Cover   : [DRY RUN] Would extract $mime from ${flac_file##*/}\n"
                cover_status=proc

            else
                local dest
                case "$mime" in
                    image/png) dest="$album_dir/folder.png" ;;
                    *)         dest="$album_dir/folder.jpg" ;;
                esac

                local tmp_file
                if ! tmp_file=$(mktemp "$album_dir/.cover.XXXXXX.tmp" 2>/dev/null); then
                    out+="  ✗ Cover   : FAILED: Could not create temp file in $album_dir\n"
                    cover_status=fail

                elif metaflac --export-picture-to="$tmp_file" "$flac_file" 2>/dev/null \
                     && [[ -s "$tmp_file" ]]; then
                    # Check that $tmp_file is gone to confirm the rename happened.
                    if mv -n -- "$tmp_file" "$dest"; then
                        out+="  ✓ Cover   : Extracted as ${dest##*/} ($mime)\n"
                        cover_status=proc
                    else
                        rm -f "$tmp_file"
                        out+="  → Cover   : Skipped (destination appeared between check and write)\n"
                        cover_status=skip
                    fi
                else
                    rm -f "$tmp_file"
                    out+="  ✗ Cover   : FAILED: metaflac could not extract picture\n"
                    cover_status=fail
                fi
            fi
        fi
    fi

    # metadata
    if [[ -f "$album_dir/album.nfo" ]]; then
        out+="  → Metadata: album.nfo already exists\n"
        nfo_status=skip
    else
        local nfo_file
        nfo_file=$(find "$album_dir" -maxdepth 1 -type f -iname '*.nfo' -print -quit)

        if [[ -z "$nfo_file" ]]; then
            out+="  → Metadata: No NFO file found\n"
            nfo_status=skip
        else
            if [[ "$DRY_RUN" == true ]]; then
                out+="  → Metadata: [DRY RUN] Would rename ${nfo_file##*/} → album.nfo\n"
                nfo_status=proc
            elif mv -- "$nfo_file" "$album_dir/album.nfo"; then
                out+="  → Metadata: Renamed ${nfo_file##*/} → album.nfo\n"
                nfo_status=proc
            else
                out+="  ✗ Metadata: FAILED: Could not rename ${nfo_file##*/} → album.nfo\n"
                nfo_status=fail
            fi
        fi
    fi

    # Stats
    stat_inc "cover_${cover_status}"
    stat_inc "nfo_${nfo_status}"

    exec {lock_fd}>&-   # release per-album advisory lock
    printf '%b' "$out"  # single write output from parallel workers stays coherent
}

export -f process_album stat_inc
export STATS_DIR DRY_RUN

# Main loop
[[ "$DRY_RUN" == true ]] && printf 'DRY RUN MODE | No files will be modified\n'
printf 'Starting cover art extraction...\nScanning : %s\nJobs     : %s\n' \
    "$MUSIC_DIR" "$JOBS"
printf -- '----------------------------------------\n'

find "$MUSIC_DIR" -mindepth 2 -maxdepth 2 -type d \
    "${TRASH_PRUNE[@]}" \
    -print0 \
| xargs -0 -P "$JOBS" -n 1 bash -c 'process_album "$1"' _

printf '\nExtraction complete!'