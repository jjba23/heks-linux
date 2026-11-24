;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Where a machine's logs go, and why that is what keeps the login prompt clean.
;;
;; runit has no journal.  A service's output goes to whichever file descriptor
;; the supervisor handed it, and the supervisor's own stdout is the console - so
;; on a machine with no syslog daemon, everything a daemon says has exactly two
;; places to go, and both of them are wrong.  A service with a @file{log/run}
;; (Void's packages all have one: @command{vlogger}, which is @code{syslog(3)})
;; sends its lines to @file{/dev/log}; with nothing listening there they are
;; thrown away, because glibc writes to the console only for a caller that asked
;; for it with @code{LOG_CONS}.  A service without one writes to the console
;; greetd is drawing the prompt on.  And everything the *kernel* prints - a
;; driver, a filesystem, and the daemons that fall back to @file{/dev/kmsg} when
;; they cannot find a syslog - is printk, which lands on the active virtual
;; terminal whatever the greeter is doing there.
;;
;; So a machine can be logged into and impossible to diagnose, and the prompt
;; can be a prompt with the kernel's idea of the last minute written through it.
;; This module is the other half of both: the syslog Void documents for runit,
;; which gives every one of those lines a file under @file{/var/log/socklog},
;; and the console loglevel, which takes the kernel's own messages off the
;; screen and leaves them in the ring buffer and in that same directory.
;;
;; What is deliberately *not* here: a log line on another console.  Void's
;; socklog configuration can mirror everything onto @file{/dev/tty12}, and a
;; machine that wants that can have it - but a login prompt that is clean
;; because the noise was moved one console over is a prompt one keystroke from
;; the noise, and @command{svlogtail} reads the same lines without leaving the
;; session.
;;
;;; Code:

(define-module (heks-linux logging)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (heks-linux identity)
  #:use-module (heks-linux services)
  #:export (logging-packages
            logging-services
            logging-directory
            logging-group
            console-loglevel
            console-sysctl-filename
            console-sysctl-path
            console-sysctl
            log-service))

;; Void's syslog, and the configuration that goes with it: @code{socklog-void}
;; is the package that carries the services, the per-facility filters under
;; @file{/var/log/socklog} and the @code{socklog} group those files belong to.
;; @code{socklog} alone is the daemon without any of that, which is a syslog
;; that writes nowhere until somebody writes the configuration by hand.
(define logging-packages
  '("socklog-void"))

;; The two services Void's documentation names.  @code{socklog-unix} is the
;; daemon on @file{/dev/log}; @code{nanoklogd} is what forwards the kernel's own
;; ring buffer to it, because glibc's @code{syslog(3)} files a kernel message
;; under @code{LOG_USER} and the @file{kernel} filter would never see it.  With
;; both, @file{/var/log/socklog/kernel} is the kernel's record and
;; @file{dmesg} is a live view of what has not been read yet rather than the
;; only copy of it.
(define logging-services
  '("socklog-unix" "nanoklogd"))

;; Where the files are.  The directory is a property of the package, and a
;; program that wants to read a log - or a message that tells a person where to
;; look - names it from here rather than spelling it a second time.
(define logging-directory
  "/var/log/socklog")

;; The group the logs are readable by, and the one a person who is expected to
;; read them is added to: the files are @code{root:socklog} with mode 2750, so
;; root reads them always and everybody else reads them by membership.
(define logging-group
  "socklog")

;; What the kernel is allowed to write on the console: emerg, alert and crit.
;; The four numbers are console loglevel, default message loglevel, minimum
;; console loglevel and default console loglevel, and the first is the one that
;; matters here: a message is printed when its level is *below* it, so 3 keeps
;; errors, warnings, notices and the driver chatter of every boot off the screen
;; and leaves them where they can be read.  A machine whose console is a
;; terminal somebody is using the machine through - this one, and a rack of
;; them - can raise it with a file of its own in the same directory.
(define console-loglevel
  (make-parameter 3))

;; Void applies every @file{/etc/sysctl.d/*.conf} in stage 1, before the
;; supervisor starts anything, so a file here is in force before greetd takes
;; the console.  The name is sorted after the distribution's own drop-ins, so a
;; machine that wants a different level overrides it with a later file rather
;; than editing this one - which the next render would overwrite anyway.
(define console-sysctl-filename
  (make-parameter "60-heks-console.conf"))

(define (console-sysctl-path)
  "Return the path the console's sysctl drop-in is installed at."
  (format #f "/etc/sysctl.d/~a" (console-sysctl-filename)))

(define (console-sysctl)
  "Return the console's sysctl drop-in, as text.

It is a drop-in rather than a line in @file{/etc/sysctl.conf} because that file
belongs to the distribution and to the person who installed the machine, while
this one file is rendered by this tree and replaced by the next render."
  (format #f "# ~a: the console belongs to the person logging in
#
# auto-generated file, DO NOT EDIT!
#
# Void applies every file in /etc/sysctl.d in stage 1, before the supervisor
# starts anything, so this is in force before greetd takes the console.
#
# The kernel prints to the active virtual terminal, which is the one greetd
# draws the login prompt on: a driver's opinion of a USB port, a filesystem's
# complaint, and every daemon that falls back to /dev/kmsg when it finds no
# syslog, all land in the middle of the prompt.
#
# A message reaches the console when its level is below the first number, so
# ~a keeps errors, warnings, notices and the boot's driver chatter off the
# screen.  Nothing is lost: the ring buffer still has it, and nanoklogd forwards
# the kernel's messages to socklog's kernel/ file.
#
# The four numbers are console loglevel, default message loglevel, minimum
# console loglevel and default console loglevel.
kernel.printk = ~a 4 1 7
"
          heks-name
          (console-loglevel)
          (console-loglevel)))

(define (log-service tag)
  "Return a @file{log/run} that sends @var{tag}'s output to syslog.

runsv starts a directory's @file{log/} service when it has a @file{run} in it,
and pipes the service's own stdout and stderr into it: this is the whole of what
a service of this tree needs to stop writing on the console.  @code{vlogger} is
Void's, the tag is the name the line will carry, and @code{daemon} is the
facility that lands in @file{/var/log/socklog/daemon} and in
@file{/var/log/socklog/messages} with everything else.

@var{tag} is checked as a service name even though every caller in this tree
passes a constant: it is interpolated into a shell line, and a name that could
carry a space or a semicolon is a service nobody wrote."
  (unless (service-name? tag)
    (error "log-service: not a service name:" tag))
  (format #f "#!/bin/sh
# ====== Heks-Linux: ~a's log ======
#
# auto-generated file, DO NOT EDIT!
#
# runsv pipes this service's output into this script, and vlogger hands it to
# the syslog daemon: without this the lines go to the console the login prompt
# is drawn on, and without a syslog daemon behind it they are thrown away.
exec vlogger -t ~a -p daemon
"
          tag tag))
