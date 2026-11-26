;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The questions a module may ask the machine about its init system and the
;; programs that live with a user's session.
;;
;; Void is the target, so runit is the answer this tree renders for when there
;; is nothing to ask.  systemd stays a supported answer because this tree also
;; installs onto Debian, whose package backend and init system differ while
;; everything above them does not.  What differs between them is small and worth
;; naming once:
;;
;; - Enabling a service at boot is a symlink into the supervisor's directory
;;   under runit and a systemctl call under systemd.  The service name is the
;;   same string in both, without the .service suffix the systemd call adds.
;; - A program that must run with a user's session is a systemd user unit when
;;   there is a user manager to start it.  Runit has no per-user supervisor
;;   unless one is installed beside it, so there the session starts the program
;;   itself, and it ends when the session does.
;; - Suspending, hibernating, rebooting and shutting down are *not* different
;;   under the two.  Void runs elogind, which provides loginctl, and loginctl
;;   asks the same thing of either manager.  So the power menu stays one line
;;   of shell and does not grow an abstraction of its own.
;;
;; Nothing here starts a service: the caller renders the argv and runs it, the
;; way every other installer in this tree is handed an argument vector rather
;; than a shell line.
;;
;;; Code:

(define-module (heks-linux services)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:export (init-system
            detected-init-system
            service-name?
            service-enable-command
            service-disable-command
            user-service-manager
            power-command))

;; What the machine runs as PID 1, read from the directory the system itself
;; keeps while it is running: systemd creates @file{/run/systemd/system} at boot
;; and nothing else does, and runit's supervisor keeps its runlevel under
;; @file{/run/runit/runsvdir}.  A machine with neither - a chroot being built, a
;; container, a rootfs - reads as Void's, which is the target this tree renders
;; for when there is nothing to ask.
;;
;; The probe takes the filesystem root as an argument so the answer can be
;; produced in a test instead of read off the machine running it, and the
;; parameter below is what every caller asks: a machine with an init system
;; neither name describes still says so in its local overrides, and
;; @code{(init-system 'openrc)} there is refused by the callers that cannot
;; answer it rather than guessed at.
(define (detected-init-system root)
  "Return the init system the machine rooted at @var{root} is running.

@var{root} is empty for the machine itself; a test passes a directory of its
own.  systemd is answered first because its directory only exists while it is
PID 1, while a runit left behind by an earlier boot keeps its own."
  (cond
    [(file-exists? (string-append root "/run/systemd/system"))
     'systemd]
    [(file-exists? (string-append root "/run/runit/runsvdir"))
     'runit]
    [else 'runit]))

(define init-system
  (make-parameter (detected-init-system "")))

;; The answer above is about the machine this process runs on, which is the wrong
;; question for a renderer that writes for another one: a build renders the
;; medium for the machine it will boot on, and says so itself instead of
;; inheriting the host's answer.  @code{as-void-target} in @code{(heks-linux
;; image)} and the systemd wrapper in @code{(heks-linux image debian)} are the two
;; places that do.

(define (service-name? name)
  "Return @code{#t} when @var{name} can name an init service.

The check is a shape check: a non-empty string that does not start with a
hyphen and holds only the characters service names use.  It cannot tell you
the service exists; only enabling it can.  What it does promise is that a name
cannot leave the directory it is read under, and cannot be read as an option."
  (and (string? name)
    (> (string-length name) 0)
    (not (char=? #\- (string-ref name 0)))
    (every (lambda (character)
             (or (char-alphabetic? character)
               (char-numeric? character)
               (memv character '(#\. #\- #\_ #\@))))
           (string->list name))))

(define (user-service-manager)
  "Return what starts a program that must live with the user's session.

@code{'user-manager} when systemd is PID 1: a user unit is enabled once and the
user manager starts it at every login.  @code{'session} when runit is: there is
no per-user supervisor unless one is installed beside it, so the session itself
starts the program - in this tree, Niri's startup list - and the program ends
with the session.

A caller asks this instead of testing @code{init-system} itself, so the answer
is spelled once and every user program follows the same one."
  (case (init-system)
    [(systemd) 'user-manager]
    [(runit) 'session]
    [else
      (error "user-service-manager: unknown init system:" (init-system))]))

(define (service-enable-command service)
  "Return the argument vector that enables @var{service} at boot.

Under runit the vector is a symlink into @file{/etc/runit/runsvdir/default}, the
set the supervisor starts: that is where @file{/var/service} points on a booted
machine and what @command{vsv} writes through.  The link goes to the directory
itself because @file{/var/service} is a chain of symlinks into @file{/run}, and
a system being built in a chroot has an empty @file{/run} - linking through it
there fails with @samp{File exists} and stops the build.  Under systemd it is
@command{systemctl enable}, with the unit suffix added here so a caller names
the service once, the way both managers spell it."
  (unless (service-name? service)
    (error "service-enable-command: not a service name:" service))
  (case (init-system)
    [(runit)
     (list "ln" "-sfn"
           (format #f "/etc/sv/~a" service)
           "/etc/runit/runsvdir/default/")]
    [(systemd)
     (list "systemctl" "enable" (format #f "~a.service" service))]
    [else
      (error "service-enable-command: unknown init system:" (init-system))]))

(define (service-disable-command service)
  "Return the argument vector that stops @var{service} starting at boot.

The other half of @code{service-enable-command}, spelled in the same place for
the same reason: a program that owns a console needs the program that was there
first to let go of it.  Under runit the link is removed - @option{-f}, because a
service that was never enabled is not a failure - and under systemd the unit is
disabled."
  (unless (service-name? service)
    (error "service-disable-command: not a service name:" service))
  (case (init-system)
    [(runit)
     (list "rm" "-f" (format #f "/etc/runit/runsvdir/default/~a" service))]
    [(systemd)
     (list "systemctl" "disable" (format #f "~a.service" service))]
    [else
      (error "service-disable-command: unknown init system:" (init-system))]))

(define (power-command action)
  "Return the argument vector that performs @var{action} on this machine.

@var{action} is one of @code{suspend}, @code{hibernate}, @code{reboot} or
@code{poweroff}.  The answer is @command{loginctl} under both init systems:
Void's elogind and systemd's logind both provide it, and asking the session
manager rather than the init system is what keeps a session's own policy -
inhibitors, a pending lock - in the way of a hasty reboot."
  (case action
    [(suspend hibernate reboot poweroff)
     (list "loginctl" (symbol->string action))]
    [else
      (error "power-command: unknown action:" action)]))
