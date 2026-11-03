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
   "    local urgency=\"$1\" title=\"$2\" body=\"$3\" icon=\"camera-photo-symbolic\""
   "    if [ \"$urgency\" = critical ]; then"
   "        icon=\"dialog-error-symbolic\""
   "    else"
   "        case \"$title\" in"
   "            *Recording*) icon=\"media-record-symbolic\" ;;"
   "            *GIF*) icon=\"image-x-generic-symbolic\" ;;"
   "        esac"
   "    fi"
   "    if command -v fyi >/dev/null 2>&1; then"
   "        fyi -i \"$icon\" -u \"$urgency\" -a \"Capture\" \"$title\" \"$body\" >/dev/null 2>&1 || true"
   "    elif command -v notify-send >/dev/null 2>&1; then"
   "        notify-send -i \"$icon\" -u \"$urgency\" \"$title\" \"$body\" >/dev/null 2>&1 || true"
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

   "# A non-empty file is not a recording: a SIGTERM during the trailer flush"
   "# leaves a 48-byte header that passes a size test.  ffprobe knows better."
   "recording_ok() {"
   "    local file=\"$1\" duration=\"\""
   "    [ -s \"$file\" ] || return 1"
   "    if command -v ffprobe >/dev/null 2>&1; then"
   "        duration=\"$(ffprobe -v error -select_streams v:0 \\"
   "            -show_entries format=duration -of default=nw=1:nk=1 \"$file\" 2>/dev/null \\"
   "            | head -n 1)\""
   "        # No awk: the test container ships a shell, not mawk.  Any clip at"
   "        # least a tenth of a second long has a whole or fractional part."
   "        case \"$duration\" in"
   "            ''|*[!0-9.]*) return 1 ;;"
   "        esac"
   "        [ \"${duration%%.*}\" -gt 0 ] && return 0"
   "        case \"${duration#*.}\" in"
   "            [1-9]*) return 0 ;;"
   "        esac"
   "        return 1"
   "    fi"
   "    [ \"$(wc -c < \"$file\" | tr -d ' ')\" -ge 1024 ]"
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
   "# slurp's full geometry - \"x,y WxH\", not the dimensions-only form: a"
   "# recording needs where the region is, or it records from the corner."
   "select_geometry() {"
   "    GEOMETRY=\"\""
   "    if [ -n \"${CAPTURE_GEOMETRY:-}\" ]; then"
   "        GEOMETRY=\"$CAPTURE_GEOMETRY\""
   "        return 0"
   "    fi"
   "    need slurp"
   "    GEOMETRY=\"$(slurp 2>/dev/null)\" || GEOMETRY=\"\""
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
   "    case \"$width\" in ''|*[!0-9]*) width=0 ;; esac"
   "    case \"$height\" in ''|*[!0-9]*) height=0 ;; esac"
   "    if [ \"$width\" -lt 2 ] || [ \"$height\" -lt 2 ]; then"
   "        die \"the selected region (${size:-nothing}) is too small to record\""
   "    fi"
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

           "    # even_geometry refuses a region too small to encode, but its die runs in"
           "    # a command substitution when it is called inline: the substitution would"
           "    # swallow the exit and the recorder would start on an empty geometry."
           "    if [ -n \"$geometry\" ]; then"
           "        geometry=\"$(even_geometry \"$geometry\")\" || exit 1"
           "    fi"
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
           "            args+=(-g \"$geometry\")"
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
           "            args+=(-g \"$geometry\")"
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
           "    # The number has to still belong to a recorder: a reused pid would get a"
           "    # SIGINT meant for a recording that already ended."
           "    case \"$(tr '\\0' ' ' < \"/proc/$pid/cmdline\" 2>/dev/null)\" in"
           "        *wl-screenrec*|*wf-recorder*) ;;"
           "        *) return 1 ;;"
           "    esac"
           "    kill -INT \"$pid\" 2>/dev/null || true"
           "    # SIGINT asks for a trailer, and the flush can take seconds behind a busy"
           "    # encoder.  Two seconds was short enough that the fallback SIGTERM cut the"
           "    # trailer off and left a 48-byte header."
           "    while kill -0 \"$pid\" 2>/dev/null && [ \"$i\" -lt 150 ]; do"
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
           "        return 2"
           "    fi"
           "    return 0"
           "}"
           ""
           "# Finish exactly once.  A timer and a second keypress both arrive here; the"
           "# lock keeps the loser from encoding the same clip twice or saving it twice."
           "finish_video() {"
           "    local mode=\"$1\" file=\"\""
           "    [ -f \"$STATE/$mode.pid\" ] || return 0"
           "    mkdir \"$STATE/$mode.lock\" 2>/dev/null || return 0"
           "    stop_recorder \"$mode\" || true"
           "    rmdir \"$STATE/$mode.lock\" 2>/dev/null || true"
           "    file=\"$(recording_file \"$mode\")\""
           "    rm -f \"$STATE/$mode.file\""
           "    [ -n \"$file\" ] && [ -s \"$file\" ] \\"
           "        || die \"the recording came out empty: see $STATE/$mode.stop.log\""
           "    recording_ok \"$file\" \\"
           "        || die \"the recording is not playable: see $STATE/$mode.stop.log\""
           "    clip_text \"$file\""
           "    notify normal \"Recording saved\" \"$file (path copied to the clipboard)\""
           "    printf '%s\\n' \"$file\""
           "}"
           ""
           "finish_gif() {"
           "    local mode=\"$1\" preset=\"$2\" file=\"\" target=\"\""
           "    [ -f \"$STATE/$mode.pid\" ] || return 0"
           "    mkdir \"$STATE/$mode.lock\" 2>/dev/null || return 0"
           "    stop_recorder \"$mode\" || true"
           "    rmdir \"$STATE/$mode.lock\" 2>/dev/null || true"
           "    file=\"$(recording_file \"$mode\")\""
           "    rm -f \"$STATE/$mode.file\""
           "    [ -n \"$file\" ] || die \"no recording to convert: see $STATE/$mode.stop.log\""
           "    recording_ok \"$file\" \\"
           "        || die \"the recording is not playable: see $STATE/$mode.stop.log\""
           "    target=\"$GIFS/gif-$(stamp).gif\""
           "    encode_gif \"$file\" \"$target\" \"$preset\""
           "    rm -f \"$file\""
           "    clip_file \"$target\" image/gif"
           "    notify normal \"GIF saved\" \"$target (copied to the clipboard)\""
           "    printf '%s\\n' \"$target\""
           "}"

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
   "    if [ -f \"$STATE/$mode.pid\" ]; then"
   "        finish_video \"$mode\""
   "        return $?"
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
   "        ( sleep \"$seconds\"; finish_video \"$mode\" ) >>\"$STATE/$mode.stop.log\" 2>&1 &"
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
           "    local filter=\"\" fps=0 quality=0 colors=0 lossy=0 palette=\"\" use_gifski=0"
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
           "    # auto takes gifski when it is installed, because gifski does"
           "    # cross-frame palettes and dithering an ffmpeg palette cannot; the"
           "    # two other values exist so a machine - or a test - can insist."
           "    case \"${CAPTURE_GIF_ENCODER:-auto}\" in"
           "        gifski) need gifski; use_gifski=1 ;;"
           "        ffmpeg) use_gifski=0 ;;"
           "        auto) command -v gifski >/dev/null 2>&1 && use_gifski=1 ;;"
           "        *) die \"CAPTURE_GIF_ENCODER must be auto, gifski or ffmpeg\" ;;"
           "    esac"
           "    if [ \"$use_gifski\" = 1 ]; then"
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
           "    if [ -f \"$STATE/$mode.pid\" ]; then"
           "        finish_gif \"$mode\" \"$preset\""
           "        return $?"
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
           "        ( sleep \"$seconds\"; finish_gif \"$mode\" \"$preset\" ) >>\"$STATE/$mode.stop.log\" 2>&1 &"
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

