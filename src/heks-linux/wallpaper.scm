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
;; The Heks Linux wallpaper engine: one generated shell script that owns the
;; background, one Rofi picker that talks to it, and the systemd units that
;; rotate it on a schedule.
;;
;; The shape of this module is deliberate.  The compositor starts the engine as
;; a startup program, the timer runs it on a calendar, the keybindings run it by
;; hand and the picker runs it with an explicit path - one entry point, so the
;; renderer, the state file and the Wayland connection are solved once instead
;; of in four places.
;;
;; The three things the previous rotation script got wrong, and that this one
;; gets right, are worth naming because they look like small details:
;;
;;   1. It guessed that the compositor was on wayland-0, wayland-1 or
;;      wayland-2, in a chain of or-ed commands that also hid every failure.
;;      The engine reads @env{WAYLAND_DISPLAY} and then looks for the socket in
;;      @env{XDG_RUNTIME_DIR}.
;;   2. Its systemd service was @code{Type=simple} around a program that never
;;      exits, so the unit stayed active forever and the timer could never
;;      trigger it again - the wallpaper was set once per boot.  The service is
;;      now a oneshot around an engine that returns, and the renderer is
;;      detached with @code{setsid} so @code{KillMode=process} leaves it alone.
;;   3. It derived the image from the current second, so the comment that
;;      promised a wallpaper per day was describing nothing.  The engine keeps
;;      the wallpaper it applied in a state file, rotates on a daily timer and
;;      never picks the image that is already on screen.
;;
;;; Code:

(define-module (heks-linux wallpaper)
  #:declarative? #t
  #:use-module (ice-9 match)
  #:use-module (ice-9 exceptions)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (wallpapers wallpaper-catalog-dir
                       wallpaper-script-dir
                       wallpaper-script-filename
                       wallpaper-systemd-dir
                       wallpaper-service-filename
                       wallpaper-timer-filename
                       wallpaper-backend
                       wallpaper-scaling
                       wallpaper-timeout
                       wallpaper-state-dir
                       wallpaper-rotation-calendar
                       wallpaper-randomized-delay
                       wallpaper-script-command
                       mk-random-wall-cmd
                       mk-random-wall-systemd-service
                       mk-random-wall-systemd-timer
                       install-wallpaper-config))

(define s
  (scriba-auto-logger))

;; --- Base Paths & Configuration Defaults ---

(define %home-dir
  (or (getenv "HOME") "/tmp"))

;; The home of the wallpaper collection.  ~maak install-wallpaper-files clones
;; it, and %wallpaper-catalog-dir is what the gallery browses.
(define wallpaper-catalog-dir
  (make-parameter (string-append %home-dir "/.config/digital-art-dreams")))

;; Where the generated scripts land.  It has to be on @env{PATH} for the
;; keybindings and the systemd unit to find the engine, which ~/.local/bin is in
;; every Heks session.
(define wallpaper-script-dir
  (make-parameter (string-append %home-dir "/.local/bin")))

;; The engine itself: the single program that sets, restores and rotates the
;; wallpaper.  Every other wallpaper consumer - keybindings, the timer, the
;; gallery - calls it.
(define wallpaper-script-filename
  (make-parameter "heks-wallpaper"))

(define wallpaper-systemd-dir
  (make-parameter (string-append %home-dir "/.config/systemd/user")))

(define wallpaper-service-filename
  (make-parameter "heks-wallpaper.service"))

(define wallpaper-timer-filename
  (make-parameter "heks-wallpaper.timer"))

