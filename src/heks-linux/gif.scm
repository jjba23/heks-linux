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

;;; Commentary:
;;
;; Generates @file{~/.local/bin/gif-record}, the screen-recording helper bound
;; to @kbd{Mod+Shift+G} in the Niri configuration.
;;
;; It is a @emph{toggle}, not a recorder: the first invocation asks @code{slurp}
;; for a region and starts @code{wf-recorder} in the background, writing its PID
;; to a pid file.  The second invocation signals that PID, waits for the encoder
;; to flush, converts the intermediate MP4 to a palette-optimised GIF with
;; @code{ffmpeg}, copies it to the clipboard with @code{wl-copy} and notifies
;; the user through @code{fyi}.
;;
;; Two details are load-bearing and worth preserving: the intermediate file is
;; encoded with @code{profile=main level=4.2} so that the system's libopenh264
;; can decode it again, and the region geometry is forced to even dimensions
;; with @code{scale=trunc(iw/2)*2:trunc(ih/2)*2} because H.264 rejects odd
;; widths and heights.
;;
;; The script intentionally stays quiet on success and logs to
;; @file{/tmp/heks-wf-recorder.log} and @file{/tmp/heks-ffmpeg.log} on failure.

;;; Code:

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

;; Directory receiving the finished @file{gif_<timestamp>.gif} files.  Defaults
;; to your home directory; a @file{~/Pictures} style path is usually nicer.
(define gif-out-dir
  (make-parameter (format #f "~a"
                          (or (getenv "HOME") "/tmp"))))

;; Frames per second of the generated GIF.  Higher is smoother and larger;
;; 20 keeps most UI recordings under a megabyte.
(define gif-fps
  (make-parameter 20))

;; Where the running wf-recorder's PID is stored between the two invocations of
;; the toggle.  Its existence is what tells the script which half to run.
(define gif-pid-file
  (make-parameter "/tmp/heks-gif-wf-recorder.pid"))

;; Intermediate H.264 file.  Kept in /tmp so a crashed recording never leaves
;; junk in your home directory.
(define gif-tmp-vid-file
  (make-parameter "/tmp/heks-gif-tmp-wf-recorder.mp4"))

;; ---

(define script-header
  "#!/usr/bin/env bash

# Temporary files & output directory
PIDFILE=\"~a\"
TMP_VID=\"~a\"
OUT_DIR=\"~a\"
OUT_GIF=\"$OUT_DIR/gif_$(date +%Y-%m-%d_%H-%M-%S).gif\"

mkdir -p \"$OUT_DIR\"
")

(define script-stop-block
  "# Check if recording is currently active
if [ -f \"$PIDFILE\" ]; then
    PID=$(cat \"$PIDFILE\")
    rm -f \"$PIDFILE\"

    # Send SIGINT to gracefully stop wf-recorder
    kill -INT \"$PID\" 2>/dev/null

    # Wait for process to fully exit and flush file buffers
    while kill -0 \"$PID\" 2>/dev/null; do
        sleep 0.1
    done

    # Ensure recorded file exists and has non-zero size
    if [ ! -s \"$TMP_VID\" ]; then
        fyi -u critical -a \"GIF Recorder\" \"Error\" \"Recorded video is empty.\"
        exit 1
    fi

    fyi -a \"GIF Recorder\" \"Processing GIF...\" \"Converting video to high-quality GIF...\"

    # Generate looping GIF
    ffmpeg -y -i \"$TMP_VID\"         -vf \"fps=~a,scale=trunc(iw/2)*2:trunc(ih/2)*2,split[s0][s1];[s0]palettegen=stats_mode=full[p];[s1][p]paletteuse=dither=sierra2_4a\"         -loop 0 \"$OUT_GIF\" >/tmp/heks-ffmpeg.log 2>&1

    rm -f \"$TMP_VID\"

    # Verify GIF generation succeeded
    if [ -s \"$OUT_GIF\" ]; then
        wl-copy --type image/gif < \"$OUT_GIF\"
        fyi -a \"GIF Recorder\" \"Recording Complete!\" \"Saved to $OUT_GIF and copied to clipboard.\"
    else
        fyi -u critical -a \"GIF Recorder\" \"Error\" \"Failed to generate GIF. Check /tmp/heks-ffmpeg.log\"
    fi
")

(define script-start-block
  "else
    # Select region with slurp
    GEOM=$(slurp -d)

    # Exit if user cancels selection
    if [ -z \"$GEOM\" ]; then
        exit 0
    fi

    # Ensure no lingering file blocks wf-recorder
    rm -f \"$TMP_VID\"

    # Force profile=main and level=4.2 so libopenh264 can decode the intermediate file
    wf-recorder -c libx264 -x yuv420p -p profile=main -p level=4.2 -g \"$GEOM\" -f \"$TMP_VID\" >/tmp/heks-wf-recorder.log 2>&1 &
    REC_PID=$!
    echo \"$REC_PID\" > \"$PIDFILE\"

    # Verify process started successfully
    sleep 0.3
    if ! kill -0 \"$REC_PID\" 2>/dev/null; then
        rm -f \"$PIDFILE\"
        fyi -u critical -a \"GIF Recorder\" \"Error\" \"wf-recorder failed to start. Check /tmp/heks-wf-recorder.log\"
        exit 1
    fi

    fyi -a \"GIF Recorder\" \"Recording Started\" \"Press hotkey again to stop recording.\"
fi
")

;; --- Script Generator ---

(define* (make-gif-recorder-script)
  "Generates the Bash region GIF recording script as a string."
  (format #f "~a~a~a"
          (format #f script-header
                  (gif-pid-file)
                  (gif-tmp-vid-file)
                  (gif-out-dir))
          (format #f script-stop-block
                  (gif-fps)) script-start-block))

;; Name of the generated executable; the Niri binding and the documentation both
;; refer to it as @code{gif-record}.
(define gif-config-filename
  (make-parameter "gif-record"))

;; Directory receiving the script; @file{~/.local/bin} is assumed to be on PATH.
(define gif-config-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define (install-gif-config)
  "Write the region GIF recorder to @code{gif-config-dir} with mode #o755.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/gif-settings.scm} first, so @code{gif-out-dir}
and @code{gif-fps} can be tweaked per machine."
  (log-info s "Installing GIF tooling")
  (load-local-overrides '(heks-linux gif)
                        'gif-settings)
  (install-config-file! #:name (gif-config-filename)
                        #:dir (gif-config-dir)
                        #:contents (make-gif-recorder-script)
                        #:perms 493)
  (log-success s "Installed GIF tooling"))
