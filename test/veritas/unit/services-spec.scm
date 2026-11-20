;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux services).
;;
;; The module answers the questions a module asks the init system, and the tests
;; ask them under both: how a service is enabled at boot, what starts a program
;; that has to live with a user's session, and how the machine is asked to
;; suspend.  The last answer having one value is the point - a power menu that
;; changes with the init system is a menu that has to be ported, and this one
;; does not.

;;; Code:

(define-module (veritas unit services-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux services)
  #:export (spec))

(define (enable-cases)
  (suite "Enabling A Service"
    (test "Void Links The Service Into The Supervisor's Directory"
      (assert-equal #:expect
        '("ln" "-sfn" "/etc/sv/guix-daemon" "/etc/runit/runsvdir/default/")
        #:got (service-enable-command "guix-daemon")
        #:name "A runit service is a symlink, and the name is one argument")
      (assert-equal #:expect
        '("ln" "-sfn" "/etc/sv/guix-daemon" "/etc/runit/runsvdir/default/")
        #:got (parameterize ((init-system 'runit))
                (service-enable-command "guix-daemon"))
        #:name
        "Not /var/service: that is a chain of symlinks into /run, and a chroot being built has an empty /run, so the link would fail with 'File exists'"))
    (test "Systemd Enables The Same Name With Its Own Tool"
      (assert-equal #:expect
        '("systemctl" "enable" "guix-daemon.service")
        #:got (parameterize ((init-system 'systemd))
                (service-enable-command "guix-daemon"))
        #:name "The unit suffix is added once, by the seam, not by every caller"))
    (test "An Unknown Init System Is Refused"
      (assert-error (lambda ()
                      (parameterize ((init-system 'openrc))
                        (service-enable-command "guix-daemon")))
        #:name "A machine with a manager this tree cannot answer is not guessed at"))
    (test "A Service Name Cannot Become A Path Or An Option"
      (assert-equal #:expect #f
        #:got (service-name? "../../etc/shadow")
        #:name "A name may not climb out of /etc/sv")
      (assert-equal #:expect #f
        #:got (service-name? "-rf")
        #:name "A name may not look like an option")
      (assert-equal #:expect #f
        #:got (service-name? "two words")
        #:name "A name has no whitespace")
      (assert-error (lambda () (service-enable-command "a/b"))
        #:name "And the command refuses one before it reaches a vector"))))

(define (user-service-cases)
  (suite "What Starts A Per-User Program"
    (test "Runit Leaves It To The Session"
      (assert-equal #:expect 'session
        #:got (user-service-manager)
        #:name "There is no per-user supervisor, so the session starts it"))
    (test "Systemd Has A User Manager"
      (assert-equal #:expect 'user-manager
        #:got (parameterize ((init-system 'systemd))
                (user-service-manager))
        #:name "A user unit is enabled once and started at every login"))
    (test "An Unknown Init System Is Refused"
      (assert-error (lambda ()
                      (parameterize ((init-system 'openrc))
                        (user-service-manager)))
        #:name "A manager this tree cannot answer for is not guessed at"))))

(define (power-cases)
  (suite "Asking The Session Manager To Power Off"
    (test "The Machine Is Asked Through logind Under Either Init"
      (assert-equal #:expect '("loginctl" "suspend")
        #:got (power-command 'suspend)
        #:name "Void's elogind answers loginctl")
      (assert-equal #:expect '("loginctl" "poweroff")
        #:got (parameterize ((init-system 'systemd))
                (power-command 'poweroff))
        #:name "And so does systemd's logind, without a different code path"))
    (test "Every Action Has An Answer"
      (assert-equal #:expect '("loginctl" "hibernate")
        #:got (power-command 'hibernate)
        #:name "Hibernate is a logind verb")
      (assert-equal #:expect '("loginctl" "reboot")
        #:got (power-command 'reboot)
        #:name "So is reboot"))
    (test "An Action That Is Not A Session Verb Is Refused"
      (assert-error (lambda () (power-command 'sleep))
        #:name "A misspelled action stops here rather than at a prompt"))))

(define (spec)
  (veritas-run (enable-cases) (user-service-cases) (power-cases)))
