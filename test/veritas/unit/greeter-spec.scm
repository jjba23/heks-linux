;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux greeter).
;;
;; The rendered file is TOML, so the tests look for the three tables greetd
;; reads rather than for a substring of a template, and they assert the two
;; greeters separately: a greeter that needs a compositor and one that does not
;; are two different dependency stories.

;;; Code:

(define-module (veritas unit greeter-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux greeter)
  #:export (spec))

(define (contains? text line)
  "Return #t when @var{text} has @var{line} in it."
  (not (eq? #f (string-contains text line))))

(define (package-cases)
  (suite "The Greeter's Packages"
    (test "The Default Greeter Is A GTK Window Under A Kiosk Compositor"
      (assert-equal #:expect '("greetd" "gtkgreet" "cage")
        #:got (greeter-packages)
        #:name "greetd runs it, gtkgreet draws it, cage gives it a screen")
      (assert-equal #:expect "cage gtkgreet"
        #:got (greeter-command)
        #:name "cage takes the application as its argument"))
    (test "The Terminal Greeter Needs Neither GTK Nor A Compositor"
      (assert-equal #:expect '("greetd" "tuigreet")
        #:got (parameterize ((greeter 'tuigreet))
                (greeter-packages))
        #:name "One binary, and the daemon that starts it")
      (assert-equal #:expect
        "tuigreet --time --remember --cmd \"niri --session\""
        #:got (parameterize ((greeter 'tuigreet))
                (greeter-command))
        #:name "The session it offers is passed as one argument"))
    (test "A Greeter This Module Does Not Know Is Refused"
      (assert-error (lambda ()
                      (parameterize ((greeter 'lightdm))
                        (greeter-packages)))
        #:name "An unknown greeter is not silently treated as a default"))))

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
        (assert-true (contains? config "command = \"cage gtkgreet\"")
          #:name "The command is the one the greeter module names")
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
      (let ((config (parameterize ((greeter 'tuigreet))
                      (greetd-config))))
        (assert-true (contains? config
                                "command = \"tuigreet --time --remember --cmd \\\"niri --session\\\"\"")
          #:name "The escaped quotes are in the file greetd reads")))))

(define (spec)
  (veritas-run (package-cases) (config-cases)))
