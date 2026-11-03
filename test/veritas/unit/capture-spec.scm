;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux capture).  The module's product is a shell
;; program, so these tests run it: each case renders the script into a scratch
;; directory, puts stub tools on PATH that record their own argv, and then
;; asserts on what the program actually did - which flags the recorder was
;; given, which filter the encoder saw, whether a cancelled selection captured
;; anything at all.
;;
;; That is the only honest way to test this surface.  A test that asserts a
;; substring of the generated text passes while the program is broken; these
;; fail when a flag moves, when the toggling stops matching, or when a fallback
;; stops being reachable.
;;
;; Nothing here touches the real desktop: the directories are scratch paths,
;; the compositor and the encoders are stubs, and the clipboard is a file.

;;; Code:

(define-module (veritas unit capture-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux capture)
  #:use-module (heks-linux prelude)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-13)
  #:export (spec))

;; --- scratch space ------------------------------------------------------

(define (block . lines)
  "Return LINES as one text, one per line, ending in a newline."
  (string-append (string-join lines "\n") "\n"))

(define (scratch-root name)
  "Return a fresh scratch directory for a test called NAME."
  (format #f "/tmp/heks-capture-spec-~a/~a" (getpid) name))

(define (write-file! path text)
  (ensure-directory-tree! (dirname path))
  (call-with-output-file path
                         (lambda (port)
                           (display text port))))

(define (read-file path)
  "Return PATH's text, or the empty string when it is not there.

Read a character at a time: these are the stubs' logs, and the ports module is
not worth an import for files this small."
  (if (file-exists? path)
    (call-with-input-file path
                          (lambda (port)
                            (let loop ((chars '()))
                              (let ((c (read-char port)))
                                (if (eof-object? c)
                                  (list->string (reverse chars))
                                  (loop (cons c chars)))))))
    ""))

(define (contains? text fragment)
  "Whether FRAGMENT appears in TEXT, as a boolean."
  (if (string-contains text fragment) #t #f))

(define (stub! root name text)
  "Write an executable stub called NAME into ROOT/bin and return its path."
  (let ((path (format #f "~a/bin/~a" root name)))
    (write-file! path text)
    (system* "chmod" "755" path)
    path))

;; Every root a test rendered into.  Recordings left running would keep the
;; container's ports open after the last assertion, so the spec stops them all
;; before it answers.
(define visited-roots
  (make-parameter '()))

(define (sh-ok? command)
  "Whether COMMAND, run by a shell, exits 0."
  (eqv? 0 (status:exit-val (system* (find-bash) "-c" command))))

;; --- stubs --------------------------------------------------------------

(define (find-bash)
  "Return the bash this environment can actually run.

The pinned shell is a Guix container: `/usr/bin/env` is not there, so a stub
whose shebang names it cannot start.  Find bash on PATH and spell it out."
  (let loop ((dirs (string-split (or (getenv "PATH") "") #\:)))
    (cond [(null? dirs) "bash"]
          [(file-exists? (string-append (car dirs) "/bash"))
           (string-append (car dirs) "/bash")]
          [else (loop (cdr dirs))])))

(define (stub-header)
  (format #f "#!~a" (find-bash)))

(define (logger name)
  (block (stub-header)
         (format #f "echo \"~a $*\" >> \"$LOG\"" name)))

(define (grim-stub)
  (block (stub-header)
         "echo \"grim $*\" >> \"$LOG\""
         "out=\"\""
         "for a in \"$@\"; do out=\"$a\"; done"
         "if [ \"$out\" = \"-\" ]; then printf 'PNG'; else printf 'PNG' > \"$out\"; fi"
         "exit 0"))

;; A recorder has to stay alive until SIGINT and then leave a non-empty file
;; behind, because that is the contract every caller depends on: the toggle's
;; second press finds a process to signal, and the encoder finds something to
;; read.
(define (recorder-stub name)
  (block (stub-header)
         (format #f "echo \"~a $*\" >> \"$LOG\"" name)
         "file=\"\""
         "prev=\"\""
         "for a in \"$@\"; do"
         "    if [ \"$prev\" = \"-f\" ]; then file=\"$a\"; fi"
         "    prev=\"$a\""
         "done"
         ;; A shell started in the background of a non-interactive script has
         ;; SIGINT ignored, which a real recorder (a program with its own signal
         ;; handlers) does not.  The stub therefore leaves its bytes behind at
         ;; once and ends on the TERM that the script sends when INT does not
         ;; land, so the toggle is exercised the same way either way.
         "[ -n \"$file\" ] && printf bytes > \"$file\""
         "trap 'exit 0' TERM"
         "while :; do sleep 0.05; done"))

(define (ffmpeg-stub)
  (block (stub-header)
         "echo \"ffmpeg $*\" >> \"$LOG\""
         "last=\"\""
         "for a in \"$@\"; do last=\"$a\"; done"
         "if [ \"$last\" = \"-\" ]; then"
         "    printf 'YUV4MPEG2\\n'"
         "else"
         "    printf bytes > \"$last\""
         "fi"
         "exit 0"))

(define (gifski-stub)
  (block (stub-header)
         "echo \"gifski $*\" >> \"$LOG\""
         "out=\"\""
         "prev=\"\""
         "for a in \"$@\"; do"
         "    if [ \"$prev\" = \"-o\" ]; then out=\"$a\"; fi"
         "    prev=\"$a\""
         "done"
         "cat > /dev/null"
         "[ -n \"$out\" ] && printf gifbytes > \"$out\""
         "exit 0"))

(define (gifsicle-stub)
  (block (stub-header)
         "echo \"gifsicle $*\" >> \"$LOG\""
         "out=\"\""
         "prev=\"\""
         "for a in \"$@\"; do"
         "    if [ \"$prev\" = \"-o\" ]; then out=\"$a\"; fi"
         "    prev=\"$a\""
         "done"
         "[ -n \"$out\" ] && printf optbytes > \"$out\""
         "exit 0"))

(define (satty-stub)
  (block (stub-header)
         "echo \"satty $*\" >> \"$LOG\""
         "out=\"\""
         "prev=\"\""
         "for a in \"$@\"; do"
         "    if [ \"$prev\" = \"--output-filename\" ]; then out=\"$a\"; fi"
         "    prev=\"$a\""
         "done"
         "[ -n \"$out\" ] && printf annotated > \"$out\""
         "exit 0"))

;; --- rendering the program ----------------------------------------------

(define* (render! root #:key (gifski? #t) (gpu-recorder? #t) (slurp "0,0 200x100"))
  "Render the capture script into ROOT's bin, with stubs for every tool.

The directories are passed through the module's parameters, so the script is
written the way a real installation writes it - absolute paths, no tilde - and
the tests never go near the user's own pictures."
  (let* ((bin (format #f "~a/bin" root))
         (shots (format #f "~a/shots" root))
         (videos (format #f "~a/videos" root))
         (gifs (format #f "~a/gifs" root)))
    (ensure-directory-tree! bin)
    (for-each (lambda (dir) (ensure-directory-tree! dir))
              (list shots videos gifs (format #f "~a/run" root)))
    (stub! root "fyi" (logger "fyi"))
    (stub! root "wl-copy"
           (block (stub-header)
                  "echo \"wl-copy $*\" >> \"$LOG\""
                  "cat > /dev/null"))
    (stub! root "slurp" (block (stub-header)
                               "echo \"slurp $*\" >> \"$LOG\""
                               (format #f "printf '%s\\n' '~a'" slurp)))
    (stub! root "grim" (grim-stub))
    ;; niri's window screenshot is its own file: the stub writes one, which is
    ;; what the real compositor does at the path its configuration names.
    (stub! root "niri" (block (stub-header)
                              "echo \"niri $*\" >> \"$LOG\""
                              "case \"$*\" in"
                              "    *focused-output*) printf '%s\\n' '{\"name\":\"eDP-1\"}' ;;"
                              (format #f "    *screenshot-window*) printf PNG > '~a/screen-niri.png' ;;"
                                      shots)
                              "esac"
                              "exit 0"))
    (stub! root "satty" (satty-stub))
    (stub! root "ffmpeg" (ffmpeg-stub))
    (stub! root "gifsicle" (gifsicle-stub))
    (stub! root "wf-recorder" (recorder-stub "wf-recorder"))
    (when gpu-recorder?
      (stub! root "wl-screenrec" (recorder-stub "wl-screenrec")))
    (when gifski?
      (stub! root "gifski" (gifski-stub)))
    (visited-roots (cons root (visited-roots)))
    (parameterize ((capture-script-dir bin)
                   (capture-screenshots-dir shots)
                   (capture-videos-dir videos)
                   (capture-gifs-dir gifs))
      (install-capture-config))
    root))

(define* (run! root args #:key (env '()))
  "Run the rendered script in ROOT with ARGS and extra ENV pairs.

Answers the exit status and everything the stubs logged."
  (let* ((script (format #f "~a/bin/heks-capture" root))
         (log (format #f "~a/calls.log" root))
         (runtime (format #f "~a/run" root))
         (path (format #f "~a/bin:~a" root (or (getenv "PATH") ""))))
    (ensure-directory-tree! runtime)
    (let ((status
           (status:exit-val
            (apply system*
                   (append (list "env"
                                 (format #f "PATH=~a" path)
                                 (format #f "LOG=~a" log)
                                 (format #f "XDG_RUNTIME_DIR=~a" runtime))
                           env
                           (list (find-bash) script)
                           args)))))
      (values status (read-file log)))))

(define (state-file root name)
  (format #f "~a/run/heks-capture/~a" root name))

(define (script-path root)
  (format #f "~a/bin/heks-capture" root))

;; --- the suites ---------------------------------------------------------

(define (program-suite)
  (suite "The Program"
    (test "The Script Is Written As An Executable Program"
      (let* ((root (render! (scratch-root "program")))
             (script (script-path root))
             (text (read-file script)))
        (assert-true (file-exists? script)
          #:name "the program is written")
        (assert-true (contains? text "#!")
          #:name "it starts with a shell's shebang")
        (assert-true (sh-ok? (format #f "test -x '~a'" script))
          #:name "it is executable")
        (assert-true (contains? text (format #f "SHOTS=\"~a/shots\"" root))
          #:name "the screenshots directory is absolute, not a tilde")
        (assert-true (not (contains? text "\"~/"))
          #:name "no directory is left for the shell to expand")))
    (test "An Unknown Verb Is A Usage Error"
      (let* ((root (render! (scratch-root "unknown"))))
        (let-values (((status log) (run! root '("nonsense"))))
          (assert-equal #:expect 2 #:got status
            #:name "an unknown verb exits 2"))))))

(define (screenshot-suite)
  (suite "Screenshots"
    (test "An Output Is Captured By Grim And Copied"
      (let* ((root (render! (scratch-root "shot-output")))
             (shots (format #f "~a/shots" root)))
        (let-values (((status log) (run! root '("shot" "output"))))
          (assert-equal #:expect 0 #:got status
            #:name "the shot succeeds")
          (assert-true (contains? log "grim -o eDP-1")
            #:name "grim is given the focused output")
          (assert-true (sh-ok? (format #f "test -n \"$(ls -A ~a/*.png 2>/dev/null | head -n 1)\"" shots))
            #:name "a PNG lands in the screenshots directory")
          (assert-true (contains? log "wl-copy --type image/png")
            #:name "the picture is copied to the clipboard"))))
    (test "A Region Comes From Slurp, Or Nothing Happens"
      (let* ((root (render! (scratch-root "shot-region"))))
        (let-values (((status log) (run! root '("shot" "region"))))
          (assert-equal #:expect 0 #:got status
            #:name "the shot succeeds")
          (assert-true (contains? log "grim -g 0,0 200x100")
            #:name "the geometry slurp answered is what grim is given")))
      (let* ((root (render! (scratch-root "shot-cancelled") #:slurp "")))
        (let-values (((status log) (run! root '("shot" "region"))))
          (assert-equal #:expect 0 #:got status
            #:name "a cancelled selection is not an error")
          (assert-true (not (contains? log "grim -g"))
            #:name "a cancelled selection captures nothing"))))
    (test "A Clipboard-Only Shot Writes No File"
      (let* ((root (render! (scratch-root "shot-clipboard"))))
        (let-values (((status log) (run! root
                                         '("shot" "region" "--clipboard"))))
          (assert-equal #:expect 0 #:got status
            #:name "the shot succeeds")
          (assert-true (sh-ok? (format #f "test -z \"$(ls ~a/shots/*.png 2>/dev/null)\""
                                       root))
            #:name "nothing is written to the screenshots directory")
          (assert-true (contains? log "grim -g 0,0 200x100 -")
            #:name "grim writes to stdout instead"))))
    (test "A Window Is Captured By The Compositor"
      (let* ((root (render! (scratch-root "shot-window"))))
        (let-values (((status log) (run! root '("shot" "window"))))
          (assert-equal #:expect 0 #:got status
            #:name "the shot succeeds")
          (assert-true (contains? log "niri msg action screenshot-window")
            #:name "niri's own action takes the picture")
          (assert-true (contains? log "wl-copy --type image/png")
            #:name "the file niri wrote is copied"))))
    (test "Annotation Runs Only When Asked For"
      (let* ((root (render! (scratch-root "shot-annotate")))
             (log (format #f "~a/calls.log" root)))
        (run! root '("shot" "output"))
        (assert-true (not (contains? (read-file log) "satty"))
          #:name "a plain screenshot does not open an editor")
        (run! root '("shot" "output" "--annotate"))
        (assert-true (contains? (read-file log) "satty --filename")
          #:name "--annotate hands the picture to satty")))))

(define (video-suite)
  (suite "Video"
    (test "The GPU Recorder Is Used When It Exists"
      (let* ((root (render! (scratch-root "video-gpu"))))
        (let-values (((status log) (run! root '("video" "output"))))
          (assert-equal #:expect 0 #:got status
            #:name "the recording starts")
          (assert-true (contains? log "wl-screenrec")
            #:name "wl-screenrec is the recorder")
          (assert-true (contains? log "--codec avc")
            #:name "the codec is named the way wl-screenrec spells it")
          (assert-true (contains? log "-o eDP-1")
            #:name "the focused output is what gets recorded"))
        (let ((file (read-file (state-file root "video-output.file"))))
          (let-values (((status log) (run! root '("video" "output"))))
            (assert-equal #:expect 0 #:got status
              #:name "the second press stops the recording")
            (assert-true (sh-ok? (format #f "test -s '~a'" file))
              #:name "the recording is a non-empty file"))
          (assert-true (not (file-exists? (state-file root "video-output.pid")))
            #:name "the pid file is gone once it stopped")
          (assert-true (contains? (read-file (format #f "~a/calls.log" root))
                                  "fyi -u normal -a Capture Recording saved")
            #:name "the user is told where it went"))))
    (test "wf-recorder Is The Fallback"
      (let* ((root (render! (scratch-root "video-forced-wf"))))
        (let-values (((status log)
                      (run! root '("video" "output")
                            #:env '("CAPTURE_RECORDER=wf-recorder"))))
          (assert-equal #:expect 0 #:got status
            #:name "the recording starts")
          (assert-true (contains? log "wf-recorder")
            #:name "CAPTURE_RECORDER=wf-recorder forces the fallback")
          (assert-true (contains? log "-c libx264")
            #:name "it is told the encoder explicitly")
          (assert-true (contains? log "profile=main")
            #:name "the profile the system's decoder needs is kept"))))
    (test "A Region Recording Is Rounded To Even Pixels"
      (let* ((root (render! (scratch-root "video-region"))))
        (let-values (((status log)
                      (run! root '("video" "region")
                            #:env '("CAPTURE_GEOMETRY=10,10 101x99"))))
          (assert-equal #:expect 0 #:got status
            #:name "the recording starts")
          (assert-true (contains? log "-g 10,10 100x98")
            #:name "an odd region is cut to what H.264 can encode"))))
    (test "A Window Recording Is Refused With A Reason"
      (let* ((root (render! (scratch-root "video-window"))))
        (let-values (((status log) (run! root '("video" "window"))))
          (assert-equal #:expect 1 #:got status
            #:name "there is nothing to record a window with")
          (assert-true (contains? (read-file (format #f "~a/calls.log" root))
                                  "portal recorder such as OBS")
            #:name "the refusal names the tool that could do it"))))))

(define (gif-suite)
  (suite "GIFs"
    (test "A High-Quality GIF Goes Through gifski"
      (let* ((root (render! (scratch-root "gif-high"))))
        (let-values (((status log) (run! root '("gif" "output"))))
          (assert-equal #:expect 0 #:got status
            #:name "the recording starts"))
        (let-values (((status log) (run! root '("gif" "output"))))
          (assert-equal #:expect 0 #:got status
            #:name "the second press converts it")
          (assert-true (contains? log "fps=20")
            #:name "twenty frames a second")
          (assert-true (contains? log "gifski --fps 20 --quality 90")
            #:name "gifski is given the frame rate and the quality")
          (assert-true (sh-ok? (format #f "test -n \"$(ls -A ~a/gifs/*.gif 2>/dev/null | head -n 1)\"" root))
            #:name "a GIF lands in the GIFs directory")
          (assert-true (contains? log "wl-copy --type image/gif")
            #:name "the GIF is copied to the clipboard"))))
    (test "The Low Preset Cuts The Size"
      (let* ((root (render! (scratch-root "gif-low")))
             (source (format #f "~a/sample.mp4" root)))
        (write-file! source "bytes")
        (let-values (((status log) (run! root (list "gif-from" source "--low"))))
          (assert-equal #:expect 0 #:got status
            #:name "the conversion succeeds")
          (assert-true (contains? log "fps=12,scale=640:-1:flags=lanczos")
            #:name "twelve frames a second at six hundred and forty pixels wide")
          (assert-true (contains? log "--lossy=80")
            #:name "gifsicle is allowed to lose what nobody will see")
          (assert-true (sh-ok? (format #f "test -n \"$(ls -A ~a/gifs/*.gif 2>/dev/null | head -n 1)\"" root))
            #:name "a GIF is written"))))
    (test "Without gifski The Palette Path Runs"
      (let* ((root (render! (scratch-root "gif-fallback") #:gifski? #f))
             (source (format #f "~a/sample.mp4" root)))
        (write-file! source "bytes")
        (let-values (((status log) (run! root (list "gif-from" source "--low"))))
          (assert-equal #:expect 0 #:got status
            #:name "the conversion succeeds")
          (assert-true (contains? log "palettegen=max_colors=128:stats_mode=diff")
            #:name "the small palette is built from the recording")
          (assert-true (contains? log "paletteuse=dither=sierra2_4a")
            #:name "the frames are mapped through it"))))
    (test "A Recording Without Content Is Not Encoded"
      (let* ((root (render! (scratch-root "gif-empty")))
             (source (format #f "~a/empty.mp4" root)))
        (write-file! source "")
        (let-values (((status log) (run! root (list "gif-from" source))))
          (assert-equal #:expect 1 #:got status
            #:name "an empty recording fails")
          (assert-true (not (contains? log "gifski"))
            #:name "no encoder is started for nothing"))))))

(define (toggling-suite)
  (suite "Toggles"
    (test "Status Reports What Is Recording"
      (let* ((root (render! (scratch-root "status"))))
        (run! root '("gif" "output"))
        (let-values (((status log) (run! root '("status"))))
          (assert-equal #:expect 0 #:got status
            #:name "status exits successfully"))
        (assert-true (file-exists? (state-file root "gif-high-output.pid"))
          #:name "the GIF recording is on record")))
    (test "Stop Stops Everything That Started"
      (let* ((root (render! (scratch-root "stop"))))
        (run! root '("video" "output"))
        (run! root '("gif" "output" "--low"))
        (let-values (((status log) (run! root '("stop"))))
          (assert-equal #:expect 0 #:got status
            #:name "stop exits successfully")
          (assert-true (not (file-exists? (state-file root "video-output.pid")))
            #:name "the video recording is stopped")
          (assert-true (not (file-exists? (state-file root "gif-low-output.pid")))
            #:name "the low GIF recording is stopped"))))
    (test "Two Qualities Are Two Recordings"
      (let* ((root (render! (scratch-root "two-presets"))))
        (run! root '("gif" "output" "--low"))
        (let-values (((status log) (run! root '("gif" "output"))))
          (assert-equal #:expect 0 #:got status
            #:name "the high recording starts while the low one runs")
          (assert-true (file-exists? (state-file root "gif-low-output.pid"))
            #:name "the low recording is untouched")
          (assert-true (file-exists? (state-file root "gif-high-output.pid"))
            #:name "and the high one is its own recording"))))))

(define (spec)
  (let ((result (veritas-run (program-suite)
                  (screenshot-suite)
                  (video-suite)
                  (gif-suite)
                  (toggling-suite))))
    (for-each (lambda (root)
                (run! root '("stop")))
              (visited-roots))
    result))
