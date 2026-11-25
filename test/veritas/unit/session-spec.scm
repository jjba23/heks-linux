;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux session).  The list is what every compositor
;; starts, so the tests ask it the questions both sessions rely on: the
;; desktop's own programs are there once, the dock starts under its lock, the
;; password manager follows its setting, and the agent appears only where no
;; user manager starts it.  What reads a compositor's own protocol stays out.

;;; Code:

(define-module (veritas unit session-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux session)
  #:use-module (heks-linux services)
  #:use-module (heks-linux ssh)
  #:use-module (heks-linux user-settings)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (command-starting-with prefix)
  "Return the session command that starts with @var{prefix}, or @code{#f}."
  (find (lambda (command) (string-prefix? prefix command))
        (session-startup-programs)))

(define (command-starts-with? prefix)
  "Whether a session command starts with @var{prefix}."
  (not (eq? #f (command-starting-with prefix))))

(define (command-count fragment)
  "Return how many session commands contain @var{fragment}."
  (count (lambda (command) (not (eq? #f (string-contains command fragment))))
         (session-startup-programs)))

(define session-suite
  (suite "Session Startup"
    (test "The Desktop Starts Once In Every Session"
      (assert-equal #:expect "whelk"
        #:got (command-starting-with "whelk")
        #:name "The shell is on the list")
      (assert-equal #:expect 1
        #:got (command-count "whelk")
        #:name "A shell started twice is two bars")
      (assert-true (command-starts-with? "emacs --daemon")
        #:name "The editor daemon is the session's")
      (assert-true (command-starts-with? "podman system service")
        #:name "The container service is the session's")
      (assert-true (command-starts-with? "xdg-user-dirs-update")
        #:name "The user directories are made once per session")
      (assert-true (command-starts-with? "warp-taskbar")
        #:name "The taskbar belongs to the desktop, not a compositor")
      (assert-true (command-starts-with?
                    "bash ~/.local/bin/write-gtk-dconf-settings")
        #:name "The dconf writer is shared"))

    (test "The Dock Starts Under Its Session Lock"
      (let ((start (session-dock-command)))
        (assert-true (not (eq? #f (string-contains start "flock -n ")))
          #:name "A reload must not draw a second dock")
        (assert-true (not (eq? #f (string-contains start "lambdock-session.lock")))
          #:name "The lock is the session's own")
        (assert-true (not (eq? #f (string-contains start " lambdock")))
          #:name "The dock is what the lock guards"))
      (assert-true (not (eq? #f (string-contains (session-dock-command #:wait #t)
                                                 "flock -w 2 ")))
        #:name "A restart queues for the lock the dead dock still holds")
      (assert-equal #:expect #f
        #:got (member "lambdock" (session-startup-programs))
        #:name "The bare dock command is never on the list"))

    (test "A Session Can Ask For No Dock At All"
      ;; The stacking session's bar is a taskbar with the windows on it, so a
      ;; dock beside it is a second place to click the same window.  The dock is
      ;; a keyword on the list rather than a filter at the caller, so a session
      ;; says what it wants and the list stays the one description of a
      ;; desktop.
      (assert-equal #:expect 0
        #:got (count (lambda (command)
                       (and (string? command)
                         (not (eq? #f (string-contains command "lambdock")))))
                     (session-startup-programs #:dock? #f))
        #:name "No command on the list starts the dock")
      (assert-equal #:expect 1
        #:got (count (lambda (command)
                       (and (string? command)
                         (not (eq? #f (string-contains command "lambdock")))))
                     (session-startup-programs))
        #:name "And every other session keeps it"))

    (test "The Password Manager Follows Its Setting"
      (assert-equal #:expect "keepassxc --minimized"
        #:got (parameterize ((heks-linux-password-command "keepassxc")
                             (heks-linux-password-startup-args "--minimized"))
                (session-password-startup))
        #:name "Another manager and its own quiet flag should come through")
      (assert-equal #:expect "keepassxc"
        #:got (parameterize ((heks-linux-password-command "keepassxc")
                             (heks-linux-password-startup-args ""))
                (session-password-startup))
        #:name "A manager with no quiet start should start plainly")
      (assert-true (command-starts-with? (heks-linux-password-command))
        #:name "The list starts the manager the bar's key glyph opens"))

    (test "The Agent Is The Session's Only Without A User Manager"
      (assert-true (not (eq? #f
                             (member (ssh-agent-session-command)
                                     (session-startup-programs))))
        #:name "Runit has no user manager, so the session starts the agent")
      (assert-equal #:expect (ssh-agent-session-socket)
        #:got (assoc-ref (session-environment) "SSH_AUTH_SOCK")
        #:name "and names the socket the agent listens on")
      (assert-equal #:expect #f
        #:got (parameterize ((init-system 'systemd))
                (member (ssh-agent-session-command)
                        (session-startup-programs)))
        #:name "Systemd's user manager starts it instead")
      (assert-equal #:expect #f
        #:got (parameterize ((init-system 'systemd))
                (assoc-ref (session-environment) "SSH_AUTH_SOCK"))
        #:name "and environment.d exports the socket"))

    (test "A Compositor's Own Programs Stay With It"
      (assert-equal #:expect 0
        #:got (command-count "heks-window-notify")
        #:name "Niri's event watcher is not a desktop program"))))

(define (spec)
  (veritas-run session-suite))
