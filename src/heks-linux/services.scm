;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The questions a module may ask the machine about its init system and the
;; programs that live with a user's session.
;;
;; Void is the target, so runit is the default answer.  systemd stays a
;; supported answer because the package backends already serve distributions
;; that use it, and a machine that runs one of those should not need a fork of
;; this tree.  What differs between them is small and worth naming once:
;;
;; - Enabling a service at boot is a symlink into /var/service under runit and
;;   a systemctl call under systemd.  The service name is the same string in
;;   both, without the .service suffix the systemd call adds.
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
            service-name?
            service-enable-command
            user-service-manager
            power-command))

;; What the machine runs as PID 1.  A parameter, not a constant, so a machine
;; with systemd says so in its local overrides and every module follows.
(define init-system
  (make-parameter 'runit))

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

Under runit the vector is a symlink into @file{/var/service}, which is what
@command{vsv} does and what survives a reboot.  Under systemd it is
@command{systemctl enable}, with the unit suffix added here so a caller names
the service once, the way both managers spell it."
  (unless (service-name? service)
    (error "service-enable-command: not a service name:" service))
  (case (init-system)
    [(runit)
     (list "ln" "-sfn"
           (format #f "/etc/sv/~a" service)
           "/var/service/")]
    [(systemd)
     (list "systemctl" "enable" (format #f "~a.service" service))]
    [else
      (error "service-enable-command: unknown init system:" (init-system))]))

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
