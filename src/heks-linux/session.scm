;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; What a Heks session starts before it is any one compositor.
;;
;; Niri and LabWC are two shapes of the same desktop: one scrolls and tiles, the
;; other stacks and floats.  The shell, the dock, the editor daemon, the
;; container service, the password manager, the dconf writers and the SSH agent
;; are not part of that shape - they are the desktop - so they are listed once
;; here and rendered by whichever compositor is running.
;;
;; What stays with the compositor is what reads its own protocol: Niri's
;; @code{heks-window-notify} consumes @command{niri msg event-stream}, and a
;; stacking session has no such stream to read.

;;; Code:

(define-module (heks-linux session)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux services)
  #:use-module (heks-linux ssh)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (srfi srfi-13)
  #:export (session-startup-programs
            session-environment
            session-password-startup
            session-dock-command
            session-installed-command
            session-shell-command
            session-launcher-command
            session-lock-command
            session-portals-filename
            session-portals-dir
            session-portals-conf
            session-path-filename
            session-path-dir
            session-path-conf
            install-session-config
            whelk-restart-command
            emacs-daemon-restart-command))

(define s
  (scriba-auto-logger))

(define (session-password-startup)
  "Return the command that starts the password manager with the session.

It is the machine's @code{heks-linux-password-command} - the same one the bar's
key glyph opens, so the app a click raises is the app this line started - with
@code{heks-linux-password-startup-args} after it.  Those default to 1Password's
@code{--silent}, which keeps the app in the tray instead of in front of you at
login; a manager with no such flag sets them to the empty string, and this
returns the plain command."
  (let ((args (heks-linux-password-startup-args)))
    (if (or (not args) (string-null? (string-trim-both args)))
      (heks-linux-password-command)
      (format #f "~a ~a"
              (heks-linux-password-command)
              args))))

