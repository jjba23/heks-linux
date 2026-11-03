;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Everything this desktop does with the screen's pixels: a screenshot of a
;; region, an output or a window; a GIF of a region or an output, at full size
;; or cut down small enough to paste into a chat; and a video recording of
;; either.
;;
;; One generated program, @file{~/.local/bin/heks-capture}, and one binding per
;; verb.  A second program per feature is how the old region-GIF recorder ended
;; up with its own copy of the geometry parsing, its own notification strings
;; and its own idea of where files go.
;;
;; Three decisions are worth stating, because they are what make the result
;; fast and trustworthy rather than merely working:
;;
;; - The recorder is @code{wl-screenrec} when it is installed.  It copies
;;   dma-buf frames and lets the GPU convert and encode them, so a recording
;;   costs a couple of percent of a core instead of the five hundred percent
;;   @code{wf-recorder}'s software path measured in its own benchmarks.  When it
;;   is absent the script falls back to @code{wf-recorder} with the flags this
;;   repository has always used, rather than failing.
;;
;; - A window is captured by the compositor, not by @code{grim}.  Neither
;;   @code{wlr-screencopy} nor @code{ext-image-copy-capture} gives a client a
;;   toplevel source yet, so @code{niri msg action screenshot-window} is the one
;;   correct answer, and the script finds the file niri wrote by timestamp
;;   rather than guessing a name.
;;
;; - GIFs are encoded by @code{gifski} when it is installed, because its
;;   cross-frame palettes and temporal dithering are the difference between a
;;   demo and a smear; the ffmpeg two-pass palette is the fallback, not the
;;   plan.  The low preset additionally cuts the width and frame rate and runs
;;   @code{gifsicle --lossy}, which is what makes a GIF small enough for a chat
;;   window.
;;
;; The recordings are toggles, keyed by what is being recorded (a high region
;; GIF and a low region GIF are two recordings, not one), so pressing the key
;; twice stops exactly the recording that key started.

;;; Code:

(define-module (heks-linux capture)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-13)
  #:export (capture-script
            install-capture-config
            capture-script-filename
            capture-script-dir
            capture-screenshots-dir
            capture-videos-dir
            capture-gifs-dir
            capture-video-fps
            capture-video-crf
            capture-video-audio?
            capture-gif-fps
            capture-gif-width
            capture-gif-quality
            capture-gif-colors
            capture-gif-low-fps
            capture-gif-low-width
            capture-gif-low-quality
            capture-gif-low-colors
            capture-gif-lossy
            capture-annotate-tool
            capture-gif-filter
            capture-video-flags
            capture-expand))

(define s
  (scriba-auto-logger))

;; ===========================================
;; Where the pictures go
;; ===========================================

(define (capture-home)
  "Return the home directory the script is rendered for."
  (or (getenv "HOME") "/tmp"))

