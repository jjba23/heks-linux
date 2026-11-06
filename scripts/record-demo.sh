#!/usr/bin/env bash
# heks-linux
#
# SPDX-License-Identifier: MIT
# Copyright © Josep Bigorra <jjbigorra@gmail.com>
#
# Record the demo GIF: one command, one file, the same tour every time.
#
# The tour is driven by the programs the desktop already has, not by synthetic
# input.  A palette change runs `heks-rofi-theme-menu` with ROFI_RETV=1 - the
# same script the bar's palette button and every heks-toon card run - and each
# beat waits for that script's own progress file to say `done`, so a beat lasts
# as long as the switch lasts instead of as long as a sleep guessed it would.
# The clip is encoded by `heks-capture gif-from`, so there is one GIF pipeline
# (gifski, quality 90, cross-frame palettes) and this script has no second copy
# of it to drift.
#
# The other surfaces are shown the way they are reached: the dock exposes what a
# click does over its own REPL socket (the launchpad, and the auto-hide the
# recording needs off), rofi opens its application list, and heks-toon opens its
# palette and wall views.  Nothing here needs a keyboard, a pointer or an X
# server, so the tour is reproducible: the same palettes, the same scenes, in
# the same order with the same holds.
#
# The lock screen is the one surface the tour cannot open for real: niri locks
# through ext-session-lock, and the protocol keeps the session locked if the
# locker dies, so a recording that locked would need a password to get out of.
# The tour therefore appends a still of the lock screen drawn from the arguments
# the niri config hands swaylock - same ring, same inside fill, over the
# wallpaper on the wall - taken while the tour's last palette is still the
# active one.

set -uo pipefail

me=${0##*/}

width=1280
hold=2
scene_hold=2.5
picker_hold=2.5
lock_hold=2.5
palettes=(catppuccin-mocha rose-pine catppuccin-latte)
tour=()
with_picker=1
with_launcher=1
with_toon=1
with_launchpad=1
with_lock=1
small=0
gif_args=()
launcher_filter=""
output="heks-demo.gif"
from=""
keep=0
dry_run=0
rehearse=0

die() {
    printf '%s: %s\n' "$me" "$*" >&2
    exit 1
}

say() {
    printf '%s\n' "$*" >&2
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is not installed"
}

usage() {
    cat <<'HEKS_DEMO'
record-demo.sh: record the heks-linux demo GIF from a running session

Usage: record-demo.sh [options]

  --palette NAME   add a palette to the tour (repeatable; default:
                   catppuccin-mocha rose-pine catppuccin-latte)
  --width PX       GIF width (default 1280; 0 keeps the recorded width)
  --hold SECONDS   how long each palette is held (default 2)
  --scene SECONDS  how long a window scene is held (default 2.5)
  --picker SECONDS how long the swatch picker stays on screen (default 2.5)
  --launcher-filter TEXT  open the application list already filtered by TEXT
  --no-launcher    leave rofi's application list out
  --no-toon        leave heks-toon's palette and wall views out
  --no-launchpad   leave the dock's launchpad out
  --no-picker      leave the swatch picker out
  --lock SECONDS   how long the lock-screen still is held (default 2.5)
  --no-lock        leave the lock-screen still out
  --small          encode with the capture program's small preset (640 px, 12 fps)
  --output FILE    where the GIF lands (default heks-demo.gif)
  --from FILE      skip the tour and encode an existing recording
  --keep           keep the intermediate recording next to the GIF
  --rehearse       run the tour on screen without recording anything
  --dry-run        print the tour and exit without touching the screen
  -h, --help       this text

The tour: the desktop, a palette switch, rofi's application list, a second
switch, heks-toon's palettes, a third switch, the swatch picker, heks-toon's            walls, then the dock's launchpad.  The lock screen closes the tour as a
still drawn from the same palette values swaylock is given, because locking for
real would need a password to get out of.  The dock's auto-hide is turned off
for the recording and back on afterwards, and the session's palette is recorded
first and put back at the end, so a run leaves the desktop as it found it.
HEKS_DEMO
}

while [ $# -gt 0 ]; do
    case "$1" in
        --palette) shift; [ -n "${1:-}" ] || die "--palette needs a name"; tour+=("$1") ;;
        --width) shift; width=${1:-} ;;
        --hold) shift; hold=${1:-} ;;
        --scene) shift; scene_hold=${1:-} ;;
        --picker) shift; picker_hold=${1:-} ;;
        --launcher-filter) shift; launcher_filter=${1:-} ;;
        --no-launcher) with_launcher=0 ;;
        --no-toon) with_toon=0 ;;
        --no-launchpad) with_launchpad=0 ;;
        --no-picker) with_picker=0 ;;
        --lock) shift; lock_hold=${1:-} ;;
        --no-lock) with_lock=0 ;;
        --small) small=1 ;;
        --output) shift; output=${1:-} ;;
        --from) shift; from=${1:-} ;;
        --keep) keep=1 ;;
        --rehearse) rehearse=1 ;;
        --dry-run) dry_run=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option $1 (try --help)" ;;
    esac
    shift
