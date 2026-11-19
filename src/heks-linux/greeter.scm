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
  #:export (greeter
            greeter-user
            greeter-vt
            greeter-autologin-user
            greeter-session
            greeter-packages
            greeter-command
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
compositor to draw in; tuigreet is one binary and needs neither."
  (case (greeter)
    [(gtkgreet) '("greetd" "gtkgreet" "cage")]
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

(define (greeter-command)
  "Return the command greetd runs for the chosen greeter.

cage takes the application as its argument and runs it maximized, which is
exactly what a kiosk is; gtkgreet then draws the prompt in the only window
there is.  tuigreet is started directly, with the session it offers passed as
one argument so a user who presses Enter gets the desktop and not a shell."
  (case (greeter)
    [(gtkgreet) "cage gtkgreet"]
    [(tuigreet) (format #f "tuigreet --time --remember --cmd ~s"
                        greeter-session)]
    [else (error "greeter-command: unknown greeter:" (greeter))]))

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