(define* (session-dock-command #:key (wait #f))
  "Return the shell command that starts the dock under its session lock.

Lambdock paints a layer surface and keeps no single-instance lock of its own, so
a second launch draws a second dock over the first.  A compositor runs its
startup list again when its configuration is reloaded, which is why the entry
cannot simply name the program: the launch holds an exclusive @code{flock} for as
long as the dock lives, and the dock inherits the descriptor, so the kernel drops
the lock when it exits.  A reload therefore finds the lock taken and starts
nothing, while a dock that crashed - or that a keybinding killed - leaves it free
and is started again.  The lock file lives in @code{$XDG_RUNTIME_DIR}, so it is
the session and not the machine that gets one dock: it disappears at logout, and
the next session starts its own.

@var{wait} makes the launch queue for the lock for two seconds instead of failing
at once, which is what the restart keybinding wants: the dock it just killed has
not let go of the lock yet at the moment its replacement is spawned."
  (let ((lock "${XDG_RUNTIME_DIR:-/tmp/heks-linux-$USER}/lambdock-session.lock"))
    ;; The dock is a package this repository builds: a machine that never built
    ;; it - every Debian one - asks the PATH first and starts nothing, like every
    ;; other optional program the session starts.
    (format #f "command -v lambdock >/dev/null 2>&1 && exec flock ~a ~a lambdock || true"
            (if wait "-w 2" "-n")
            lock)))

(define (session-welcome-command)
  "Return the greeting the session shows when it opens."
  (format #f "fyi -i distributor-logo-symbolic ~a ~a"
          (shell-single-quote
           (G_ "Welcome to the Heks-Linux power user session"))
          (shell-single-quote
           (G_ "Enter and explore, for the cosmos of computation is yours to command."))))

;; Both binaries a keybinding restarts are the session's, not a compositor's: the
;; shell and the editor daemon are on this list, and a second session with the
;; same chords needs the same two commands rather than a copy of them.
(define (whelk-restart-command)
  "Return the shell command that (re)starts the shell from a keybinding.

The shell is a GApplication, so @code{--quit} is a message to the instance that
is running and the answer to it is asynchronous: the name is still taken the
moment the command returns, and a launch straight afterwards would be forwarded
to the instance on its way out - leaving the desktop with no bar at all.  The
wait is bounded, because a shell that will not quit should cost the keypress
rather than the session, and the start that follows is unconditional: pressed
with no shell running, @code{--quit} answers that nothing was running and this
brings one back."
  (string-append "whelk --quit || true; "
                 "timeout 3 sh -c 'while pgrep -x whelk >/dev/null; do sleep 0.1; done'; "
                 "whelk"))

(define (emacs-daemon-restart-command)
  "Return the shell command that (re)starts the editor daemon.

@code{kill-emacs} rather than a signal, because the daemon then takes its own
server socket down and leaves nothing behind for the next start to trip over;
the signal is the fallback for a daemon too wedged to answer
@command{emacsclient} at all.  What it starts is the daemon the session starts,
@code{emacs --daemon}, so the process a keypress brings back is the one the
bridge and the palette picker were talking to before it.

A restart is a restart: the frames and the unsaved buffers the daemon held go
with it."
  (string-append "emacsclient --eval '(kill-emacs)' >/dev/null 2>&1"
                 " || pkill -f 'emacs --daemon' || true; "
                 "sleep 0.5; emacs --daemon"))

(define (session-installed-command command)
  "Return @var{command} as a shell line that runs only when its program is here.

A session starts a list of programs, and most of the list is optional: a machine
that never installed the editor's daemon, the container service or a password
manager has nothing to start, and a startup line whose program is missing is an
error in the session's log at every login - which is why a machine somebody else
configured reads as a machine that is broken.  So the first word of the line is
asked for on the PATH first, and a machine without it starts nothing and says
nothing.

The program is the first word rather than a name beside the line, because the
line is what a machine writes in its own settings: one string, one program, no
second spelling to keep in step."
  (let* ((words (string-tokenize command))
         (program (if (pair? words) (car words) command))
         ;; A single-quoted shell string cannot hold a single quote, and the
         ;; lines here do: the welcome message is one, quoted argument per
         ;; sentence.  `'\''` closes the string, escapes the quote and opens it
         ;; again - the one spelling that works inside single quotes.
         (quoted (string-join (string-split command #\') "'\\''")))
    (format #f "sh -c 'command -v ~a >/dev/null 2>&1 && exec ~a'"
            program quoted)))

(define (session-shell-command)
  "Return the command that starts the session's shell.

whelk is this tree's own shell - the bar, the launcher, the notifications, the
clipboard history and the lock screen in one program - and a machine that has it
gets it.  A machine that does not has Waybar, which both distributions carry and
whose configuration this tree renders from the same palette: a bar is what a
session opens its windows from, so the fallback is a bar rather than nothing."
  "sh -c 'if command -v whelk >/dev/null 2>&1; then exec whelk; fi; exec waybar'")

(define (session-launcher-command)
  "Return the command the session's launcher key runs.

The same choice as the shell: whelk's launcher is the one this palette was drawn
for, and Rofi - which both distributions carry - is the launcher a machine
without whelk opens.  Rofi speaks X11 up to 1.7 and Wayland from 2.0, so the
session also starts @command{xwayland-satellite} when it is installed: without
one of the two a Debian 13 machine has a keybinding that does nothing."
  "sh -c 'if command -v whelk >/dev/null 2>&1; then exec whelk --launcher; fi; exec rofi -show drun'")

(define (session-lock-command)
  "Return the command the session's lock key runs.

whelk locks every output itself; a machine without it has @command{swaylock}."
  "sh -c 'if command -v whelk >/dev/null 2>&1; then exec whelk --lock; fi; exec swaylock -f'")

(define (session-portals-filename)
  "Return the name of the file the portal reads its back ends from."
  "niri-portals.conf")

(define session-portals-dir
  (make-parameter (format #f "~a/.config/xdg-desktop-portal"
                          (or (getenv "HOME") "/tmp"))))

(define (session-portals-conf)
  "Return @file{~/.config/xdg-desktop-portal/niri-portals.conf}.

The portal is how a Wayland session answers a screenshot, a file chooser or a
screencast, and the answer is a choice of back end per interface.  GNOME's back
end is the wrong one under Niri: it is written for a GNOME session, and on Debian
13 it segfaults on the first question - taking every client waiting on it with
it, a bar among them.  GTK's back end is the one that works on a compositor with
no desktop environment around it, and the secret service is gnome-keyring's,
which is the one a session with no GNOME still has.

A machine that wants another back end names it here: this file is the portal's,
and it is the only place the choice is made."
  "[preferred]
# The back end every interface uses unless one below names another: GTK's,
# which wants a portal host and not a desktop environment.
default=gtk
# The secret service is gnome-keyring's: the GTK back end has none of its own.
org.freedesktop.impl.portal.Secret=gnome-keyring
# Screenshots and screencasts go through the compositor's own interface, which
# Niri implements.
org.freedesktop.impl.portal.ScreenCast=gnome
org.freedesktop.impl.portal.Screenshot=gnome
")

(define (session-path-filename)
  "Return the name of the environment file that puts the session's PATH right."
  "10-heks-path.conf")

(define session-path-dir
  (make-parameter (format #f "~a/.config/environment.d"
                          (or (getenv "HOME") "/tmp"))))

(define (session-path-conf)
  "Return @file{~/.config/environment.d/10-heks-path.conf}.

A session started by greetd inherits the environment the login put there, which
on a Debian machine is the distribution's PATH and nothing else: the programs
this tree installs under @file{~/.local/bin} - the session menu, the wallpaper
engine, the palette picker - are then not on it, and a bar item that runs one
answers \"no such file\" while the file is right there.  A program installed with
@command{cargo install} lands in the second directory, and Rofi's X11 fallback is
built from source on a distribution that has no package for it.

environment.d is read by the user manager and by the session, so this is the one
file both of them see; a machine that needs a third directory adds a file rather
than editing this one."
  "PATH=${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}
")

(define (install-session-config)
  "Write the two session-wide files: the portal's back ends, and the PATH.

They are configuration of the session rather than of any one surface, which is
why they live here: the portal answers for every client in it, and the PATH is
what makes the programs under @file{~/.local/bin} reachable from a keybinding, a
bar item and a terminal alike."
  (log-info s "Installing the session's portal and PATH configuration")
  (install-config-file! #:name (session-portals-filename)
                        #:dir (session-portals-dir)
                        #:contents (session-portals-conf))
  (install-config-file! #:name (session-path-filename)
                        #:dir (session-path-dir)
                        #:contents (session-path-conf))
  (log-success s "Installed the session's portal and PATH configuration"))

(define* (session-startup-programs #:key (dock? #t))
  "Return the commands every Heks session starts.

The order is the desktop's: the shell that draws the bar and owns
notifications, the dock, then the programs a machine configured - the editor
daemon, the container service, a password manager - and the one-shot work: user
directories, the dconf writers, the welcome message.  A compositor appends what
it alone can start; it does not repeat these.

Everything optional is started only when its program is installed: see
@code{session-installed-command}.  That is what makes one list right on a
machine this tree assembled and on one somebody installed a distribution onto -
the second has no editor daemon, no container service and no Cloudflare client,
and says nothing about any of them at login.

@var{dock?} is the one part of the list a session leaves out: the floating
session's bar is a taskbar with the desktop's windows on it, and a dock beside it
is a second place to click the same window."
  (append
   (list (session-shell-command))
   (if dock? (list (session-dock-command)) '())
   ;; X11 in a Wayland session: Debian 13's Rofi is an X11 program, and Niri has
   ;; no X server of its own - the satellite is the whole of what makes one.
   (list (session-installed-command "xwayland-satellite"))
   (map session-installed-command (heks-linux-session-startups))
   (list (session-installed-command (session-password-startup))
         (session-installed-command (session-welcome-command))
         "xdg-user-dirs-update"
         "bash ~/.local/bin/write-gtk-dconf-settings"
         "bash ~/.local/bin/write-heks-linux-dconf-settings")
   ;; Runit has no per-user supervisor, so the session is the agent's manager.
   (if (eq? 'session (user-service-manager))
     (list (ssh-agent-session-command))
     '())))

(define (session-environment)
  "Return the environment variables a Heks session exports.

The agent's socket is the one variable the session has to name: a user manager
expands the environment file on systemd, and a session that starts the agent
itself (runit) has to tell its programs where it listens."
  (if (eq? 'session (user-service-manager))
    (list (cons "SSH_AUTH_SOCK" (ssh-agent-session-socket)))
    '()))

;;; session.scm ends here