done

case "$width" in ''|*[!0-9]*) die "--width needs a whole number of pixels" ;; esac
case "$hold" in ''|*[!0-9.]*) die "--hold needs a number of seconds" ;; esac
case "$scene_hold" in ''|*[!0-9.]*) die "--scene needs a number of seconds" ;; esac
case "$picker_hold" in ''|*[!0-9.]*) die "--picker needs a number of seconds" ;; esac
case "$lock_hold" in ''|*[!0-9.]*) die "--lock needs a number of seconds" ;; esac
[ -n "$output" ] || die "--output needs a path"

picker=$(command -v heks-rofi-theme-menu || true)
[ -n "$picker" ] || die "heks-rofi-theme-menu is not installed: run maak install-rofi"
capture=$(command -v heks-capture || true)
[ -n "$capture" ] || die "heks-capture is not installed: run maak install-capture"

progress=${XDG_RUNTIME_DIR:-/tmp}/heks-theme-progress
# The picker names the palette it is wearing and the one it is switching to, and
# nothing else in the session spells a palette besides the settings file.  Its
# list mode is therefore also how this finds the palette to put back.
palette_rows() {
    ROFI_RETV=0 "$picker" 2>/dev/null | tr '\0' '\n' | sed -n 's/^display\x1f//p'
}

palette_names() {
    palette_rows | sed 's/^\(.*\)  (current)$/\1/'
}

current_palette() {
    palette_rows | sed -n 's/^\(.*\)  (current)$/\1/p'
}

palette_known() {
    palette_names | grep -Fxq -- "$1"
}

# A beat is over when the switch says so.  `apply_theme` reports failure through
# this file and not through its exit status, so the file is what is read: a
# palette that fails would otherwise be recorded as a beat that worked.
switch_to() {
    local name="$1" i=0
    rm -f "$progress"
    ROFI_RETV=1 "$picker" "$name" >/dev/null 2>&1
    while [ "$i" -lt 900 ]; do
        case "$(cat "$progress" 2>/dev/null)" in
            done*) return 0 ;;
            failed*) return 1 ;;
        esac
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

# ====== The dock ======
#
# Lambdock is a Guile program with a REPL on its own socket, and its
# `(lambdock core)' module exports what the dock's buttons do: the launchpad,
# and the auto-hide setting.  Driving those is the difference between a demo of
# a dock that is off-screen and one that is there.

dock_socket=${TMPDIR:-/tmp}/lambdock-repl.sock
dock_core='(resolve-module (quote (lambdock core)))'
launchpad_up=0
autohide_flipped=0
autohide_original=""

dock_available() {
    [ -S "$dock_socket" ] && command -v nc >/dev/null 2>&1
}

dock_call() {
    printf '%s\n' "$1" | timeout 4 nc -U -w 1 "$dock_socket" 2>/dev/null
}

dock_do() {
    local proc="$1" arg="${2:-}"
    if [ -n "$arg" ]; then
        dock_call "(let ((m $dock_core)) ((module-ref m '$proc) $arg))" >/dev/null
    else
        dock_call "(let ((m $dock_core)) ((module-ref m '$proc)))" >/dev/null
    fi
}

dock_autohide_state() {
    dock_call "(let ((m $dock_core)) (write ((module-ref m 'get-dock-auto-hide?))) (newline))" \
        | tr -d '\r' | grep -oE '#[tf]' | tail -n 1
}

launchpad_shown() {
    local layers
    command -v niri >/dev/null 2>&1 || return 1
    layers=$(niri msg layers 2>/dev/null) || return 1
    case "$layers" in *lambdock-launchpad*) return 0 ;; esac
    return 1
}