;; The renderer.  @code{auto} prefers swaybg, which scales to fill every output
;; and owns its own error reporting, and falls back to wbg; @code{swaybg} and
;; @code{wbg} pin one.  wbg is the smaller, layer-shell-only setter from the
;; Niri world (package wbg), useful when only a minimal client is wanted - it
;; covers every output in one instance and has no per-output or per-seam
;; control.
(define wallpaper-backend
  (make-parameter 'auto))

;; How the image meets the screen: @code{fill} crops, @code{fit} letterboxes,
;; @code{stretch} distorts, @code{center} and @code{tile} do what they say.
;; Passed to swaybg as -m; wbg understands @code{fill} (as its stretch flag) and
;; otherwise centres the image.
(define wallpaper-scaling
  (make-parameter "fill"))

;; How long the engine keeps trying to reach a Wayland compositor, in seconds.
;; The timer can fire before the session's compositor is listening, and the
;; systemd unit has no way to know when that happened.
(define wallpaper-timeout
  (make-parameter 20))

;; Where the engine records the wallpaper it applied, so restore can put the
;; same image back after the compositor restarts.  XDG_STATE_HOME is honoured,
;; with the documented ~/.local/state fallback.
(define wallpaper-state-dir
  (make-parameter (let ((xdg (getenv "XDG_STATE_HOME")))
                    (string-append (if (and xdg
                                            (not (string=? xdg ""))) xdg
                                       (string-append %home-dir
                                                      "/.local/state"))
                                   "/heks-linux"))))

;; When the wallpaper rotates.  The default is a daily 4am change, far enough
;; from most people's evening that the current wallpaper has been seen, and
;; early enough that it is fresh when the machine is picked up again.
(define wallpaper-rotation-calendar
  (make-parameter "*-*-* 04:00:00"))

;; A random delay added to the rotation, so a fleet of machines does not all
;; decode a six thousand pixel JPEG at the same instant.
(define wallpaper-randomized-delay
  (make-parameter "30m"))

;; --- Wallpaper Engine: palette selection ---

(define (wallpapers)
  "Return active wallpaper absolute file paths based on the running theme palette."
  (let* ((base-path (wallpaper-catalog-dir))
         (build-paths (lambda (loc files)
                        (map (lambda (f)
                               (format #f "~a/~a/~a" base-path loc f)) files)))
         (palette (heks-linux-palette)))
    (match palette
      ((or 'ef-melissa-light
           'ef-cyprus
           'ef-day
           'ef-kassio
           'everforest-light
           'gruvbox-light)
       (build-paths "wallpapers/sss"
                    '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))

      ('ef-dream (build-paths "wallpapers/sss"
                              '("paisaje-de-la-luna-en-el-anime.jpg"
                                "1362745.png" "inazuma.jpg" "diluc-tree.jpg"
                                "tempel-pink-sun.jpg")))

      ('heavy-metal (build-paths "wallpapers/sss"
                                 '("heavy-wall3.jpg" "heavy-wall2.jpg"
                                   "heavy-wall.jpg" "tempel-red-sun.jpg")))

      ((or 'solarized-light
           'doom-molokai)
       (build-paths "wallpapers"
                    '("wild-hunt.jpg")))

      ('ef-autumn (build-paths "wallpapers/sss"
                               '("0mar2ygf59je1.jpeg" "ofcoisp7abfe1.jpeg")))

      ((or 'ef-bio
           'everforest-dark
           'gruvbox-dark
           'doom-tomorrow-night
           'nord)
       (build-paths "wallpapers/sss"
                    '("some-forest.jpg" "redwood-forest.jpg")))

      ('dracula (build-paths "wallpapers/sss"
                             '("paisaje-de-la-luna-en-el-anime.jpg"
                               "dracula/Dracula.png" "dracula/Kraken.png"
                               "dracula/dracula-soft-waves-44475a.png"
                               "tempel-pink-sun.jpg")))

      ('catppuccin-latte (build-paths "wallpapers/catppuccin"
                                      '("bergen-1.png" "bergen-2.png")))

      ((or 'modus-vivendi
           'modus-vivendi-tinted
           'modus-vivendi-deuteranopia
           'modus-vivendi-tritanopia
           'kaolin-dark
           'solarized-dark)
       (build-paths "wallpapers/sss"
                    '("space/heic2002a.jpg" "space/heic2007a.jpg"
                      "space/potw2006a.jpg")))

      ((or 'modus-operandi
           'modus-operandi-deuteranopia
           'modus-operandi-tritanopia
           'doom-one-light
           'rose-pine-dawn)
       (build-paths "wallpapers"
                    '("bergen-1.jpg" "bergen-2.jpg")))
      ;; `modus-operandi-tinted` is deliberately absent from the generic
      ;; `modus-operandi` family above so it reaches the macOS wallpaper set.
      ((or 'modus-operandi-tinted)
       (build-paths "wallpapers/mac"
                    '("10-5-6k.jpg" "10-5-Server-6k.jpg"
                      "10-6-6k.jpg"
                      "10-6-Server-6k.jpg"
                      "10-10-6k.jpg"
                      "10-11-6k.jpg"
                      "10-13-6k.jpg"
                      "10-14-Day-6k.jpg")))
      ((or 'ayu-dark
           'ayu-mirage)
       (build-paths "wallpapers/space"
                    '("1.jpg" "2.jpg" "3.jpg" "4.jpg" "5.jpg")))
      ((or 'ayu-light)
       (build-paths "wallpapers/mac"
                    '("10-10-6k.jpg" "10-14-Day-6k.jpg"
                      "15-Sequoia-Sunrise.png")))
      ;; Golden Gate wears macOS's own artwork: the day set for the light
      ;; palette, the night set for the dark one.
      ('golden-gate-light (build-paths "wallpapers/mac"
                                       '("10-14-Day-6k.jpg" "10-15-Day-6k.jpg"
                                         "11-Big-Sur-Day-6k.jpg"
                                         "12-Monterey-Light.jpg"
                                         "15-Sequoia-Sunrise.png")))
      ('golden-gate-dark (build-paths "wallpapers/mac"
                                      '("10-14-Night-6k.jpg"
                                        "10-15-Night-6k.jpg"
                                        "11-Big-Sur-Night-6k.jpg"
                                        "12-Monterey-Dark.jpg")))
      ((or 'kanagawa)
       (build-paths "wallpapers"
                    '("kanagawa.jpg")))

      ((or 'catppuccin-mocha
           'doom-one
           'tokyo-night)
       (build-paths "wallpapers/catppuccin"
                    '("raiden.png" "varesa-tribe-reputation.png"
                      "moonlight-shadow.png")))

      ('rose-pine-moon (build-paths "wallpapers/sss"
                                    '("paisaje-de-la-luna-en-el-anime.jpg"
                                      "tempel-pink-sun.jpg")))

      (_ (raise-exception (make-exception-with-message (format #f
                                                        "exception occurred! unknown palette selected (~a), could not determine wallpaper set."
                                                        palette)))))))

;; --- Wallpaper Engine: script rendering ---

(define (wallpaper-home-relative path)
  "Return @var{path} with a leading home directory written as a tilde.

The generated Niri bindings and startup programs are dotfiles, and a shell
expands the tilde for them, so a path under @var{%home-dir} stays portable
between machines while anything outside it - a user who pointed
@code{wallpaper-script-dir} somewhere else - is spelled out in full."
  (if (string-prefix? %home-dir path)
      (string-append "~"
                     (substring path
                                (string-length %home-dir))) path))

(define (wallpaper-script-command)
  "Return the engine as a shell word, ready to embed in a Niri binding.

The result is the engine path with the home directory written as a tilde, so
the binding a dotfile carries is the same on every machine.  Call it where a
shell will expand the tilde, such as a Niri @code{spawn-sh}."
  (wallpaper-home-relative (format #f "~a/~a"
                                   (wallpaper-script-dir)
                                   (wallpaper-script-filename))))

(define (wallpaper-backend-name)
  "Return the configured renderer as the shell word the engine compares against.

The engine switches on this string, so an unknown value has to reach it as
@code{auto} rather than as an empty string it cannot match."
  (let ((backend (wallpaper-backend)))
    (if (memq backend
              '(auto swaybg wbg))
        (symbol->string backend) "auto")))

(define (wallpaper-printf-list lines)
  "Render @var{lines} as the arguments of one POSIX @code{printf} call.

Each line is quoted, so a wallpaper whose name holds a space, a glob or a
semicolon stays one argument.  The result is meant to sit inside a shell
function body, which is why it is indented once."
  (let ((n (length lines)))
    (if (zero? n) "\t:"
        (string-join (append (list "\tprintf '%s\\n' \\")
                             (map (lambda (i line)
                                    (format #f "\t\t\"~a\"~a" line
                                            (if (= i
                                                   (1- n)) "" " \\")))
                                  (iota n) lines)) "\n"))))

(define* (mk-random-wall-cmd walls)
  "Render the Heks Linux wallpaper engine as a POSIX shell script.

@var{walls} is the wallpaper set curated for the running palette: the engine
treats it as its rotation, and @code{all-list} reaches the whole collection
below @code{wallpaper-catalog-dir} for everything else.

The script is the one program that touches the background.  It keeps what it
applied in a state file so @code{restore} can put the same image back after the
compositor restarts, it retries until a Wayland socket answers because the
systemd unit can start before Niri is listening, and it detaches the renderer so
it can return instead of blocking the unit that started it.

@example
(display (mk-random-wall-cmd (wallpapers)))
@end example"
  (format #f
   "#!/usr/bin/env sh
# ====== Heks-Linux wallpaper engine ======
#
# auto-generated file, DO NOT EDIT!
#
# Usage: heks-wallpaper [random|next|prev|restore|set PATH|current|palette-list|all-list [DIR]|help]

set -u

CATALOG=\"~a\"
STATE_DIR=\"~a\"
STATE_FILE=\"$STATE_DIR/wallpaper\"
LOG=\"${TMPDIR:-/tmp}/heks-wallpaper.log\"
BACKEND=\"~a\"
SCALING=\"~a\"
TIMEOUT=\"~a\"

say() {
	printf '%s\\n' \"$*\"
}

warn() {
	printf 'heks-wallpaper: %s\\n' \"$*\" >&2
}

log() {
	mkdir -p \"$(dirname \"$LOG\")\" 2>/dev/null || true
	printf '%s %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"$*\" >>\"$LOG\" 2>/dev/null || true
}

usage() {
	cat <<'HEKS_USAGE'
Usage: heks-wallpaper [COMMAND]

Commands:
  random           pick a wallpaper from the palette set, never the one
                   already on screen (this is the default)
  next             the next wallpaper of the palette set
  prev             the previous wallpaper of the palette set
  restore          re-apply the wallpaper on record
  set PATH         apply an explicit wallpaper
  current          print the wallpaper on record
  palette-list     print the palette wallpapers, one per line
  all-list [DIR]   print every wallpaper below DIR, one per line
  help             print this help
HEKS_USAGE
}

# --- the palette set ---

palette_list() {
~a
}

palette_count() {
	palette_list | wc -l | tr -d ' '
}

palette_nth() {
	palette_list | sed -n \"${1}p\"
}

# 1-based index of $1 in the palette set, nothing when it is not there.  A
# while-read loop would run in a subshell and lose its counter, which is why
# this is awk.
palette_index_of() {
	palette_list | awk -v want=\"$1\" '$0 == want { print i + 1; exit } { i++ }'
}

all_list() {
	ref=\"${1:-$CATALOG}\"
	[ -d \"$ref\" ] || return 1
	find \"$ref\" -type f \\
		\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\
		-o -iname '*.webp' -o -iname '*.gif' -o -iname '*.jxl' \\) \\
		| LC_ALL=C sort
}

# --- what is on screen ---

current() {
	[ -f \"$STATE_FILE\" ] || return 1
	saved=\"\"
	read -r saved <\"$STATE_FILE\" || return 1
	[ -n \"$saved\" ] || return 1
	say \"$saved\"
}

remember() {
	mkdir -p \"$STATE_DIR\" 2>/dev/null || true
	printf '%s\\n' \"$1\" >\"$STATE_FILE\" 2>/dev/null || true
}

# --- talking to the compositor ---

# Resolve the Wayland socket instead of assuming a name.  A systemd unit starts
# before the compositor exists and a second session may well be wayland-1, so
# the display is read from the environment when it is usable and discovered in
# the runtime directory otherwise.
wayland_socket() {
	runtime=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"
	if [ -n \"${WAYLAND_DISPLAY:-}\" ] && [ -S \"$runtime/${WAYLAND_DISPLAY:-}\" ]; then
		return 0
	fi
	for sock in \"$runtime\"/wayland-[0-9]*; do
		[ -S \"$sock\" ] || continue
		WAYLAND_DISPLAY=\"${sock##*/}\"
		export WAYLAND_DISPLAY
		return 0
	done
	return 1
}

# Start a renderer in its own session.  setsid keeps it out of the way of the
# service that started it: a oneshot unit with KillMode=process signals the
# main process only, and the main process here has already exited.
spawn() {
	mkdir -p \"$(dirname \"$LOG\")\" 2>/dev/null || true
	if command -v setsid >/dev/null 2>&1; then
		setsid \"$@\" >>\"$LOG\" 2>&1 &
	else
		nohup \"$@\" >>\"$LOG\" 2>&1 &
	fi
}

render_swaybg() {
	command -v swaybg >/dev/null 2>&1 || return 127
	pkill -x swaybg >/dev/null 2>&1 || true
	sleep 0.2
	spawn swaybg -i \"$1\" -m \"$SCALING\"
	sleep 0.5
	# swaybg exits at once when it cannot connect, and lives while it decodes,
	# so survival is the cheapest probe of success available here.
	pgrep -x swaybg >/dev/null 2>&1
}

render_wbg() {
	command -v wbg >/dev/null 2>&1 || return 127
	pkill -x wbg >/dev/null 2>&1 || true
	sleep 0.2
	# wbg has a single flag: -s stretches, the default scales to fit.  One
	# instance covers every output, there is no per-output control.
	if [ \"$SCALING\" = \"fill\" ]; then
		spawn wbg -s \"$1\"
	else
		spawn wbg \"$1\"
	fi
	sleep 0.5
	pgrep -x wbg >/dev/null 2>&1
}

render() {
	case \"$BACKEND\" in
		swaybg) render_swaybg \"$1\" ;;
		wbg) render_wbg \"$1\" ;;
		*) render_swaybg \"$1\" || render_wbg \"$1\" ;;
	esac
}

apply() {
	if [ ! -f \"${1:-}\" ]; then
		warn \"no such wallpaper: ${1:-}\"
		return 1
	fi
	tries=0
	while [ \"$tries\" -lt \"$TIMEOUT\" ]; do
		tries=$((tries + 1))
		if wayland_socket && render \"$1\"; then
			remember \"$1\"
			say \"wallpaper: $1\"
			log \"applied $1\"
			return 0
		fi
		sleep 1
	done
	warn \"could not reach a Wayland compositor (see $LOG)\"
	log \"failed to apply $1\"
	return 1
}

# --- commands ---

cmd_random() {
	n=$(palette_count)
	if [ \"$n\" -eq 0 ]; then
		warn \"the palette wallpaper set is empty\"
		return 1
	fi
	# The RANDOM variable is bash-only, so the entropy comes from the one
	# place POSIX promises: /dev/urandom.
	seed=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \\n')
	case \"${seed:-}\" in
		''|*[!0-9]*) seed=$(date +%s) ;;
	esac
	pick=$((seed % n + 1))
	img=$(palette_nth \"$pick\")
	if [ \"$n\" -gt 1 ]; then
		cur=$(current 2>/dev/null || true)
		if [ -n \"${cur:-}\" ] && [ \"$img\" = \"$cur\" ]; then
			pick=$((pick % n + 1))
			img=$(palette_nth \"$pick\")
		fi
	fi
	apply \"$img\"
}

cmd_step() {
	step=\"${1:-1}\"
	n=$(palette_count)
	if [ \"$n\" -eq 0 ]; then
		warn \"the palette wallpaper set is empty\"
		return 1
	fi
	i=0
	cur=$(current 2>/dev/null || true)
	if [ -n \"${cur:-}\" ]; then
		i=$(palette_index_of \"$cur\" || true)
		case \"${i:-}\" in
			''|*[!0-9]*) i=0 ;;
		esac
	fi
	i=$((i + step))
	while [ \"$i\" -lt 1 ]; do i=$((i + n)); done
	while [ \"$i\" -gt \"$n\" ]; do i=$((i - n)); done
	apply \"$(palette_nth \"$i\")\"
}

cmd_restore() {
	cur=$(current 2>/dev/null || true)
	if [ -n \"${cur:-}\" ] && [ -f \"$cur\" ]; then
		apply \"$cur\"
	else
		cmd_random
	fi
}

main() {
	case \"${1:-random}\" in
		random) cmd_random ;;
		next) cmd_step 1 ;;
		prev) cmd_step -1 ;;
		restore) cmd_restore ;;
		set)
			if [ $# -lt 2 ]; then
				warn \"set needs a wallpaper path\"
				return 2
			fi
			apply \"$2\"
			;;
		current) current ;;
		palette-list) palette_list ;;
		all-list) all_list \"${2:-}\" ;;
		-h|--help|help) usage ;;
		*)
			warn \"unknown command: $1\"
			usage >&2
			return 2
			;;
	esac
}

main \"$@\"
"
   (wallpaper-catalog-dir)
   (wallpaper-state-dir)
   (wallpaper-backend-name)
   (wallpaper-scaling)
   (wallpaper-timeout)
   (wallpaper-printf-list walls)))

;; --- systemd units ---

(define (mk-random-wall-systemd-service script-path)
  "Render the systemd user service that rotates the wallpaper.

@var{script-path} is the absolute path of the generated engine, because a user
unit has no shell to resolve a home directory shorthand.

The unit is a oneshot on purpose.  The previous version was @code{Type=simple}
around a renderer that never exits, so the unit stayed active for the whole
session, @code{systemctl start} became a no-op and the timer could never change
the wallpaper again.  Now the engine applies one image and returns, and
@code{KillMode=process} keeps the detached renderer alive when it does - the
default @code{control-group} would kill swaybg the moment the script exited."
  (format #f "[Unit]
Description=Rotate the Heks Linux wallpaper

[Service]
Type=oneshot
ExecStart=/usr/bin/env sh ~a random
KillMode=process
" script-path))

(define (mk-random-wall-systemd-timer)
  "Return the systemd user timer that triggers the wallpaper rotation.

The schedule is a calendar entry rather than a repeat, so the wallpaper changes
once a day instead of every ten minutes, and @code{Persistent=true} makes a
machine that was switched off at the appointed hour catch up on the next boot.
"
  (format #f "[Unit]
Description=Timer to rotate the Heks Linux wallpaper

[Timer]
OnCalendar=~a
RandomizedDelaySec=~a
AccuracySec=1min
Persistent=true
Unit=~a

[Install]
WantedBy=timers.target
"
          (wallpaper-rotation-calendar)
          (wallpaper-randomized-delay)
          (wallpaper-service-filename)))

;; --- Execution/Deployment Core ---

(define (install-wallpaper-config)
  "Write the wallpaper engine and the systemd user units.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/wallpaper-settings.scm} first, so a machine
can pin a renderer or a rotation schedule without touching the module.

The engine is installed executable; it is what the compositor, the timer, the
keybindings and the gallery all run.  There is no separate picker to install any
more - the gallery page is the picker - and a Rofi wall left over from an older
install is deleted rather than left behind.

Restart the timer with
@code{systemctl --user restart heks-wallpaper.timer} after changing the
wallpaper set or the schedule."
  (log-info s "Installing wallpaper management configuration")
  (load-local-overrides '(heks-linux wallpaper)
                        'wallpaper-settings)
  (let ((script-path (format #f "~a/~a"
                             (wallpaper-script-dir)
                             (wallpaper-script-filename))))
    (install-config-file! #:name (wallpaper-script-filename)
                          #:dir (wallpaper-script-dir)
                          #:contents (mk-random-wall-cmd (wallpapers))
                          #:perms 493)

    ;; The Rofi wall that used to live beside the engine: the gallery page is the
    ;; only wallpaper picker now, and a script nobody calls is a script somebody
    ;; will eventually click.
    (let ((stale (format #f "~a/heks-wallpaper-chooser" (wallpaper-script-dir))))
      (when (file-exists? stale)
        (delete-file stale)
        (log-info s "Removed the retired Rofi wallpaper picker: ~a" stale)))

    (install-config-file! #:name (wallpaper-service-filename)
                          #:dir (wallpaper-systemd-dir)
                          #:contents (mk-random-wall-systemd-service
                                      script-path))

    (install-config-file! #:name (wallpaper-timer-filename)
                          #:dir (wallpaper-systemd-dir)
                          #:contents (mk-random-wall-systemd-timer))

    (log-success s "Installed wallpaper management configuration")))
