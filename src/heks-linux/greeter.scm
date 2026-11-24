;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The login prompt: greetd, and the one program it starts.
;;
;; That program is @code{tuigreet}, a login box drawn out of text on a console.
;; greetd authenticates, tuigreet draws the fields and reads the keyboard, and
;; that is the whole dependency story: no GPU, no EGL, no Vulkan, no compositor
;; and no toolkit stand between a person and their own machine.  The prompt this
;; replaced was a GTK window under @command{cage}, and a machine whose graphics
;; wlroots could not drive had no prompt at all - greetd restarts a prompt that
;; ends, so the screen was the same renderer errors over and over.  A prompt
;; that draws no window cannot fail that way.
;;
;; It is keyboard-only, which is what the trade costs: there is no user list to
;; click, and the arrows and Enter do the moving.  The remembered name, the
;; asterisks over a typed password, the clock and the colours are tuigreet's own
;; settings, in a file of its own.
;;
;; The keyboard is the console keymap the kernel loaded, not the XKB layout the
;; session runs with: tuigreet draws on a virtual terminal and libxkbcommon is
;; not in the picture.  A machine whose console keymap is not the layout in
;; front of it types its password on the wrong keys.
;;
;; greetd owns the first virtual terminal, so Void's getty for it has to be
;; stopped or two programs write to one console - and a text prompt is also the
;; thing that keeps the other consoles honest: @kbd{Ctrl+Alt+F4} is a plain
;; login, with a shell, on a machine whose session will not start.  That is not
;; a second display manager; it is the getty Void installed.
;;
;; The session behind the prompt is @command{niri --session}, not
;; @command{niri-session}: the latter is a systemd wrapper, and Void has runit.
;; @code{niri --session} is what niri documents for a session manager that is
;; not systemd, and it is what a display manager on Void launches.
;;
;; Two files are rendered here.  @file{/etc/greetd/config.toml} is which
;; program runs and where; @file{/etc/tuigreet/config.toml} is what it looks
;; like.  They are rendered here rather than in the image module because a
;; machine that was installed by hand wants the same two: the image writes them
;; into the chroot, and a running Void box writes them in place.
;;
;;; Code:

(define-module (heks-linux greeter)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (heks-linux identity)
  #:export (greeter-user
            greeter-vt
            greeter-autologin-user
            greeter-sessions
            greeter-session
            greeter-session-dir
            greeter-session-filename
            greeter-session-entry
            greeter-session-entries
            greeter-packages
            greeter-command
            greeter-config
            greeter-config-path
            greetd-config
            greetd-config-path))

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

;; The sessions this tree offers, as rows of @code{(NAME COMMAND DESKTOP
;; WHAT-IT-IS)}.  The prompt lists them, so this is where they are decided: a
;; session that is not here is a session a person cannot reach with F3, however
;; well its configuration renders.
;;
;; The commands are the ones that work on runit, and that is the whole reason
;; the list is this tree's rather than the packages': niri ships
;; @file{niri.desktop} with @code{Exec=niri-session}, and @command{niri-session}
;; is a shell script that looks for a service manager to hand the session to -
;; with neither of the two it knows, it prints "No systemd or dinit detected,
;; please use niri --session instead" and exits.  A session picked from the
;; prompt would end where it started.  @code{niri --session} is niri's own flag
;; for exactly this case: it imports the environment and starts niri's D-Bus
;; services itself.
(define greeter-sessions
  '(("Heks Niri" "niri --session" "niri" "The scrollable tiling session")
    ("Heks LabWC" "labwc" "labwc" "The floating session")))

;; The session behind the prompt when nobody picks another one: the first row,
;; so the default and the list cannot disagree.
(define greeter-session
  (cadr (car greeter-sessions)))

;; Where a prompt reads the sessions from.  tuigreet runs as the greeter's
;; account, with a home of its own under @file{/var/lib}, so an entry in a
;; person's @file{~/.local/share/wayland-sessions} is an entry no prompt can
;; see: this directory is the one that answers F3.
(define greeter-session-dir
  "/usr/share/wayland-sessions")

