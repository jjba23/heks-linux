;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The login prompt: greetd, and the few packages it needs to show a face.
;;
;; The choice is @code{gtkgreet} by default, and it is the smallest greeter
;; that is still usable with a mouse.  It is a GTK3 program that draws one
;; window - the user list, a password field, the buttons - and it is run by
;; @command{cage}, a kiosk compositor whose whole job is to show a single
;; application full-screen.  That is the dependency story: greetd, gtkgreet and
;; cage, and GTK3 arrives as gtkgreet's own dependency (gtkgreet's Void package
;; declares greetd and nothing else).  There is no desktop session behind the
;; prompt, no librsvg theme engine, no Qt, and no compositor that also tries to
;; be a window manager.
;;
;; @code{tuigreet} is the other value, and it exists for the machine that has
;; no GPU to draw on: a terminal greeter, one binary, no GTK, no compositor.
;; It is keyboard-only, which is why it is not the default - a mouse is the one
;; input every machine has and the one a login prompt should not require.
;;
;; It is also the fallback, and that is the second thing this module owns.
;; greetd starts the prompt again whenever it ends, so a compositor that cannot
;; draw on this machine's graphics - no EGL, no Vulkan, a half-driven AMD or a
;; virtual card without acceleration - is a screen of the same renderer errors,
;; over and over, with no way to log in.  The command in @file{config.toml} is
;; therefore not @command{cage} but @file{heks-greeter}, a small script: it lets
;; wlroots draw on the CPU, times the run, and after the third prompt that died
;; before it drew anything it starts @command{tuigreet} instead.  tuigreet is
;; part of the gtkgreet package list for that reason - the escape hatch has to
;; be on the machine before it is needed.
;;
;; The script also hands the prompt the machine's keyboard, from
;; @code{heks-linux-keyboard-layout} and @code{heks-linux-keyboard-options}: a
;; login prompt is where a password is typed, and a prompt typing on a layout
;; nobody chose is a prompt that says the right password is wrong.
;;
;; The session behind the prompt is @command{niri --session}, not
;; @command{niri-session}: the latter is a systemd wrapper, and Void has runit.
;; @code{niri --session} is what niri documents for a session manager that is
;; not systemd, and it is what a display manager on Void launches.
;;
;; The file this module renders is @file{/etc/greetd/config.toml}.  It is
;; rendered here rather than in the image module because a machine that was
;; installed by hand wants the same file: the image writes it into the chroot,
;; and a running Void box writes it in place.
;;
;;; Code:

(define-module (heks-linux greeter)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux user-settings)
  #:export (greeter
            greeter-user
            greeter-vt
            greeter-autologin-user
            greeter-session
            greeter-packages
            greeter-command
            greeter-script
            greeter-script-path
            greetd-config
            greetd-config-path))