# A dock that hides itself is off-screen for the whole recording, so it is shown
# for the run and put back afterwards.  The setting is the dock's, not a file:
# nothing is written, so an interrupted run leaves no half-rewritten config.
dock_show_setup() {
    dock_available || {
        say "dock: no REPL on $dock_socket, so the launchpad and auto-hide are left alone"
        with_launchpad=0
        return 0
    }
    autohide_original=$(dock_autohide_state)
    if [ "$autohide_original" = "#t" ]; then
        dock_do set-dock-auto-hide! '#f'
        autohide_flipped=1
        say "dock: auto-hide off for the recording"
    fi
}

# ====== Scenes ======

scene_picker() {
    say "picker: open"
    rofi -replace -show theme >/dev/null 2>&1 &
    rofi_pid=$!
    sleep 0.4
    kill -0 "$rofi_pid" 2>/dev/null || die "rofi did not open the theme picker"
    sleep "$picker_hold"
    kill -TERM "$rofi_pid" 2>/dev/null
    wait "$rofi_pid" 2>/dev/null
    rofi_pid=""
    sleep 0.4
}

scene_launcher() {
    local args=(-replace -show drun)
    say "launcher: open"
    [ -n "$launcher_filter" ] && args+=(-filter "$launcher_filter")
    rofi "${args[@]}" >/dev/null 2>&1 &
    rofi_pid=$!
    sleep 0.6
    if ! kill -0 "$rofi_pid" 2>/dev/null; then
        say "launcher: rofi did not open its application list, skipping"
        rofi_pid=""
        return 0
    fi
    sleep "$scene_hold"
    kill -TERM "$rofi_pid" 2>/dev/null
    wait "$rofi_pid" 2>/dev/null
    rofi_pid=""
    sleep 0.3
}

scene_toon() {
    local view="$1" i=0 windows
    command -v heks-toon >/dev/null 2>&1 || {
        say "toon: heks-toon is not installed, skipping $view"
        return 0
    }
    say "toon: $view"
    heks-toon "$view" >"$state/toon-$view.log" 2>&1 &
    toon_pid=$!
    # The beat starts when the window is on screen, not when the process is:
    # the compositor rule opens it focused, and a first frame of empty desktop
    # is a second of the demo saying nothing.
    while [ "$i" -lt 40 ]; do
        windows=$(niri msg windows 2>/dev/null) || windows=""
        case "$windows" in *'App ID: "heks-toon"'*) break ;; esac
        sleep 0.1
        i=$((i + 1))
    done
    sleep "$scene_hold"
    kill -TERM "$toon_pid" 2>/dev/null
    wait "$toon_pid" 2>/dev/null
    toon_pid=""
    sleep 0.3
}

scene_launchpad() {
    local i=0
    dock_available || return 0
    say "launchpad: open"
    dock_do show-launchpad! || return 0
    launchpad_up=1
    while [ "$i" -lt 30 ]; do
        launchpad_shown && break
        sleep 0.1
        i=$((i + 1))
    done
    sleep "$scene_hold"
    dock_do hide-launchpad!
    launchpad_up=0
    i=0
    while [ "$i" -lt 30 ]; do
        launchpad_shown || break
        sleep 0.1
        i=$((i + 1))
    done
    sleep 0.3
}

# ====== What the run will do ======

original=""
if [ -z "$from" ]; then
    original=$(current_palette)
    [ -n "$original" ] || die "could not tell which palette is active: is this a heks-linux session?"
    if [ "${#tour[@]}" -eq 0 ]; then
        tour=("${palettes[@]}")
    fi
    for name in "${tour[@]}"; do
        palette_known "$name" || die "unknown palette: $name"
    done
fi

state=$(mktemp -d "${TMPDIR:-/tmp}/heks-demo.XXXXXX") || die "cannot create a work directory"
rec_pid=""
rofi_pid=""
toon_pid=""
switched=0

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [ -n "$rofi_pid" ] && kill -0 "$rofi_pid" 2>/dev/null; then
        kill -TERM "$rofi_pid" 2>/dev/null
    fi
    if [ -n "$toon_pid" ] && kill -0 "$toon_pid" 2>/dev/null; then
        kill -TERM "$toon_pid" 2>/dev/null
    fi
    if [ "$launchpad_up" = 1 ]; then
        dock_do hide-launchpad!
        launchpad_up=0
    fi
    stop_recorder
    # The desktop goes back even when the run failed or was interrupted: the
    # script records a desktop, it does not get to own one of its surfaces.
    if [ "$autohide_flipped" = 1 ]; then
        dock_do set-dock-auto-hide! '#t'
        autohide_flipped=0
    fi
    if [ "$switched" = 1 ] && [ -n "$original" ]; then
        say "restoring palette: $original"
        switch_to "$original" || say "warning: could not restore $original"
    fi
    rm -rf "$state"
    exit "$status"
}
trap cleanup EXIT INT TERM

