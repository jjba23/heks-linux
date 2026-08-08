;;; heks-linux

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; heks-linux is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; heks-linux is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with heks-linux.  If not, see <https://www.gnu.org/licenses/>.

(define-module (heks-linux gif)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-gif-config gif-out-dir
                               gif-fps
                               gif-pid-file
                               gif-tmp-vid-file
                               make-gif-recorder-script
                               gif-config-filename
                               gif-config-dir))

(define s
  (scriba-auto-logger))

(define gif-out-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

(define gif-fps
  (make-parameter 20))

(define gif-pid-file
  (make-parameter "/tmp/heks-gif-wf-recorder.pid"))

(define gif-tmp-vid-file
  (make-parameter "/tmp/heks-gif-tmp-wf-recorder.mp4"))

(define* (make-gif-recorder-script)
  "Generates the Bash region GIF recording script as a string."
  (format #f
   "#!/usr/bin/env bash

# Temporary files & output directory
PIDFILE=\"~a\"
TMP_VID=\"~a\"
OUT_DIR=\"~a\"
OUT_GIF=\"$OUT_DIR/gif_$(date +%Y-%m-%d_%H-%M-%S).gif\"

mkdir -p \"$OUT_DIR\"

# Check if recording is currently active
if [ -f \"$PIDFILE\" ]; then
    PID=$(cat \"$PIDFILE\")
    rm -f \"$PIDFILE\"

    # Send SIGINT to gracefully stop wf-recorder
    kill -INT \"$PID\" 2>/dev/null

    fyi -a \"GIF Recorder\" \"Processing GIF...\" \"Converting video to high-quality GIF...\"

    # Generate high-quality GIF using 2-pass palettegen in ffmpeg
    ffmpeg -y -i \"$TMP_VID\" -vf \"fps=~a,scale=flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse\" \"$OUT_GIF\" 2>/dev/null
    rm -f \"$TMP_VID\"

    if [ -f \"$OUT_GIF\" ]; then
        # Copy raw GIF to clipboard
        wl-copy --type image/gif < \"$OUT_GIF\"
        fyi -a \"GIF Recorder\" \"Recording Complete!\" \"Saved to $OUT_GIF and copied to clipboard.\"
    else
        fyi -u critical -a \"GIF Recorder\" \"Error\" \"Failed to generate GIF.\"
    fi
else
    # Select region with slurp
    GEOM=$(slurp -d)

    # Exit if user cancels selection (e.g. hits Escape)
    if [ -z \"$GEOM\" ]; then
        exit 0
    fi

    # Start wf-recorder in the background
    wf-recorder -g \"$GEOM\" -f \"$TMP_VID\" >/dev/null 2>&1 &
    REC_PID=$!
    echo \"$REC_PID\" > \"$PIDFILE\"

    fyi -a \"GIF Recorder\" \"Recording Started\" \"Press hotkey again to stop recording.\"
fi
"
   (gif-pid-file)
   (gif-tmp-vid-file)
   (gif-out-dir)
   (gif-fps)))

(define gif-config-filename
  (make-parameter "gif-record"))

(define gif-config-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define (install-gif-config)
  (log-info s "Installing GIF tooling")
  (load-local-overrides '(heks-linux gif)
                        'gif-settings)
  (install-config-file! #:name (gif-config-filename)
                        #:dir (gif-config-dir)
                        #:contents (make-gif-recorder-script))
  (log-success s "Installed GIF tooling"))