;; Which greeter greetd starts: a GTK window under cage, or a terminal.
(define greeter
  (make-parameter 'gtkgreet))

;; The account greetd runs the greeter as.  Void's greetd package creates
;; @code{_greeter} with the video group and a home under @file{/var/lib}, so
;; this is the name that already exists on the machine.
(define greeter-user
  (make-parameter "_greeter"))

;; The virtual terminal greetd takes over.  One, because the greeter is the
;; first thing the machine shows and the kernel's own console is behind it.
(define greeter-vt
  (make-parameter 1))

;; A user to log in without asking, or @code{#f}.  A live image sets it so the
;; desktop is on screen when the medium finishes booting; an installed machine
;; leaves it off and gets the prompt.
(define greeter-autologin-user
  (make-parameter #f))

;; The session behind the prompt.  `--session' is niri's own flag for a
;; session manager that is not systemd: it imports the environment and starts
;; niri's D-Bus services, which a bare `niri' on runit does not.
(define greeter-session
  "niri --session")

(define (greeter-packages)
  "Return the packages the chosen greeter needs from xbps.

gtkgreet's own Void package depends on greetd, and cage is what gives it a
compositor to draw in; tuigreet is there because it is what a compositor that
cannot draw falls back to, and a machine cannot fetch its escape hatch after the
graphical prompt has taken the console.  tuigreet is one binary and needs
neither."
  (case (greeter)
    [(gtkgreet) '("greetd" "gtkgreet" "cage" "tuigreet")]
    [(tuigreet) '("greetd" "tuigreet")]
    [else (error "greeter-packages: unknown greeter:" (greeter))]))

(define (toml-string text)
  "Return @var{text} as a TOML basic string body.

TOML escapes a backslash and a double quote with a backslash.  A command line
that carries no quotes at all is the common case, and this keeps the
@code{tuigreet} one - which passes the session as one argument - readable."
  (string-join (map (lambda (character)
                      (if (memv character '(#\\ #\"))
                        (string #\\ character)
                        (string character)))
                    (string->list text))
               ""))

(define (shell-word text)
  "Return @var{text} as one single-quoted shell word.

The keyboard layout and the options below are the machine's settings - strings
somebody typed into a Scheme file - and they land in a shell assignment.  A
shell string built out of data is a command looking for somewhere to run, so the
quotes are put on here instead of being assumed."
  (string-append "'"
                 (string-join (string-split text #\') "'\\''")
                 "'"))

(define (tuigreet-command)
  "Return the command line that starts the terminal prompt.

One line, named twice: it is the greeter for a machine that has no GPU at all,
and it is what the graphical prompt falls back to when the compositor cannot
draw.  A prompt that offers one desktop and no shell is a prompt a person can
get through, so the session is passed as one argument."
  (format #f "tuigreet --time --remember --cmd ~s" greeter-session))

;; The program greetd runs when the greeter is the graphical one: a script
;; rather than a command line, because it holds the fallback.  The path is where
;; the image's payload puts it, which is why greetd reads this name and not one
;; on the PATH.
(define greeter-script-path
  "/usr/local/lib/heks-linux/heks-greeter")

(define (greeter-command)
  "Return the command greetd runs for the chosen greeter.

gtkgreet has no command line of its own here: greetd runs
@code{greeter-script-path}, which starts cage and answers a compositor that
cannot draw.  tuigreet is started directly - there is nothing behind a prompt
that is already text on a console."
  (case (greeter)
    [(gtkgreet) greeter-script-path]
    [(tuigreet) (tuigreet-command)]
    [else (error "greeter-command: unknown greeter:" (greeter))]))

(define (greeter-script)
  "Return the program greetd runs as the graphical prompt, as text.

It exists for one failure.  cage needs a renderer - EGL, Vulkan, or pixman - and
a machine whose graphics wlroots cannot draw on is a compositor that exits
before it shows a window.  greetd starts it again, so the screen is the same
renderer errors over and over and nobody can log in.  The script times each run
instead: one that lasted a few seconds is a prompt that drew, and it starts the
count over; one that died at once is a failure, and the third in a row is
answered with tuigreet.  The count lives in the greeter's runtime directory,
which is empty at boot, so a reboot tries the graphical prompt again.

@code{WLR_RENDERER_ALLOW_SOFTWARE} is the other half of the answer: wlroots draws
with pixman only when it is told it may, and a slow prompt beats a screen with
no prompt on it."
  (format #f "#!/bin/sh
# ====== Heks-Linux login prompt ======
#
# auto-generated file, DO NOT EDIT!
#
# greetd runs this: gtkgreet inside cage.  A machine whose graphics cage cannot
# drive is a compositor that dies at once, and greetd starting it again is the
# same renderer errors over and over - so after three fast failures the prompt
# is tuigreet, which needs no GPU to draw a line of text.  Write the limit to
# the count file to stay on the terminal prompt; delete it to try the other one.

set -u

limit=3
quiet=10

runtime=${XDG_RUNTIME_DIR:-${HOME:-/tmp}}
state=$runtime/heks-greeter-failures

failures=0
if [ -r \"$state\" ]; then
    read -r failures <\"$state\" || failures=0
fi
case $failures in
    '' | *[!0-9]*) failures=0 ;;
esac

# The end of the loop: nothing has drawn, and a prompt that needs no GPU is a
# prompt.  exec, because this session is the terminal greeter and nothing else.
# A tuigreet that is not on the machine is no fallback at all: the compositor
# stays the answer, which is where this prompt started.
if [ \"$failures\" -ge \"$limit\" ] && command -v tuigreet >/dev/null 2>&1; then
    exec ~a
fi

# wlroots draws with a software renderer only when it is told it may, and on a
# machine with half a driver that is the difference between a slow login box and
# a screen of errors.
WLR_RENDERER_ALLOW_SOFTWARE=1
export WLR_RENDERER_ALLOW_SOFTWARE

# The keyboard this machine was set up with, in the variables libxkbcommon reads.
# Without them the prompt types on whatever xkbcommon defaults to, and a password
# typed on a layout that is not the one in front of you is a password the prompt
# says is wrong.
XKB_DEFAULT_LAYOUT=~a
XKB_DEFAULT_OPTIONS=~a
export XKB_DEFAULT_LAYOUT XKB_DEFAULT_OPTIONS

started=$(date +%s)
cage gtkgreet
status=$?

if [ $(( $(date +%s) - started )) -ge \"$quiet\" ]; then
    failures=0
else
    failures=$((failures + 1))
fi
printf '%s\\n' \"$failures\" >\"$state\" 2>/dev/null || true
exit $status
"
          (tuigreet-command)
          (shell-word (heks-linux-keyboard-layout))
          (shell-word (string-join (heks-linux-keyboard-options) ","))))

(define greetd-config-path
  "/etc/greetd/config.toml")

(define (greetd-config)
  "Return @file{/etc/greetd/config.toml} for the chosen greeter, as text.

greetd reads three tables: the terminal it takes over, the session that is the
prompt, and - when a machine wants one - the session that starts before it.
The comment at the top says the file is generated because it is: the next
render replaces it."
  (format #f "# Heks Linux: the login prompt
#
# auto-generated file, DO NOT EDIT!
#
# Rendered by heks-linux.  The greeter is ~a; the session it starts is
# ~a.

[terminal]
vt = ~a

[default_session]
command = \"~a\"
user = \"~a\"
~a"
          (greeter)
          greeter-session
          (greeter-vt)
          (toml-string (greeter-command))
          (toml-string (greeter-user))
          (if (greeter-autologin-user)
            (format #f "
# The session that starts before the prompt: a live image logs its own user
# in, and the greeter is what a person sees when that session ends.
[initial_session]
command = \"~a\"
user = \"~a\"
"
                    (toml-string greeter-session)
                    (toml-string (greeter-autologin-user)))
            "")))
