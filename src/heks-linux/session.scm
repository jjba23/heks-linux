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
  #:use-module (srfi srfi-13)
  #:export (session-startup-programs
            session-environment
            session-password-startup
            session-dock-command))

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
    (format #f "flock ~a ~a lambdock || true"
            (if wait "-w 2" "-n")
            lock)))

(define (session-welcome-command)
  "Return the greeting the session shows when it opens."
  (format #f "fyi -i distributor-logo-symbolic ~a ~a"
          (shell-single-quote
           (G_ "Welcome to the Heks-Linux power user session"))
          (shell-single-quote
           (G_ "Enter and explore, for the cosmos of computation is yours to command."))))

(define (session-startup-programs)
  "Return the commands every Heks session starts.

The order is the desktop's: the shell that draws the bar and owns
notifications, the dock, the editor daemon and the container service, then the
one-shot work - user directories, the dconf writers, the welcome message - and
the applications that sit in the tray.  A compositor appends what it alone can
start; it does not repeat these."
  (append
   (list "whelk"
         (session-dock-command)
         "emacs --daemon"
         "podman system service --time=0 unix:///tmp/podman.sock"
         "xdg-user-dirs-update"
         "sudo warp-svc"
         "warp-taskbar"
         (session-password-startup)
         (session-welcome-command)
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