(define (greeter-session-filename session)
  "Return the file name @var{session} is listed under.

The name is this tree's - @code{heks-niri.desktop} - rather than the one the
package would use, because the entry is not the package's: it names a command
the package does not.  A file of its own also means an upgrade cannot quietly
put the other one back; see @code{image-sessions-core-service} for the half that
takes the packages' entries away."
  (format #f "heks-~a.desktop" (caddr session)))

(define (greeter-session-entry session)
  "Return one session's @file{.desktop} file, as text.

@var{session} is a row of @code{greeter-sessions}.  @code{TryExec} is what a
display manager greys the entry out by, and @code{DesktopNames} is the name the
session announces to the portals and the toolkit, so it is the desktop's own -
@code{niri}, @code{labwc} - and not this tree's."
  (format #f "# ~a: a session the prompt lists
#
# auto-generated file, DO NOT EDIT!
#
# Read by tuigreet, which lists every .desktop file in
# /usr/share/wayland-sessions and starts the one picked with that file's own
# Exec line.  The command is the one that works on runit; see
# (heks-linux greeter) for why it is not the package's.

[Desktop Entry]
Type=Application
Name=~a
Comment=~a
Exec=~a
TryExec=~a
DesktopNames=~a
"
          heks-name
          (car session)
          (cadddr session)
          (cadr session)
          (caddr session)
          (caddr session)))

(define (greeter-session-entries)
  "Return the sessions the prompt lists, as @code{(FILENAME . CONTENTS)} pairs.

The image renders them into the payload, so the medium and the installed system
offer the same list, and the build's readiness check asks for each one by the
name this returns."
  (map (lambda (session)
         (cons (greeter-session-filename session)
               (greeter-session-entry session)))
       greeter-sessions))

;; greetd authenticates and tuigreet draws: a prompt that needs neither a
;; compositor nor a toolkit is a prompt a machine without a GPU still has.
(define greeter-packages
  '("greetd" "tuigreet"))

;; The command greetd runs for the prompt.  `--cmd' is the session behind the
;; prompt and nothing else is passed here: everything about how the prompt looks
;; lives in greeter-config, where a key tuigreet does not know is ignored instead
;; of being an option it refuses to start with.
(define greeter-command
  (format #f "tuigreet --cmd ~s" greeter-session))

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

(define greetd-config-path
  "/etc/greetd/config.toml")

(define greeter-config-path
  "/etc/tuigreet/config.toml")

(define (greeter-config)
  "Return @file{/etc/tuigreet/config.toml}, as text.

What the prompt looks like, kept out of greetd's file because it is the prompt's
own business: the clock, the greeting, the last user's name, the user list, the
asterisks, the width of the box and its colours.  tuigreet ignores a key it does
not know, so this file is a preference an older tuigreet reads the parts of it
that it can - which is why the session is not in here but on greetd's command
line.

The palette is the one the wizards are drawn with: green ink on a dark screen
with a warm title, the same colour the medium and the installer use.  An
animated backdrop is available - @code{[background] kind = \"matrix\"} or
\"doom\", with @kbd{F4} to switch it while the prompt is up - and it is off on
purpose: the machine at a login prompt is a machine that has not started
anything yet, and an animation is the one thing that would be running.

@code{battery} draws a charge indicator on a machine that has a battery and
nothing on one that does not.

There is no @code{[user_menu]} table, and its absence is the fix for a prompt
that reported an authentication failure on every boot before anybody typed
anything.  tuigreet 0.11.0 and 0.11.1 answer both a remembered name and a user
menu holding one eligible account by sending two session requests; greetd
refuses the second with \"a session is already being configured\", tuigreet
cancels the session it already had, and what is left is a cancelled
authentication and its error on the screen.  A prompt asks for one session, so
it gets one: the remembered name stays - it is the older of the two, and it is
what puts the account in the field before the first keypress - and the menu
waits for a tuigreet whose two paths cannot both run.  A machine with several
accounts types the name it wants, and the field is editable."
  (format #f "# ~a: the login prompt's own file
#
# auto-generated file, DO NOT EDIT!
#
# Read by tuigreet, which greetd starts on the first console.  Keys this tuigreet
# does not know are ignored, so the prompt stays a prompt.  The session behind it
# is greetd's, in /etc/greetd/config.toml.
#
# F2 edits the session command, F3 lists the sessions, F12 turns the machine off
# or restarts it, and F4 paints a backdrop.
#
# There is no [user_menu] table here on purpose: tuigreet 0.11.0 and 0.11.1 send
# two session requests when a remembered name and a user menu with one eligible
# account are both enabled, greetd refuses the second one, and the prompt reports
# an authentication failure on every boot because of it.  The name is remembered
# instead, which is one request.

[display]
show_time = true
time_format = \"%a %d %b %H:%M\"
custom_title = \"~a\"
greeting = \"Log in to your machine\"
battery = true

[remember]
username = true
session = true
user_session = true

[secret]
mode = \"characters\"

[layout]
width = 60
window_padding = 2
container_padding = 2
prompt_padding = 1

[theme]
container = \"black\"
border = \"green\"
text = \"white\"
title = \"yellow\"
greet = \"green\"
time = \"green\"
prompt = \"green\"
input = \"white\"
action = \"yellow\"
button = \"green\"
"
          heks-name
          heks-name))

(define (greetd-config)
  "Return @file{/etc/greetd/config.toml}, as text.

greetd reads three tables: the terminal it takes over, the session that is the
prompt, and - when a machine wants one - the session that starts before it.
The comment at the top says the file is generated because it is: the next
render replaces it."
  (format #f "# ~a: the login prompt
#
# auto-generated file, DO NOT EDIT!
#
# Rendered by heks-linux.  The prompt is tuigreet, and the session behind it is
# ~a.

[terminal]
vt = ~a

[default_session]
command = \"~a\"
user = \"~a\"
~a"
          heks-name
          greeter-session
          (greeter-vt)
          (toml-string greeter-command)
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