(define (capture-expand path)
  "Return @var{path} with a leading @file{~/} expanded to the home directory.

The script is started from a compositor binding, where a quoted tilde is a
literal character and not a directory, so every path it is handed is absolute
by the time it is written."
  (if (and (string? path) (string-prefix? "~/" path))
    (format #f "~a/~a" (capture-home) (substring path 2))
    path))

;; Screenshots land where niri writes its own, which is the setting the dock's
;; Screenshots stack reads as well: one directory, or the stack shows an empty
;; folder while every picture goes somewhere else.
(define capture-screenshots-dir
  (make-parameter (heks-linux-screenshots-dir)))

;; GIFs go beside the screenshots for the same reason: they are pictures, and
;; they belong in the folder that already collects them.
(define capture-gifs-dir
  (make-parameter (heks-linux-screenshots-dir)))

;; Recordings are video, and video has a folder.
(define capture-videos-dir
  (make-parameter (format #f "~a/Videos" (capture-home))))

(define capture-script-filename
  (make-parameter "heks-capture"))

(define capture-script-dir
  (make-parameter (format #f "~a/.local/bin" (capture-home))))

;; ===========================================
;; How good the result is
;; ===========================================

;; crf 18 is visually lossless for screen content at these resolutions and is
;; still a fraction of the bitrate of the default; the preset is the fast one
;; because a recording that stutters is worse than one that is 5% larger.
(define capture-video-crf
  (make-parameter 18))

(define capture-video-fps
  (make-parameter 60))

;; Desktop audio off by default: most recordings are of something already
;; talking, and an accidental microphone recording is the one mistake a
;; capture tool must not make on its own.
(define capture-video-audio?
  (make-parameter #f))

(define capture-gif-fps
  (make-parameter 20))

;; 0 means the recorded width: a GIF of a region is already small, and scaling
;; it up would only make the file bigger.
(define capture-gif-width
  (make-parameter 0))

(define capture-gif-quality
  (make-parameter 90))

(define capture-gif-colors
  (make-parameter 256))

(define capture-gif-low-fps
  (make-parameter 12))

(define capture-gif-low-width
  (make-parameter 640))

(define capture-gif-low-quality
  (make-parameter 70))

(define capture-gif-low-colors
  (make-parameter 128))

;; gifsicle's lossy knob, for the small preset only: 80 is the usual sweet spot
;; where the file halves and the text stays readable.
(define capture-gif-lossy
  (make-parameter 80))

;; Annotation is optional: satty is not packaged everywhere, and a screenshot
;; that silently fails to appear because an editor is missing is worse than a
;; plain one.
(define capture-annotate-tool
  (make-parameter "satty"))

;; ===========================================
;; The pure parts
;; ===========================================

(define* (capture-gif-filter #:key (width (capture-gif-width))
                             (fps (capture-gif-fps)))
  "Return the ffmpeg filter that turns a recording into GIF-sized frames.

Width 0 keeps the recorded width; anything else scales with lanczos, which is
the only scaler worth using for text."
  (if (and (number? width) (> width 0))
    (format #f "fps=~a,scale=~a:-1:flags=lanczos" fps width)
    (format #f "fps=~a" fps)))

(define* (capture-video-flags #:key (recorder 'wf-recorder)
                              (codec 'h264)
                              (crf (capture-video-crf)))
  "Return the encoder arguments @var{recorder} needs besides its file and area.

@code{wl-screenrec} chooses the encoder through @code{--codec} and the GPU does
the work; @code{wf-recorder} is an ffmpeg front end, so it takes the encoder and
its parameters one flag at a time.  The @code{profile} and @code{level} pair is
load-bearing: the system's libopenh264 decodes the result, and it rejects the
high profiles ffmpeg would otherwise pick."
  (case recorder
    [(wl-screenrec)
     (list "--codec" (if (eq? codec 'hevc) "hevc" "avc"))]
    [(wf-recorder)
     (list "-c" (if (eq? codec 'hevc) "libx265" "libx264")
           "-x" "yuv420p"
           "-p" (format #f "crf=~a" crf)
           "-p" "preset=veryfast"
           "-p" "profile=main"
           "-p" "level=4.2")]
    [else
      (error "capture-video-flags: unknown recorder" recorder)]))

;; ===========================================
;; The program
;; ===========================================

(define (script-text . lines)
  "Return @var{lines} as one text, one per line, ending in a newline."
  (string-append (string-join lines "\n") "\n"))

(define (capture-header)
  (format #f
          (script-text
           "#!/usr/bin/env bash"
           "# ====== Heks-Linux capture ======"
           "#"
           "# auto-generated file, DO NOT EDIT!"
           "#"
           "# shot   region|output|window   [--annotate] [--clipboard] [--geometry G]"
           "# gif    region|output          [--low] [--seconds N] [--geometry G]"
           "# video  region|output          [--hevc] [--seconds N] [--geometry G]"
           "# gif-from FILE                 [--low]"
           "# status | stop | help"
           "#"
           "# Recordings are toggles: the same command starts one and stops it."
           ""
           "set -uo pipefail"
           ""
           "SHOTS=\"~a\""
           "VIDEOS=\"~a\""
           "GIFS=\"~a\""
           "STATE=\"${XDG_RUNTIME_DIR:-/tmp}/heks-capture\""
           "ANNOTATE_TOOL=\"~a\"")
          (capture-expand (capture-screenshots-dir))
          (capture-expand (capture-videos-dir))
          (capture-expand (capture-gifs-dir))
          (capture-annotate-tool)))

(define (capture-helpers)
  (script-text
   ""
   "notify() {"
   "    local urgency=\"$1\" title=\"$2\" body=\"$3\""
   "    if command -v fyi >/dev/null 2>&1; then"
   "        fyi -u \"$urgency\" -a \"Capture\" \"$title\" \"$body\" >/dev/null 2>&1 || true"
   "    elif command -v notify-send >/dev/null 2>&1; then"
   "        notify-send -u \"$urgency\" \"$title\" \"$body\" >/dev/null 2>&1 || true"
   "    else"
   "        printf '%s: %s\\n' \"$title\" \"$body\" >&2"
   "    fi"
   "}"
   ""
   "die() {"
   "    notify critical \"Capture failed\" \"$*\""
   "    printf 'heks-capture: %s\\n' \"$*\" >&2"
   "    exit 1"
   "}"
   ""
   "need() {"
   "    command -v \"$1\" >/dev/null 2>&1 || die \"$1 is not installed\""
   "}"
   ""
   "stamp() { printf '%(%Y-%m-%d_%H-%M-%S)T' -1; }"
   ""
   "ensure_dirs() {"
   "    mkdir -p \"$SHOTS\" \"$GIFS\" \"$VIDEOS\" \"$STATE\" || die \"cannot create a capture directory\""
   "}"
   ""
   "clip_file() {"
   "    command -v wl-copy >/dev/null 2>&1 || return 0"
   "    wl-copy --type \"$2\" < \"$1\" >/dev/null 2>&1 || true"
   "}"
   ""
   "clip_text() {"
   "    command -v wl-copy >/dev/null 2>&1 || return 0"
   "    printf '%s' \"$1\" | wl-copy >/dev/null 2>&1 || true"
   "}"
   ""
   "mode_name() {"
   "    local name=\"${1##*/}\""
   "    printf '%s' \"${name%.pid}\""
   "}"
   ""
   "focused_output() {"
   "    local json=\"\" name=\"\""
   "    local fields=()"
   "    command -v niri >/dev/null 2>&1 || die \"no output to capture: niri is not running\""
   "    json=\"$(niri msg --json focused-output 2>/dev/null)\""
   "    IFS='\"' read -r -a fields <<< \"$json\""
   "    name=\"${fields[3]:-}\""
   "    if [ -z \"$name\" ]; then"
   "        json=\"$(niri msg --json outputs 2>/dev/null)\""
   "        IFS='\"' read -r -a fields <<< \"$json\""
   "        name=\"${fields[1]:-}\""
   "    fi"
   "    [ -n \"$name\" ] || die \"no output to capture: niri named no output\""
   "    printf '%s\\n' \"$name\""
   "}"
   ""
   "# slurp in dimensions mode: what a region selector returns for a recording,"
   "# where the position matters as much as the size."
   "select_geometry() {"
   "    GEOMETRY=\"\""
   "    if [ -n \"${CAPTURE_GEOMETRY:-}\" ]; then"
   "        GEOMETRY=\"$CAPTURE_GEOMETRY\""
   "        return 0"
   "    fi"
   "    need slurp"
   "    GEOMETRY=\"$(slurp -d 2>/dev/null)\" || GEOMETRY=\"\""
   "    return 0"
   "}"
   ""
   "# H.264 has no odd pixels: a 101-pixel-wide region makes the encoder fail"
   "# with a message about alignment rather than about the region."
   "even_geometry() {"
   "    local geometry=\"$1\" position=\"0,0\" size=\"\" width=0 height=0"
   "    if [[ \"$geometry\" == *\" \"* ]]; then"
   "        position=\"${geometry%% *}\""
   "        size=\"${geometry##* }\""
   "    else"
   "        size=\"$geometry\""
   "    fi"
   "    width=\"${size%x*}\""
   "    height=\"${size#*x}\""
   "    printf '%s %dx%d\\n' \"$position\" \"$((width - width % 2))\" \"$((height - height % 2))\""
   "}"))

(define (capture-shot-commands)
  (script-text
   "annotate_file() {"
   "    [ \"$ANNOTATE\" = 1 ] || return 0"
   "    if command -v \"$ANNOTATE_TOOL\" >/dev/null 2>&1; then"
   "        \"$ANNOTATE_TOOL\" --filename \"$1\" --output-filename \"$1\" --copy-command wl-copy \\"
   "            >/dev/null 2>&1 || notify low \"Capture\" \"annotation failed; kept the plain screenshot\""
   "    else"
   "        notify low \"Capture\" \"annotation needs $ANNOTATE_TOOL; kept the plain screenshot\""
   "    fi"
   "}"
   ""
   "cmd_shot() {"
   "    local area=\"${1:-region}\" annotate=0 clipboard=1 save=1 geometry=\"\" file=\"\" output=\"\" marker=\"\" newest=\"\" candidate=\"\" i=0"
   "    [ $# -gt 0 ] && shift"
   "    while [ $# -gt 0 ]; do"
   "        case \"$1\" in"
   "            --annotate) annotate=1 ;;"
   "            --clipboard) save=0 ;;"
   "            --no-clipboard) clipboard=0 ;;"
   "            --geometry) shift; geometry=\"${1:-}\" ;;"
   "            *) die \"shot: unknown option $1\" ;;"
   "        esac"
   "        shift"
   "    done"
   "    ANNOTATE=\"$annotate\""
   "    ensure_dirs"
   "    case \"$area\" in"
   "        region)"
   "            need grim"
   "            if [ -n \"$geometry\" ]; then GEOMETRY=\"$geometry\"; else select_geometry; fi"
   "            [ -n \"$GEOMETRY\" ] || { notify low \"Capture\" \"nothing selected\"; exit 0; }"
   "            if [ \"$save\" = 0 ]; then"
   "                grim -g \"$GEOMETRY\" - | wl-copy --type image/png \\"
   "                    || die \"grim could not capture $GEOMETRY\""
   "                notify normal \"Screenshot copied\" \"the region is on the clipboard\""
   "                return 0"
   "            fi"
   "            file=\"$SHOTS/screen-$(stamp)-$$.png\""
   "            grim -g \"$GEOMETRY\" \"$file\" || die \"grim could not capture $GEOMETRY\""
   "            annotate_file \"$file\""
   "            [ \"$clipboard\" = 1 ] && clip_file \"$file\" image/png"
   "            notify normal \"Screenshot saved\" \"$file\""
   "            printf '%s\\n' \"$file\""
   "            ;;"
   "        output)"
   "            need grim"
   "            output=\"$(focused_output)\""
   "            if [ \"$save\" = 0 ]; then"
   "                grim -o \"$output\" - | wl-copy --type image/png \\"
   "                    || die \"grim could not capture $output\""
   "                notify normal \"Screenshot copied\" \"the output is on the clipboard\""
   "                return 0"
   "            fi"
   "            file=\"$SHOTS/screen-$(stamp)-$$.png\""
   "            grim -o \"$output\" \"$file\" || die \"grim could not capture $output\""
   "            annotate_file \"$file\""
   "            [ \"$clipboard\" = 1 ] && clip_file \"$file\" image/png"
   "            notify normal \"Screenshot saved\" \"$file\""
   "            printf '%s\\n' \"$file\""
   "            ;;"
   "        window)"
   "            need niri"
   "            marker=\"$STATE/window-shot.marker\""
   "            : > \"$marker\""
   "            niri msg action screenshot-window >/dev/null 2>&1 \\"
   "                || die \"niri could not capture the focused window\""
   "            # niri writes the file itself, at the path its own"
   "            # configuration names, and tells nobody which one: the newest"
   "            # picture newer than the marker is the one this action wrote."
   "            newest=\"\""
   "            while [ \"$i\" -lt 30 ]; do"
   "                for candidate in \"$SHOTS\"/*.png; do"
   "                    [ -e \"$candidate\" ] || continue"
   "                    [ \"$candidate\" -nt \"$marker\" ] || continue"
   "                    if [ -z \"$newest\" ] || [ \"$candidate\" -nt \"$newest\" ]; then"
   "                        newest=\"$candidate\""
   "                    fi"
   "                done"
   "                [ -n \"$newest\" ] && break"
   "                sleep 0.1"
   "                i=$((i + 1))"
   "            done"
   "            [ -n \"$newest\" ] || die \"niri wrote no screenshot to $SHOTS: check screenshot-path in its config\""
   "            annotate_file \"$newest\""
   "            [ \"$clipboard\" = 1 ] && clip_file \"$newest\" image/png"
   "            notify normal \"Window screenshot saved\" \"$newest\""
   "            printf '%s\\n' \"$newest\""
   "            ;;"
   "        *)"
   "            die \"shot: '$area' is not a region, an output or a window\""
   "            ;;"
   "    esac"
   "}"))

(define (capture-recorder)
  (format #f
          (script-text
           ""
           "record_start() {"
           "    local mode=\"$1\" file=\"$2\" geometry=\"${3:-}\" args=() output=\"\" gpu=\"\""
           "    rm -f \"$file\""
           "    # CAPTURE_RECORDER forces a backend: a machine whose GPU encoder is"
           "    # broken should not have to uninstall it, and the tests say which path"
           "    # they mean."
           "    case \"${CAPTURE_RECORDER:-auto}\" in"
           "        wl-screenrec) gpu=1 ;;"
           "        wf-recorder) gpu=\"\" ;;"
           "        *) if command -v wl-screenrec >/dev/null 2>&1; then gpu=1; fi ;;"
           "    esac"
           "    if [ -n \"$gpu\" ]; then"
           "        args=(-f \"$file\" ~a)"
           "        if [ -n \"$geometry\" ]; then"
           "            args+=(-g \"$(even_geometry \"$geometry\")\")"
           "        else"
           "            output=\"$(focused_output)\""
           "            args+=(-o \"$output\")"
           "        fi"
           "        ~a"
           "        wl-screenrec \"${args[@]}\" >>\"$STATE/$mode.log\" 2>&1 &"
           "    else"
           "        need wf-recorder"
           "        args=(-f \"$file\" ~a)"
           "        if [ -n \"$geometry\" ]; then"
           "            args+=(-g \"$(even_geometry \"$geometry\")\")"
           "        else"
           "            args+=(-o \"$(focused_output)\")"
           "        fi"
           "        ~a"
           "        wf-recorder \"${args[@]}\" >>\"$STATE/$mode.log\" 2>&1 &"
           "    fi"
           "    printf '%s' \"$!\" > \"$STATE/$mode.pid\""
           "    printf '%s' \"$file\" > \"$STATE/$mode.file\""
           "    sleep 0.4"
           "    kill -0 \"$!\" 2>/dev/null \\"
           "        || { rm -f \"$STATE/$mode.pid\"; die \"the recorder exited at once: see $STATE/$mode.log\"; }"
           "}"
           ""
           "# SIGINT is how every ffmpeg front end finishes a file properly: the moov"
           "# atom is written on the way out, and a SIGTERM leaves an unplayable"
           "# recording."
           "stop_recorder() {"
           "    local mode=\"$1\" pid=\"\" i=0"
           "    [ -f \"$STATE/$mode.pid\" ] || return 1"
           "    pid=\"$(cat \"$STATE/$mode.pid\")\""
           "    rm -f \"$STATE/$mode.pid\""
           "    kill -INT \"$pid\" 2>/dev/null || true"
           "    # Two seconds for the graceful path, which is what a recorder needs to"
           "    # write the trailer; TERM is the fallback for one that is wedged."
           "    while kill -0 \"$pid\" 2>/dev/null && [ \"$i\" -lt 20 ]; do"
           "        sleep 0.1"
           "        i=$((i + 1))"
           "    done"
           "    if kill -0 \"$pid\" 2>/dev/null; then"
           "        kill -TERM \"$pid\" 2>/dev/null || true"
           "        i=0"
           "        while kill -0 \"$pid\" 2>/dev/null && [ \"$i\" -lt 20 ]; do"
           "            sleep 0.1"
           "            i=$((i + 1))"
           "        done"
           "    fi"
           "    return 0"
           "}"
           ""
           "recording_file() {"
           "    cat \"$STATE/$1.file\" 2>/dev/null || true"
           "}")
          (string-join (capture-video-flags #:recorder 'wl-screenrec) " ")
          (if (capture-video-audio?) "args+=(--audio)" "")
          (string-join (capture-video-flags #:recorder 'wf-recorder) " ")
          (if (capture-video-audio?) "args+=(--audio)" "")))

(define (capture-video-command)
  (script-text
   ""
   "cmd_video() {"
   "    local area=\"${1:-output}\" seconds=0 geometry=\"\" file=\"\" mode=\"\""
   "    [ $# -gt 0 ] && shift"
   "    while [ $# -gt 0 ]; do"
   "        case \"$1\" in"
   "            --seconds) shift; seconds=\"${1:-0}\" ;;"
   "            --geometry) shift; geometry=\"${1:-}\" ;;"
   "            --hevc) HEVC=1 ;;"
   "            *) die \"video: unknown option $1\" ;;"
   "        esac"
   "        shift"
   "    done"
   "    ensure_dirs"
   "    mode=\"video-$area\""
   "    if stop_recorder \"$mode\"; then"
   "        file=\"$(recording_file \"$mode\")\""
   "        rm -f \"$STATE/$mode.file\""
   "        [ -n \"$file\" ] && [ -s \"$file\" ] || die \"the recording came out empty\""
   "        clip_text \"$file\""
   "        notify normal \"Recording saved\" \"$file (path copied to the clipboard)\""
   "        printf '%s\\n' \"$file\""
   "        return 0"
   "    fi"
   "    case \"$area\" in"
   "        region)"
   "            if [ -n \"$geometry\" ]; then GEOMETRY=\"$geometry\"; else select_geometry; fi"
   "            [ -n \"$GEOMETRY\" ] || { notify low \"Capture\" \"nothing selected\"; exit 0; }"
   "            geometry=\"$GEOMETRY\""
   "            ;;"
   "        output)"
   "            geometry=\"\""
   "            ;;"
   "        *)"
   "            die \"video: '$area' cannot be recorded: a window needs a portal recorder such as OBS\""
   "            ;;"
   "    esac"
   "    file=\"$VIDEOS/rec-$(stamp).mp4\""
   "    record_start \"$mode\" \"$file\" \"$geometry\""
   "    if [ \"$seconds\" -gt 0 ] 2>/dev/null; then"
   "        ( sleep \"$seconds\"; \"$0\" video \"$area\" ) >/dev/null 2>&1 &"
   "    fi"
   "    notify normal \"Recording started\" \"press the same key again to stop\""
   "}"))

(define (capture-gif-command)
  (format #f
          (script-text
           ""
           "GIF_FILTER_HIGH=\"~a\""
           "GIF_FILTER_LOW=\"~a\""
           "GIF_FPS_HIGH=~a"
           "GIF_FPS_LOW=~a"
           "GIF_QUALITY_HIGH=~a"
           "GIF_QUALITY_LOW=~a"
           "GIF_COLORS_HIGH=~a"
           "GIF_COLORS_LOW=~a"
           "GIF_LOSSY=~a"
           ""
           "encode_gif() {"
           "    local source=\"$1\" target=\"$2\" preset=\"${3:-high}\""
           "    local filter=\"\" fps=0 quality=0 colors=0 lossy=0 palette=\"\""
           "    case \"$preset\" in"
           "        low)"
           "            filter=\"$GIF_FILTER_LOW\"; fps=\"$GIF_FPS_LOW\"; quality=\"$GIF_QUALITY_LOW\""
           "            colors=\"$GIF_COLORS_LOW\"; lossy=\"$GIF_LOSSY\""
           "            ;;"
           "        high)"
           "            filter=\"$GIF_FILTER_HIGH\"; fps=\"$GIF_FPS_HIGH\"; quality=\"$GIF_QUALITY_HIGH\""
           "            colors=\"$GIF_COLORS_HIGH\"; lossy=0"
           "            ;;"
           "        *)"
           "            die \"gif: '$preset' is neither high nor low\""
           "            ;;"
           "    esac"
           "    [ -s \"$source\" ] || die \"the recording came out empty\""
           "    need ffmpeg"
           "    rm -f \"$target\""
           "    if command -v gifski >/dev/null 2>&1; then"
           "        # gifski reads y4m and does its own cross-frame palette and"
           "        # temporal dithering, which an ffmpeg palette cannot do."
           "        ffmpeg -nostdin -loglevel error -i \"$source\" -vf \"$filter\" -f yuv4mpegpipe - \\"
           "            | gifski --fps \"$fps\" --quality \"$quality\" -o \"$target\" - \\"
           "            || die \"gifski could not encode $source\""
           "    else"
           "        palette=\"$STATE/palette-$preset.png\""
           "        ffmpeg -nostdin -loglevel error -y -i \"$source\" \\"
           "            -vf \"$filter,palettegen=max_colors=$colors:stats_mode=diff\" \"$palette\" \\"
           "            || die \"ffmpeg could not build a palette for $source\""
           "        ffmpeg -nostdin -loglevel error -y -i \"$source\" -i \"$palette\" \\"
           "            -lavfi \"$filter[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle\" \"$target\" \\"
           "            || die \"ffmpeg could not encode $target\""
           "    fi"
           "    if [ \"$lossy\" -gt 0 ] && command -v gifsicle >/dev/null 2>&1; then"
           "        gifsicle -O3 --careful --lossy=\"$lossy\" \"$target\" -o \"$target.opt\" \\"
           "            && mv \"$target.opt\" \"$target\""
           "    fi"
           "    [ -s \"$target\" ] || die \"the GIF came out empty\""
           "}"
           ""
           "cmd_gif() {"
           "    local area=\"${1:-region}\" preset=high seconds=0 geometry=\"\" file=\"\" target=\"\" mode=\"\""
           "    [ $# -gt 0 ] && shift"
           "    while [ $# -gt 0 ]; do"
           "        case \"$1\" in"
           "            --low) preset=low ;;"
           "            --high) preset=high ;;"
           "            --seconds) shift; seconds=\"${1:-0}\" ;;"
           "            --geometry) shift; geometry=\"${1:-}\" ;;"
           "            *) die \"gif: unknown option $1\" ;;"
           "        esac"
           "        shift"
           "    done"
           "    ensure_dirs"
           "    mode=\"gif-$preset-$area\""
           "    if stop_recorder \"$mode\"; then"
           "        file=\"$(recording_file \"$mode\")\""
           "        rm -f \"$STATE/$mode.file\""
           "        target=\"$GIFS/gif-$(stamp).gif\""
           "        encode_gif \"$file\" \"$target\" \"$preset\""
           "        rm -f \"$file\""
           "        clip_file \"$target\" image/gif"
           "        notify normal \"GIF saved\" \"$target (copied to the clipboard)\""
           "        printf '%s\\n' \"$target\""
           "        return 0"
           "    fi"
           "    case \"$area\" in"
           "        region)"
           "            if [ -n \"$geometry\" ]; then GEOMETRY=\"$geometry\"; else select_geometry; fi"
           "            [ -n \"$GEOMETRY\" ] || { notify low \"Capture\" \"nothing selected\"; exit 0; }"
           "            geometry=\"$GEOMETRY\""
           "            ;;"
           "        output)"
           "            geometry=\"\""
           "            ;;"
           "        *)"
           "            die \"gif: '$area' is not a region or an output\""
           "            ;;"
           "    esac"
           "    file=\"$STATE/gif-$preset-$area.mp4\""
           "    record_start \"$mode\" \"$file\" \"$geometry\""
           "    if [ \"$seconds\" -gt 0 ] 2>/dev/null; then"
           "        ( sleep \"$seconds\"; \"$0\" gif \"$area\" \"--$preset\" ) >/dev/null 2>&1 &"
           "    fi"
           "    notify normal \"GIF recording started\" \"press the same key again to convert it\""
           "}"
           ""
           "cmd_gif_from() {"
           "    local source=\"${1:-}\" preset=\"high\" target=\"\""
           "    [ -n \"$source\" ] || die \"gif-from: name a video file\""
           "    shift"
           "    while [ $# -gt 0 ]; do"
           "        case \"$1\" in"
           "            --low) preset=low ;;"
           "            --high) preset=high ;;"
           "            *) die \"gif-from: unknown option $1\" ;;"
           "        esac"
           "        shift"
           "    done"
           "    [ -f \"$source\" ] || die \"gif-from: $source does not exist\""
           "    ensure_dirs"
           "    target=\"$GIFS/gif-$(stamp).gif\""
           "    encode_gif \"$source\" \"$target\" \"$preset\""
           "    clip_file \"$target\" image/gif"
           "    notify normal \"GIF saved\" \"$target (copied to the clipboard)\""
           "    printf '%s\\n' \"$target\""
           "}")
          (capture-gif-filter #:fps (capture-gif-fps) #:width (capture-gif-width))
          (capture-gif-filter #:fps (capture-gif-low-fps) #:width (capture-gif-low-width))
          (capture-gif-fps)
          (capture-gif-low-fps)
          (capture-gif-quality)
          (capture-gif-low-quality)
          (capture-gif-colors)
          (capture-gif-low-colors)
          (capture-gif-lossy)))

(define (capture-dispatch)
  (script-text
   ""
   "cmd_status() {"
   "    local found=0 file=\"\""
   "    for file in \"$STATE\"/*.pid; do"
   "        [ -e \"$file\" ] || continue"
   "        printf '%s\\trunning\\n' \"$(basename \"$file\" .pid)\""
   "        found=1"
   "    done"
   "    [ \"$found\" = 1 ] || echo \"nothing is recording\""
   "}"
   ""
   "cmd_stop() {"
   "    local file=\"\" mode=\"\" pid=\"\""
   "    for file in \"$STATE\"/*.pid; do"
   "        [ -e \"$file\" ] || continue"
   "        mode=\"$(basename \"$file\" .pid)\""
   "        pid=\"$(cat \"$file\")\""
   "        rm -f \"$file\""
   "        kill -INT \"$pid\" 2>/dev/null || true"
   "        printf 'stopped %s\\n' \"$mode\""
   "    done"
   "}"
   ""
   "usage() {"
   "    cat <<'HEKS_CAPTURE'"
   "heks-capture: pictures and recordings of this desktop"
   ""
   "  heks-capture shot region|output|window [--annotate] [--clipboard] [--geometry G]"
   "      A region, the focused output or the focused window.  Saved and copied by"
   "      default; --clipboard keeps it off the disk, --annotate opens satty."
   ""
   "  heks-capture gif region|output [--low] [--seconds N] [--geometry G]"
   "      A GIF as a toggle: the same command starts the recording and converts it."
   "      --low cuts the width, the frame rate and the palette for chat-sized files."
   ""
   "  heks-capture video region|output [--hevc] [--seconds N] [--geometry G]"
   "      A video recording as a toggle; the file's path is copied when it stops."
   ""
   "  heks-capture gif-from FILE [--low]"
   "      Convert a video that already exists into a GIF."
   ""
   "  heks-capture status | stop"
   "      What is recording now, and a way to stop all of it."
   "HEKS_CAPTURE"
   "}"
   ""
   "main() {"
   "    local kind=\"${1:-help}\""
   "    [ $# -gt 0 ] && shift"
   "    case \"$kind\" in"
   "        shot) cmd_shot \"$@\" ;;"
   "        gif) cmd_gif \"$@\" ;;"
   "        video) cmd_video \"$@\" ;;"
   "        gif-from) cmd_gif_from \"$@\" ;;"
   "        status) cmd_status ;;"
   "        stop) cmd_stop ;;"
   "        help|-h|--help) usage ;;"
   "        *) usage >&2; exit 2 ;;"
   "    esac"
   "}"
   ""
   "main \"$@\""))

(define (capture-script)
  "Return the whole @file{heks-capture} program as text."
  (string-append (capture-header)
                 (capture-helpers)
                 (capture-shot-commands)
                 (capture-recorder)
                 (capture-video-command)
                 (capture-gif-command)
                 (capture-dispatch)))

;; ===========================================
;; Installing it
;; ===========================================

(define (install-capture-config)
  "Write @file{heks-capture} to @code{capture-script-dir} with mode #o755.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/capture-settings.scm} first, so the
directories, the frame rates and the quality knobs can be changed per machine
without editing this file."
  (log-info s "Installing capture tooling")
  (load-local-overrides '(heks-linux capture) 'capture-settings)
  (ensure-directory-tree! (capture-expand (capture-screenshots-dir)))
  (ensure-directory-tree! (capture-expand (capture-gifs-dir)))
  (ensure-directory-tree! (capture-expand (capture-videos-dir)))
  (install-config-file! #:name (capture-script-filename)
                        #:dir (capture-expand (capture-script-dir))
                        #:contents (capture-script)
                        #:perms 493)
  (log-success s "Installed capture tooling"))