# ====== Recording ======

start_recorder() {
    local clip="$state/clip.mp4"
    rm -f "$clip"
    if command -v wl-screenrec >/dev/null 2>&1; then
        # The cursor is left out: a demo shows the desktop, not a pointer that
        # nobody moved, and none of these scenes needs a pointer at all.
        wl-screenrec --codec avc -m 30 --no-cursor -f "$clip" \
            >>"$state/recorder.log" 2>&1 &
    elif command -v wf-recorder >/dev/null 2>&1; then
        wf-recorder -f "$clip" -c libx264 -x yuv420p -r 30 \
            -p crf=18 -p preset=veryfast -p profile=main -p level=4.2 \
            >>"$state/recorder.log" 2>&1 &
    else
        die "no recorder: install wl-screenrec or wf-recorder"
    fi
    rec_pid=$!
    sleep 0.5
    kill -0 "$rec_pid" 2>/dev/null \
        || die "the recorder exited at once: $(tail -n 3 "$state/recorder.log" 2>/dev/null)"
    printf '%s' "$clip" > "$state/clip.path"
}

# SIGINT is how every ffmpeg front end writes its trailer; SIGTERM leaves a
# header that passes a size test and plays nothing.
stop_recorder() {
    local i=0
    [ -n "$rec_pid" ] || return 0
    if kill -0 "$rec_pid" 2>/dev/null; then
        kill -INT "$rec_pid" 2>/dev/null
        while kill -0 "$rec_pid" 2>/dev/null && [ "$i" -lt 150 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        if kill -0 "$rec_pid" 2>/dev/null; then
            kill -TERM "$rec_pid" 2>/dev/null
        fi
    fi
    wait "$rec_pid" 2>/dev/null
    rec_pid=""
}

# ====== The lock screen ======
#
# A still, not a lock.  It is drawn from the installed niri config's own swaylock
# arguments - the ring colour, the inside fill, the indicator's radius and
# thickness - over the wallpaper that is on the wall, so the palette on show is
# the palette swaylock would be handed rather than a description of it.
render_lock_preview() {
    local clip="$1" png="$state/lock-preview.png" conf width height wallpaper
    local line ring inside radius thickness
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
    [ -f "$conf" ] || { say "lock screen: no niri config, skipping"; return 1; }
    line=$(grep -o 'swaylock [^"]*' "$conf" 2>/dev/null | head -n 1)
    [ -n "$line" ] || { say "lock screen: no swaylock line in the niri config, skipping"; return 1; }
    ring=$(printf '%s\n' "$line" | sed -n 's/.*--ring-color \([0-9a-fA-F]*\).*/\1/p')
    inside=$(printf '%s\n' "$line" | sed -n 's/.*--inside-color \([0-9a-fA-F]*\).*/\1/p')
    radius=$(printf '%s\n' "$line" | sed -n 's/.*--indicator-radius \([0-9]*\).*/\1/p')
    thickness=$(printf '%s\n' "$line" | sed -n 's/.*--indicator-thickness \([0-9]*\).*/\1/p')
    [ -n "$ring" ] && [ -n "$inside" ] \
        || { say "lock screen: the swaylock line names no ring or inside colour, skipping"; return 1; }
    command -v magick >/dev/null 2>&1 || { say "lock screen: ImageMagick is not installed, skipping"; return 1; }
    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
        -of default=nw=1:nk=1 "$clip" 2>/dev/null | head -n 1)
    height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
        -of default=nw=1:nk=1 "$clip" 2>/dev/null | head -n 1)
    case "$width" in ''|*[!0-9]*) return 1 ;; esac
    case "$height" in ''|*[!0-9]*) return 1 ;; esac
    wallpaper=$(command -v heks-wallpaper >/dev/null 2>&1 && heks-wallpaper current 2>/dev/null)
    [ -f "${wallpaper:-}" ] || { say "lock screen: no wallpaper on the wall, skipping"; return 1; }
    # --scaling fill is a crop, not a stretch, so the wallpaper is cropped to the
    # recording's shape the way swaylock crops it to the output's.
    magick "$wallpaper" -resize "${width}x${height}^" -gravity center -extent "${width}x${height}" \
        -fill "#${inside}" -stroke "#${ring}" -strokewidth "${thickness:-10}" \
        -draw "circle $((width / 2)),$((height / 2)) $((width / 2 + ${radius:-120})),$((height / 2))" \
        "$png" || { say "lock screen: ImageMagick could not draw the still"; return 1; }
    return 0
}

