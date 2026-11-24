;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux greeter).
;;
;; There is one prompt and it is a terminal program: the tests say so about the
;; package list, about the command greetd runs, and about the two files greetd
;; and tuigreet read - the session, and the way the prompt looks.  Both files are
;; TOML, so the tests look for the tables the programs read rather than for a
;; substring of a template.

;;; Code:

(define-module (veritas unit greeter-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux greeter)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? text line)
  "Return #t when @var{text} has @var{line} in it."
  (not (eq? #f (string-contains text line))))

(define (package-cases)
  (suite "The Greeter's Packages"
    (test "The Prompt Is A Terminal Program And The Daemon That Runs It"
      (assert-equal #:expect '("greetd" "tuigreet")
        #:got greeter-packages
        #:name "No compositor and no toolkit: a machine without a GPU can still be logged into"))
    (test "Greetd Starts The Terminal Prompt On The Session"
      (assert-equal #:expect "tuigreet --cmd \"niri --session\""
        #:got greeter-command
        #:name "The session is passed as one argument, so a name with a space stays one name"))))

(define (prompt-cases)
  (suite "The Prompt's Own File"
    (test "Tuigreet Reads It Where The Package Looks"
      (assert-equal #:expect "/etc/tuigreet/config.toml"
        #:got greeter-config-path
        #:name "The path is the program's, not this tree's"))
    (test "The Prompt Says Where It Is And What Time It Is"
      (let ((config (greeter-config)))
        (assert-true (contains? config "[display]")
          #:name "There is a display table")
        (assert-true (contains? config "show_time = true")
          #:name "The clock is on")
        (assert-true (contains? config "time_format =")
          #:name "In a format that fits a console")
        (assert-true (contains? config "custom_title = \"Heks GNU/Linux\"")
          #:name "The box is named after the system it logs into")
        (assert-true (contains? config "greeting = ")
          #:name "And greets the person typing")
        (assert-true (contains? config "battery = true")
          #:name "A laptop is told its charge, and a machine without one draws nothing")))
    (test "It Remembers What Was Typed Last Time"
      (let ((config (greeter-config)))
        (assert-true (contains? config "[remember]")
          #:name "There is a table for what is remembered")
        (assert-true (contains? config "username = true")
          #:name "The last user is in the field before the first keypress")
        (assert-true (contains? config "session = true")
          #:name "And the last session chosen with F2 survives to the next boot")
        (assert-true (contains? config "user_session = true")
          #:name "Remembered per user, which is what a machine with two people wants")))
    (test "The Prompt Asks For One Session, And Only Once"
      ;; tuigreet 0.11.0 and 0.11.1 send two session requests when a remembered
      ;; name and a user menu holding one eligible account are both enabled:
      ;; greetd refuses the second with "a session is already being configured",
      ;; tuigreet cancels the session it already had, and the prompt reports an
      ;; authentication failure on every boot before anybody types anything.
      ;; One request is the fix, so the user menu is not enabled here.
      (let ((config (greeter-config)))
        (assert-true (not (contains? config "\n[user_menu]"))
          #:name "There is no user list table beside the remembered name: the prompt asks for one session")
        (assert-true (contains? config "\n[remember]")
          #:name "The remembered name is the request the prompt makes")))
    (test "The Password Is Typed With Feedback"
      (let ((config (greeter-config)))
        (assert-true (contains? config "[secret]")
          #:name "There is a table for the secret")
        (assert-true (contains? config "mode = \"characters\"")
          #:name "One character per keystroke, so a count can be seen")))
    (test "The Prompt Takes A Console's Width And Not The Whole Screen"
      (let ((config (greeter-config)))
        (assert-true (contains? config "[layout]")
          #:name "There is a table for the shape of the box")
        (assert-true (contains? config "width = 60")
          #:name "Narrower than the 80 columns a console usually has, so the box floats")))
    (test "Every Component Tuigreet Can Colour Is Coloured"
      ;; The palette is the one the wizards are drawn with - green ink on a dark
      ;; screen with a warm title - and a colour name tuigreet cannot read is
      ;; dropped in silence, so every name here is one it knows.
      (let ((config (greeter-config)))
        (assert-true (contains? config "[theme]")
          #:name "There is a table for the colours")
        (for-each (lambda (component)
                    (assert-true (contains? config (format #f "~a = \"" component))
                      #:name (format #f "~a has a colour" component)))
                  '("container" "border" "text" "title" "greet"
                    "time" "prompt" "input" "action" "button"))))
    (test "The Backdrop Is Not Animated"
      (assert-true (not (contains? (greeter-config) "[background]"))
        #:name "An animation is a CPU the machine logging in may not have to spare"))
    (test "The File Says That It Is Generated"
      (assert-true (contains? (greeter-config) "DO NOT EDIT")
        #:name "A hand edit is a change the next render overwrites"))
    (test "A File An Older Tuigreet Cannot Read Is Still A Prompt"
      ;; tuigreet ignores keys it does not know, and greetd's `--cmd' is on the
      ;; command line rather than in this file: a prompt with an unreadable
      ;; config is plainer, not absent.
      (assert-true (contains? greeter-command "--cmd")
        #:name "The session is greetd's argument, not tuigreet's file"))))

(define (config-cases)
  (suite "The greetd Configuration"
    (test "The Prompt Takes One Terminal And Runs One Command"
      (let ((config (greetd-config)))
        (assert-true (contains? config "[terminal]")
          #:name "There is a terminal table")
        (assert-true (contains? config "vt = 1")
          #:name "The prompt is on the first virtual terminal")
        (assert-true (contains? config "[default_session]")
          #:name "There is a default session")
        (assert-true (contains? config "command = \"tuigreet")
          #:name "The command is the terminal prompt itself, not a script in front of it")
        (assert-true (contains? config "user = \"_greeter\"")
          #:name "And it runs as the account Void's package creates")))
    (test "An Installed Machine Is Not Logged In Behind Its Own Back"
      (assert-true (not (contains? (greetd-config) "[initial_session]"))
        #:name "No session starts before the prompt by default"))
    (test "A Live Image Logs Its Own User In"
      (let ((config (parameterize ((greeter-autologin-user "heks"))
                      (greetd-config))))
        (assert-true (contains? config "[initial_session]")
          #:name "The live user is started before the greeter")
        (assert-true (contains? config "user = \"heks\"")
          #:name "And it is the account the image creates")))
    (test "The File Says That It Is Generated"
      (assert-true (contains? (greetd-config) "DO NOT EDIT")
        #:name "A hand edit is a change the next render overwrites"))
    (test "A Command With Quotes Stays One TOML String"
      ;; tuigreet passes the session to itself as one argument, and the inner
      ;; quotes have to survive TOML's own escaping or greetd runs a different
      ;; command from the one this module rendered.
      (assert-true (contains? (greetd-config)
                              "command = \"tuigreet --cmd \\\"niri --session\\\"\"")
        #:name "The escaped quotes are in the file greetd reads"))))

(define (spec)
  (veritas-run (package-cases) (prompt-cases) (config-cases)))