(define (capture-edit-commands)
  (script-text
   ""
   "# A plain menu: these lists are three or four rows and typing narrows"
   "# nothing, so the search field goes, and with it the mode pills and the"
   "# input row.  The launcher keeps all three."
   "#"
   "# This is a function rather than a variable holding the flags, because the"
   "# flags have to reach rofi as one argument: an unquoted variable splits on"
   "# the spaces inside the theme string, rofi then sees `entry', `{',"
   "# `enabled:' and the rest as separate arguments, and answers with a theme"
   "# parse error."
   "rofi_menu() {"
   "    rofi -replace -theme-str 'entry { enabled: false; } mode-switcher { enabled: false; } inputbar { enabled: false; }' \"$@\""
   "}"
   ""
   "# The newest file in a directory, without find(1)."
   "latest_file() {"
   "    local dir=\"$1\" pattern=\"$2\" candidate=\"\" newest=\"\""
   "    for candidate in \"$dir\"/$pattern; do"
   "        [ -e \"$candidate\" ] || continue"
   "        if [ -z \"$newest\" ] || [ \"$candidate\" -nt \"$newest\" ]; then"
   "            newest=\"$candidate\""
   "        fi"
   "    done"
   "    [ -n \"$newest\" ] || die \"no $pattern in $dir\""
   "    printf '%s\\n' \"$newest\""
   "}"
   ""
   "# One question, answered in rofi; the default is offered as the line to"
   "# accept, so a bare Enter keeps the common case."
   "ask() {"
   "    local prompt=\"$1\" default=\"$2\" answer=\"\""
   "    command -v rofi >/dev/null 2>&1 || die \"rofi is not installed\""
   "    answer=\"$(printf '%s\\n' \"$default\" | rofi -replace -dmenu -p \"$prompt\")\" || exit 0"
   "    printf '%s\\n' \"${answer:-$default}\""
   "}"
   ""
   "pick_file() {"
   "    local dir=\"$1\" pattern=\"$2\" prompt=\"$3\" chosen=\"\""
   "    command -v rofi >/dev/null 2>&1 || die \"rofi is not installed\""
   "    chosen=\"$(ls -t \"$dir\"/$pattern 2>/dev/null | head -n 20 | rofi -replace -dmenu -i -p \"$prompt\")\" || exit 0"
   "    [ -n \"$chosen\" ] || exit 0"
   "    printf '%s\\n' \"$chosen\""
   "}"
   ""
   "# Annotate a screenshot.  The editor is whichever one is installed, and the"
   "# result is a new file beside the original: an annotation is an addition, so"
   "# the untouched screenshot stays where the capture put it."
   "# What this program drives.  A missing recorder is a fallback, a missing"
   "# grim is nothing at all, and the difference is worth printing instead of"
   "# finding out from a key that does not work."
   "cmd_doctor() {"
   "    local missing=0 tool=\"\""
   "    for tool in grim slurp wl-copy fyi rofi ffmpeg gifsicle magick; do"
   "        if ! command -v \"$tool\" >/dev/null 2>&1; then"
   "            printf 'missing: %s\\n' \"$tool\""
   "            missing=1"
   "        fi"
   "    done"
   "    if ! command -v wl-screenrec >/dev/null 2>&1 \\"
   "        && ! command -v wf-recorder >/dev/null 2>&1; then"
   "        printf 'missing: a recorder (wl-screenrec or wf-recorder)\\n'"
   "        missing=1"
   "    fi"
   "    if ! command -v satty >/dev/null 2>&1 \\"
   "        && ! command -v swappy >/dev/null 2>&1 \\"
   "        && ! command -v gimp >/dev/null 2>&1; then"
   "        printf 'missing: an annotation editor (satty, swappy or gimp)\\n'"
   "        missing=1"
   "    fi"
   "    command -v gifski >/dev/null 2>&1 \\"
   "        || printf 'optional: gifski (ffmpeg encodes the GIF without it)\\n'"
   "    if [ \"$missing\" = 0 ]; then"
   "        printf 'every capture tool is installed\\n'"
   "    else"
   "        printf 'install with: maak install-zypper and maak install-nix-packages\\n'"
   "    fi"
   "    return \"$missing\""
   "}"
   ""
   "# What am I taking, and of how much of the screen?  Two questions, then the"
   "# capture the keys already run: the same shot, gif and video verbs, so this"
   "# menu and the bindings cannot drift apart."
   "cmd_choose() {"
   "    local what=\"\" scope=\"\""
   "    command -v rofi >/dev/null 2>&1 || die \"rofi is not installed\""
   "    ensure_dirs"
   "    what=\"$(printf 'Screenshot\\nGIF\\nVideo\\n' | rofi_menu -dmenu -i -p 'Capture')\" || exit 0"
   "    [ -n \"$what\" ] || exit 0"
   "    case \"$what\" in"
   "        Screenshot)"
   "            scope=\"$(printf 'Whole screen\\nRegion\\nWindow\\n' | rofi_menu -dmenu -i -p 'How much?')\" || exit 0"
   "            case \"$scope\" in"
   "                'Whole screen') cmd_shot output ;;"
   "                Region) cmd_shot region ;;"
   "                Window) cmd_shot window ;;"
   "                *) exit 0 ;;"
   "            esac"
   "            ;;"
   "        GIF)"
   "            scope=\"$(printf 'Whole screen\\nRegion\\n' | rofi_menu -dmenu -i -p 'How much?')\" || exit 0"
   "            case \"$scope\" in"
   "                'Whole screen') cmd_gif output ;;"
   "                Region) cmd_gif region ;;"
   "                *) exit 0 ;;"
   "            esac"
   "            ;;"
   "        Video)"
   "            scope=\"$(printf 'Whole screen\\nRegion\\n' | rofi_menu -dmenu -i -p 'How much?')\" || exit 0"
   "            case \"$scope\" in"
   "                'Whole screen') cmd_video output ;;"
   "                Region) cmd_video region ;;"
   "                *) exit 0 ;;"
   "            esac"
   "            ;;"
   "        *) exit 0 ;;"
   "    esac"
   "}"
   ""
   "cmd_annotate() {"
   "    local target=\"${1:-}\" editor=\"\" out=\"\" base=\"\""
   "    [ $# -gt 0 ] && shift"
   "    while [ $# -gt 0 ]; do"
   "        case \"$1\" in"
   "            --editor) shift; editor=\"${1:-}\" ;;"
   "            *) die \"annotate: unknown option $1\" ;;"
   "        esac"
   "        shift"
   "    done"
   "    ensure_dirs"
   "    [ -n \"$target\" ] || target=\"$(latest_file \"$SHOTS\" '*.png')\""
   "    [ -f \"$target\" ] || die \"annotate: $target does not exist\""
   "    base=\"${target%.*}\""
   "    out=\"$base-annotated.png\""
   "    if [ -z \"$editor\" ]; then"
   "        if command -v satty >/dev/null 2>&1; then editor=satty"
   "        elif command -v swappy >/dev/null 2>&1; then editor=swappy"
   "        elif command -v gimp >/dev/null 2>&1; then editor=gimp"
   "        else die \"no annotation editor: install satty, swappy or gimp\"; fi"
   "    fi"
   "    case \"$editor\" in"
   "        satty) \"$editor\" --filename \"$target\" --output-filename \"$out\" --copy-command wl-copy ;;"
   "        swappy) \"$editor\" --file \"$target\" --output \"$out\" ;;"
   "        gimp) \"$editor\" \"$target\" >/dev/null 2>&1 & ;;"
   "        *) die \"annotate: $editor is not an editor this knows\" ;;"
   "    esac"
   "    if [ -s \"$out\" ]; then"
   "        clip_file \"$out\" image/png"
   "        notify normal \"Screenshot edited\" \"$out (copied to the clipboard)\""
   "        printf '%s\\n' \"$out\""
   "    else"
   "        notify low \"Screenshot editor closed\" \"$target is unchanged\""
   "    fi"
   "}"
   ""
   "# Edit a GIF: cut it, change its speed, crop or resize it, change its"
   "# colours or its hue, reverse it, or make it smaller."
   "cmd_gif_edit() {"
   "    local source=\"${1:-}\" start=\"\" duration=\"\" speed=\"\" crop=\"\" resize=\"\" width=\"\""
   "    local colors=\"\" hue=\"\" saturation=\"\" brightness=\"\" contrast=\"\" fps=\"\""
   "    local reverse=0 lossy=\"\" pixels=0 target=\"\""
   "    [ $# -gt 0 ] && shift"
   "    while [ $# -gt 0 ]; do"
   "        case \"$1\" in"
   "            --start) shift; start=\"${1:-}\"; pixels=1 ;;"
   "            --duration) shift; duration=\"${1:-}\"; pixels=1 ;;"
   "            --speed) shift; speed=\"${1:-}\"; pixels=1 ;;"
   "            --crop) shift; crop=\"${1:-}\" ;;"
   "            --resize) shift; resize=\"${1:-}\" ;;"
   "            --width) shift; width=\"${1:-}\" ;;"
   "            --colors) shift; colors=\"${1:-}\" ;;"
   "            --hue) shift; hue=\"${1:-}\"; pixels=1 ;;"
   "            --saturation) shift; saturation=\"${1:-}\"; pixels=1 ;;"
   "            --brightness) shift; brightness=\"${1:-}\"; pixels=1 ;;"
   "            --contrast) shift; contrast=\"${1:-}\"; pixels=1 ;;"
   "            --fps) shift; fps=\"${1:-}\"; pixels=1 ;;"
   "            --reverse) reverse=1; pixels=1 ;;"
   "            --lossy) shift; lossy=\"${1:-}\" ;;"
   "            *) die \"gif-edit: unknown option $1\" ;;"
   "        esac"
   "        shift"
   "    done"
   "    ensure_dirs"
   "    [ -n \"$source\" ] || source=\"$(latest_file \"$GIFS\" '*.gif')\""
   "    [ -f \"$source\" ] || die \"gif-edit: $source is not a GIF\""
   "    target=\"${source%.gif}-edit.gif\""
   "    local n=2"
   "    while [ -e \"$target\" ]; do"
   "        target=\"${source%.gif}-edit-$n.gif\""
   "        n=$((n + 1))"
   "    done"
   "    if [ \"$pixels\" = 0 ]; then"
   "        # Nothing here needs pixels decoded: gifsicle edits the file"
   "        # losslessly, and the frames keep the palette they were recorded with."
   "        need gifsicle"
   "        local args=(-O3 --careful)"
   "        [ -n \"$crop\" ] && args+=(--crop \"$crop\")"
   "        [ -n \"$resize\" ] && args+=(--resize \"$resize\")"
   "        [ -n \"$width\" ] && args+=(--resize-width \"$width\")"
   "        [ -n \"$colors\" ] && args+=(--colors \"$colors\")"
   "        [ -n \"$lossy\" ] && args+=(--lossy=\"$lossy\")"
   "        gifsicle \"${args[@]}\" \"$source\" -o \"$target\" \\"
   "            || die \"gifsicle could not edit $source\""
   "    else"
   "        local filters=()"
   "        [ -n \"$crop\" ] && filters+=(\"crop=${crop#*+}\")"
   "        if [ -n \"$crop\" ]; then"
   "            local wh=\"${crop#*+}\" xy=\"${crop%%+*}\""
   "            filters[-1]=\"crop=${wh%x*}:${wh#*x}:${xy%,*}:${xy#*,}\""
   "        fi"
   "        [ -n \"$speed\" ] && filters+=(\"setpts=PTS/$speed\")"
   "        [ -n \"$hue\" ] && filters+=(\"hue=h=$hue:s=${saturation:-1}\")"
   "        [ -z \"$hue\" ] && [ -n \"$saturation\" ] && filters+=(\"hue=s=$saturation\")"
   "        if [ -n \"$brightness\" ] || [ -n \"$contrast\" ]; then"
   "            filters+=(\"eq=brightness=${brightness:-0}:contrast=${contrast:-1}\")"
   "        fi"
   "        [ \"$reverse\" = 1 ] && filters+=(\"reverse\")"
   "        [ -n \"$resize\" ] && filters+=(\"scale=${resize}\")"
   "        [ -z \"$resize\" ] && [ -n \"$width\" ] && filters+=(\"scale=$width:-1:flags=lanczos\")"
   "        local chain=\"fps=${fps:-20}\""
   "        [ ${#filters[@]} -gt 0 ] && chain=\"${chain},$(IFS=,; printf '%s' \"${filters[*]}\")\""
   "        need ffmpeg"
   "        rm -f \"$target\""
   "        if command -v gifski >/dev/null 2>&1; then"
   "            ffmpeg -nostdin -loglevel error ${start:+-ss \"$start\"} ${duration:+-t \"$duration\"} \\"
   "                -i \"$source\" -vf \"$chain\" -f yuv4mpegpipe - \\"
   "                | gifski --fps \"${fps:-20}\" --quality 90 -o \"$target\" - \\"
   "                || die \"gifski could not edit $source\""
   "        else"
   "            local palette=\"$STATE/palette-edit.png\""
   "            ffmpeg -nostdin -loglevel error -y ${start:+-ss \"$start\"} ${duration:+-t \"$duration\"} \\"
   "                -i \"$source\" -vf \"$chain,palettegen=max_colors=${colors:-256}:stats_mode=diff\" \"$palette\" \\"
   "                || die \"ffmpeg could not build a palette for $source\""
   "            ffmpeg -nostdin -loglevel error -y ${start:+-ss \"$start\"} ${duration:+-t \"$duration\"} \\"
   "                -i \"$source\" -i \"$palette\" \\"
   "                -lavfi \"$chain[x];[x][1:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle\" \"$target\" \\"
   "                || die \"ffmpeg could not edit $target\""
   "        fi"
   "        if [ -n \"$lossy\" ] && command -v gifsicle >/dev/null 2>&1; then"
   "            gifsicle -O3 --careful --lossy=\"$lossy\" \"$target\" -o \"$target.opt\" \\"
   "                && mv \"$target.opt\" \"$target\""
   "        fi"
   "    fi"
   "    [ -s \"$target\" ] || die \"the edited GIF came out empty\""
   "    clip_file \"$target\" image/gif"
   "    notify normal \"GIF edited\" \"$target (copied to the clipboard)\""
   "    printf '%s\\n' \"$target\""
   "}"
   ""
   "# The easy way in: a menu for the last screenshots and GIFs, with the few"
   "# edits that are worth doing from a keypress."
   "cmd_studio() {"
   "    local kind=\"${1:-}\" file=\"\" action=\"\" value=\"\" start=\"\" duration=\"\""
   "    local hue=\"\" saturation=\"\" brightness=\"\" contrast=\"\""
   "    command -v rofi >/dev/null 2>&1 || die \"rofi is not installed\""
   "    ensure_dirs"
   "    if [ -z \"$kind\" ]; then"
   "        kind=\"$(printf 'screenshot\\ngif\\n' | rofi_menu -dmenu -i -p 'Edit what?')\" || exit 0"
   "    fi"
   "    case \"$kind\" in"
   "        screenshot*)"
   "            file=\"$(pick_file \"$SHOTS\" '*.png' 'Screenshot')\""
   "            action=\"$(printf 'annotate\\nopen in GIMP\\ncopy the path\\nscale to half\\n' | rofi_menu -dmenu -i -p 'Do what?')\" || exit 0"
   "            case \"$action\" in"
   "                annotate) \"$0\" annotate \"$file\" ;;"
   "                \"open in GIMP\") need gimp; gimp \"$file\" >/dev/null 2>&1 & ;;"
   "                \"copy the path\") clip_text \"$file\"; notify normal \"Path copied\" \"$file\" ;;"
   "                \"scale to half\")"
   "                    need magick"
   "                    value=\"${file%.*}-half.png\""
   "                    magick \"$file\" -resize 50% \"$value\" || die \"magick could not scale $file\""
   "                    clip_file \"$value\" image/png"
   "                    notify normal \"Screenshot scaled\" \"$value (copied to the clipboard)\""
   "                    ;;"
   "                *) exit 0 ;;"
   "            esac"
   "            ;;"
   "        gif*)"
   "            file=\"$(pick_file \"$GIFS\" '*.gif' 'GIF')\""
   "            action=\"$(printf 'cut (start, duration)\\nspeed\\ncrop\\nwidth\\ncolours\\nhue and saturation\\nbrightness and contrast\\nreverse\\nmake it smaller\\n' | rofi_menu -dmenu -i -p 'Do what?')\" || exit 0"
   "            case \"$action\" in"
   "                \"cut\"*)"
   "                    start=\"$(ask 'Start (s)' 0)\""
   "                    duration=\"$(ask 'Duration (s)' 3)\""
   "                    \"$0\" gif-edit \"$file\" --start \"$start\" --duration \"$duration\""
   "                    ;;"
   "                speed)"
   "                    value=\"$(ask 'Speed factor' 2)\""
   "                    \"$0\" gif-edit \"$file\" --speed \"$value\""
   "                    ;;"
   "                crop)"
   "                    value=\"$(ask 'Crop X,Y+WxH' '0,0+640x400')\""
   "                    \"$0\" gif-edit \"$file\" --crop \"$value\""
   "                    ;;"
   "                width)"
   "                    value=\"$(ask 'Width' 640)\""
   "                    \"$0\" gif-edit \"$file\" --width \"$value\""
   "                    ;;"
   "                colours)"
   "                    value=\"$(ask 'Colours' 128)\""
   "                    \"$0\" gif-edit \"$file\" --colors \"$value\""
   "                    ;;"
   "                \"hue\"*)"
   "                    hue=\"$(ask 'Hue degrees' 90)\""
   "                    saturation=\"$(ask 'Saturation' 1.4)\""
   "                    \"$0\" gif-edit \"$file\" --hue \"$hue\" --saturation \"$saturation\""
   "                    ;;"
   "                brightness*)"
   "                    brightness=\"$(ask 'Brightness (-1..1)' 0.1)\""
   "                    contrast=\"$(ask 'Contrast (0..2)' 1.1)\""
   "                    \"$0\" gif-edit \"$file\" --brightness \"$brightness\" --contrast \"$contrast\""
   "                    ;;"
   "                reverse)"
   "                    \"$0\" gif-edit \"$file\" --reverse"
   "                    ;;"
   "                *smaller*)"
   "                    \"$0\" gif-edit \"$file\" --lossy 80"
   "                    ;;"
   "                *) exit 0 ;;"
   "            esac"
   "            ;;"
   "        *) exit 0 ;;"
   "    esac"
   "}"))

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
   "      CAPTURE_GIF_ENCODER=auto|gifski|ffmpeg picks the encoder; auto prefers gifski."
   ""
   "  heks-capture video region|output [--hevc] [--seconds N] [--geometry G]"
   "      A video recording as a toggle; the file's path is copied when it stops."
   ""
   "  heks-capture gif-edit [FILE] [--start S] [--duration S] [--speed F] [--crop X,Y+WxH]"
   "                           [--width W] [--resize WxH] [--colors N] [--hue DEG]"
   "                           [--saturation F] [--brightness F] [--contrast F]"
   "                           [--reverse] [--fps N] [--lossy N]"
   "      Edit a GIF: gifsicle handles crops, resizes and palettes without"
   "      re-encoding; speed, trim, hue and reverse go through ffmpeg."
   ""
   "  heks-capture annotate [FILE] [--editor satty|swappy|gimp]"
   "      Annotate the newest screenshot (or FILE) in the first editor"
   "      installed; the result is a new -annotated.png beside it."
   ""
   "  heks-capture choose"
   "      One menu: screenshot, GIF or video, then the whole screen or a region."
   ""
   "  heks-capture doctor"
   "      What the program needs and what is missing, with where to get it."
   ""
   "  heks-capture studio [screenshot|gif]"
   "      The same edits as a rofi menu, answering prompts."
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
   "        gif-edit) cmd_gif_edit \"$@\" ;;"
   "        annotate) cmd_annotate \"$@\" ;;"
   "        choose) cmd_choose ;;"
   "        doctor) cmd_doctor ;;"
   "        studio) cmd_studio \"$@\" ;;"
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
                 (capture-edit-commands)
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