# gifsicle joins the two files: the still keeps its own palette, which is what
# gifski produced for it, and one -O3 pass merges the identical frames into a
# single held one.
append_lock_preview() {
    local gif="$1" still still_width encoder flags
    [ -f "$state/lock-preview.png" ] || return 1
    [ -n "$capture" ] || return 1
    encoder=$(video_encoder) || return 1
    case "$encoder" in
        libx264|libx265) flags=(-crf 16 -preset veryfast) ;;
        *) flags=(-q:v 2) ;;
    esac
    still_width=$(magick identify -format '%w' "${gif}[0]" 2>/dev/null)
    case "$still_width" in ''|*[!0-9]*) return 1 ;; esac
    ffmpeg -nostdin -loglevel error -y -loop 1 -framerate 20 -t "$lock_hold" \
        -i "$state/lock-preview.png" -vf "scale=${still_width}:-2" \
        -c:v "$encoder" "${flags[@]}" -pix_fmt yuv420p -an "$state/lock.mp4" \
        || return 1
    still=$("$capture" gif-from "$state/lock.mp4" ${gif_args[@]+"${gif_args[@]}"} 2>/dev/null | tail -n 1)
    [ -n "${still:-}" ] && [ -s "$still" ] || return 1
    gifsicle -O3 --careful "$gif" "$still" -o "$state/lock-joined.gif" || return 1
    mv "$state/lock-joined.gif" "$gif"
    rm -f "$still"
    return 0
}

# ====== Encoding ======

# openSUSE ships an ffmpeg without libx264, so the scaling pass cannot name one
# encoder and hope: it asks for the first the build has.  mpeg4 at q2 is the
# safe floor, and the 256-colour palette the GIF gets afterwards hides what
# little it costs.
video_encoder() {
    local encoders enc
    encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null) || encoders=""
    for enc in libx264 libx265 mpeg4; do
        # No pipe here: `grep -q' closes it on the first match, ffmpeg dies of
        # SIGPIPE, and pipefail reads the whole pipeline as a failure.
        case "$encoders" in
            *" $enc "*) printf '%s' "$enc"; return 0 ;;
        esac
    done
    return 1
}

encode() {
    local source="$1" clip_duration gif target source_width=0 encoder flags
    need ffmpeg
    need ffprobe
    [ -f "$source" ] || die "$source does not exist"
    clip_duration=$(ffprobe -v error -select_streams v:0 \
        -show_entries format=duration -of default=nw=1:nk=1 "$source" 2>/dev/null | head -n 1)
    case "$clip_duration" in
        ''|0|0.0*|*[!0-9.]*) die "the recording has no video in it: $source" ;;
    esac
    say "recording: ${clip_duration}s"

    if [ "$width" -gt 0 ]; then
        source_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
            -of default=nw=1:nk=1 "$source" 2>/dev/null | head -n 1)
        case "$source_width" in ''|*[!0-9]*) source_width=0 ;; esac
    fi
    # Lanczos once, before the GIF encoder: a GIF has no scaler of its own and a
    # 2256-pixel-wide one is a file nobody opens.  A clip already narrower than
    # the target is left alone rather than enlarged, which would only blur it.
    if [ "$width" -gt 0 ] && [ "$source_width" -gt "$width" ]; then
        encoder=$(video_encoder) || die "ffmpeg has no video encoder to scale with"
        case "$encoder" in
            libx264|libx265) flags=(-crf 16 -preset veryfast) ;;
            *) flags=(-q:v 2) ;;
        esac
        ffmpeg -nostdin -loglevel error -y -i "$source" \
            -vf "scale=$width:-2:flags=lanczos" \
            -c:v "$encoder" "${flags[@]}" -pix_fmt yuv420p -an \
            "$state/scaled.mp4" || die "ffmpeg could not scale $source"
        source="$state/scaled.mp4"
    fi

    say "encoding: heks-capture gif-from"
    gif=$("$capture" gif-from "$source" ${gif_args[@]+"${gif_args[@]}"} 2>/dev/null) \
        || die "heks-capture could not encode a GIF"
    gif=$(printf '%s\n' "$gif" | tail -n 1)
    [ -s "$gif" ] || die "the GIF came out empty: gif-from said '$gif'"

    # gif-from names its file after the second, and the lock-screen still is a
    # second call: the main file moves into the work directory first, so a still
    # that lands on the same name cannot take it down with it.
    if [ "$with_lock" = 1 ]; then
        cp -f "$gif" "$state/main.gif" || die "cannot copy the GIF into $state"
        gif="$state/main.gif"
    fi

    # Lossless: -O3 merges frames and rewrites the table without touching a
    # pixel, so the high preset stays the high preset.
    if command -v gifsicle >/dev/null 2>&1; then
        gifsicle -O3 --careful "$gif" -o "$state/optimised.gif" \
            && mv "$state/optimised.gif" "$gif"
    fi

    if [ "$with_lock" = 1 ] && [ -f "$state/lock-preview.png" ]; then
        say "lock screen: appending the still"
        append_lock_preview "$gif" || say "warning: could not append the lock-screen still"
    fi

    mkdir -p "$(dirname "$output")" || die "cannot create $(dirname "$output")"
    # CDPATH makes a relative `cd' echo where it went, which lands in the
    # answer; an empty one for the subshell keeps the path one line.
    target="$(CDPATH='' cd -- "$(dirname "$output")" && pwd)/$(basename "$output")"
    [ "$gif" = "$target" ] || mv -f "$gif" "$target"

    if [ "$keep" = 1 ] && [ -f "$state/clip.path" ]; then
        cp -f "$(cat "$state/clip.path")" "${target%.gif}-raw.mp4" \
            || say "warning: could not keep the recording"
    fi
    say "GIF: $target ($(du -h "$target" | cut -f1))"
    printf '%s\n' "$target"
}

