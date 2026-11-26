;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux services).
;;
;; The module answers the questions a module asks the init system, and the tests
;; ask them under both: how a service is enabled and disabled at boot, what
;; starts a program that has to live with a user's session, and how the machine
;; is asked to suspend.  The last answer having one value is the point - a power
;; menu that changes with the init system is a menu that has to be ported, and
;; this one does not.

;;; Code:

(define-module (veritas unit services-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux services)
  #:use-module (ice-9 format)
  #:export (spec))

;; A directory every detection case gets of its own.  The probe reads a
;; filesystem *root* rather than the live one, so the answer is produced here
;; instead of read from whatever machine the suite happens to run on.
(define scratch-counter 0)

(define (make-directory path)
  "Create @var{path} and its parents when they are not there already."
  (unless (file-exists? path)
    (make-directory (dirname path))
    (catch 'system-error (lambda () (mkdir path #o700)) (lambda (key . args) #f))))

(define (scratch-root)
  "Return a fresh empty directory to play a machine's @file{/run} in."
  (set! scratch-counter (+ scratch-counter 1))
  (let ((base (format #f "/tmp/heks-services-spec-~a-~a"
                      (getpid)
                      scratch-counter)))
    (make-directory base)
    base))

(define (touch path)
  "Create an empty @var{path}."
  (call-with-output-file path (lambda (port) (display "" port))))

(define (enable-cases)
  (suite "Enabling A Service"
    (test "Void Links The Service Into The Supervisor's Directory"
      (assert-equal #:expect
        '("ln" "-sfn" "/etc/sv/guix-daemon" "/etc/runit/runsvdir/default/")
        #:got (parameterize ((init-system 'runit))
                (service-enable-command "guix-daemon"))
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

(define (disable-cases)
  (suite "Disabling A Service"
    (test "Void Removes The Link That Starts It"
      (assert-equal #:expect
        '("rm" "-f" "/etc/runit/runsvdir/default/agetty-tty1")
        #:got (parameterize ((init-system 'runit))
                (service-disable-command "agetty-tty1"))
        #:name "-f, because a service that was never enabled is not a failure"))
    (test "Systemd Disables The Same Name With Its Own Tool"
      (assert-equal #:expect
        '("systemctl" "disable" "agetty-tty1.service")
        #:got (parameterize ((init-system 'systemd))
                (service-disable-command "agetty-tty1"))
        #:name "The unit suffix is added once, by the seam, not by every caller"))
    (test "An Unknown Init System Is Refused"
      (assert-error (lambda ()
                      (parameterize ((init-system 'openrc))
                        (service-disable-command "agetty-tty1")))
        #:name "A machine with a manager this tree cannot answer is not guessed at"))
    (test "A Name That Is Not A Service Is Refused"
      (assert-error (lambda () (service-disable-command "../shadow"))
        #:name "The same shape check guards the directory a removal is given"))))

(define (detection-cases)
  (suite "Finding Out Which Init System This Is"
    ;; The default answer used to be runit, because Void was the only machine
    ;; this tree ran on: a Debian machine inherited it and rendered a runit
    ;; symlink nothing would ever follow.  The default is now what the machine
    ;; itself says, read from the two directories the two systems own.
    (test "A Machine With Systemd Is Found By Its Runtime Directory"
      (let ((root (scratch-root)))
        (make-directory (format #f "~a/run/systemd" root))
        (touch (format #f "~a/run/systemd/system" root))
        (assert-equal #:expect 'systemd
          #:got (detected-init-system root)
          #:name "The directory systemctl creates at boot"))
      (let ((root (scratch-root)))
        ;; A machine with both directories is a machine that ran both at some
        ;; point; systemd wins because its directory only exists while it is
        ;; running as PID 1.
        (make-directory (format #f "~a/run/systemd" root))
        (touch (format #f "~a/run/systemd/system" root))
        (make-directory (format #f "~a/run/runit" root))
        (touch (format #f "~a/run/runit/runsvdir" root))
        (assert-equal #:expect 'systemd
          #:got (detected-init-system root)
          #:name "And it wins over a runit left behind by an earlier boot")))
    (test "A Machine With Runit Is Found By Its Supervisor Directory"
      (let ((root (scratch-root)))
        (make-directory (format #f "~a/run/runit" root))
        (touch (format #f "~a/run/runit/runsvdir" root))
        (assert-equal #:expect 'runit
          #:got (detected-init-system root)
          #:name "runsvdir is where the supervisor keeps its runlevel")))
    (test "A Machine With Neither Reads As Void"
      ;; A chroot being built from a Void medium has an empty /run, and so does
      ;; a container: the target's answer is the one that renders a service the
      ;; installed machine can follow.
      (assert-equal #:expect 'runit
        #:got (detected-init-system (scratch-root))
        #:name "Nothing to read is not a reason to fail a render"))
    (test "The Default This Machine Loaded Is One It Can Answer"
      (assert-true (if (memv (init-system) '(runit systemd)) #t #f)
        #:name "A loaded parameter is either of the two answers"))))

(define (spec)
  ;; The suite describes the target machine, which runs runit.  `init-system` is
  ;; read from the machine the code is loaded on, so a suite run on a systemd
  ;; host would otherwise test the other rendering: pinning it here is what makes
  ;; these cases a fact about this tree rather than about the host.
  (parameterize ((init-system 'runit))
    (veritas-run (enable-cases) (disable-cases) (user-service-cases)
      (power-cases) (detection-cases))))