# ====== The tour ======

run_tour() {
    local index=0 name
    sleep "$hold"
    for name in "${tour[@]}"; do
        index=$((index + 1))
        say "switching: $name"
        switched=1
        switch_to "$name" || die "the switch to $name failed: see ${TMPDIR:-/tmp}/heks-theme.log"
        sleep "$hold"
        # The scenes land between switches, so a palette change is seen landing
        # on the launcher's icons and on heks-toon's cards rather than on a
        # desktop nobody is looking at.
        case "$index" in
            1) [ "$with_launcher" = 1 ] && scene_launcher ;;
            2) [ "$with_toon" = 1 ] && scene_toon palettes ;;
        esac
    done
    [ "$with_picker" = 1 ] && scene_picker
    [ "$with_toon" = 1 ] && scene_toon walls
    [ "$with_launchpad" = 1 ] && scene_launchpad
    return 0
}

# The small preset is the capture program's own: 640 px at 12 fps with
# gifsicle's lossy pass, for a file a page loads inline.  The default is the
# high preset, which is what the desktop uses for its own captures.
if [ "$small" = 1 ]; then
    gif_args=(--low)
fi

if [ -n "$from" ]; then
    # A kept clip gets the same still a live run appends, so re-encoding it
    # gives back the GIF the run produced rather than a shorter one.
    if [ "$with_lock" = 1 ]; then
        render_lock_preview "$from" || with_lock=0
    fi
    encode "$from"
    exit 0
fi

say "tour: $original$([ "${#tour[@]}" -gt 0 ] && printf ' -> %s' "${tour[@]}") -> $original (restored)"
say "scenes: launcher=$([ "$with_launcher" = 1 ] && printf yes || printf no), toon=$([ "$with_toon" = 1 ] && printf yes || printf no), picker=$([ "$with_picker" = 1 ] && printf yes || printf no), launchpad=$([ "$with_launchpad" = 1 ] && printf yes || printf no)"
say "width: $width, hold: ${hold}s, scene: ${scene_hold}s"
if [ "$dry_run" = 1 ]; then
    say "dry run: nothing recorded"
    exit 0
fi

dock_show_setup

if [ "$rehearse" = 1 ]; then
    say "rehearsal: running the tour without recording"
    run_tour
    say "restoring palette: $original"
    switch_to "$original" || say "warning: could not restore $original"
    switched=0
    say "rehearsal: nothing recorded"
    exit 0
fi

start_recorder
run_tour
stop_recorder
# Drawn before the palette goes back: the still is the lock screen the tour's
# last switch produced, not the one the session started on.
if [ "$with_lock" = 1 ]; then
    render_lock_preview "$(cat "$state/clip.path")" || with_lock=0
fi
say "restoring palette: $original"
switch_to "$original" || say "warning: could not restore $original"
switched=0

encode "$(cat "$state/clip.path")"
