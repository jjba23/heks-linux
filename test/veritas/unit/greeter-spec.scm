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
;;
;; The last suite runs the prompt greetd starts, because it is a shell program
;; and the thing that matters about it is what it does when the compositor
;; cannot draw - which no assertion on its text can tell.

;;; Code:

(define-module (veritas unit greeter-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux greeter)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (contains? text line)
  "Return #t when @var{text} has @var{line} in it."
  (not (eq? #f (string-contains text line))))

(define (package-cases)
  (suite "The Greeter's Packages"
    (test "The Default Greeter Is A GTK Window Under A Kiosk Compositor"
      (assert-equal #:expect '("greetd" "gtkgreet" "cage" "tuigreet")
        #:got (greeter-packages)
        #:name "greetd runs it, gtkgreet draws it, cage gives it a screen, and the terminal prompt is there for the machine cage cannot draw on")
      (assert-equal #:expect greeter-script-path
        #:got (greeter-command)
        #:name "The command is the script that runs the compositor, not the compositor itself"))
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
        (assert-true (contains? config
                                (format #f "command = \"~a\"" greeter-script-path))
          #:name "The command is the prompt script, which is where a compositor that cannot draw is caught")
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

(define (parses? text)
  "Return @code{#t} when the shell reads @var{text} as a script, without running it."
  (let ((path (format #f "/tmp/heks-greeter-spec-~a.sh" (getpid))))
    (call-with-output-file path
      (lambda (port) (display text port)))
    (let ((status (status:exit-val (system* "bash" "-n" path))))
      (delete-file path)
      (zero? status))))

;; --- running the prompt greetd starts ------------------------------------
;;
;; cage dying before it draws is the failure this script exists for, and it is a
;; failure no assertion on the text can see: the count, the limit and the fall
;; back are three moving parts.  So the script is rendered into a scratch
;; directory and run against stubs that record what they were asked to start.
;; `date' is a stub as well - a run's length is told to it, not waited for.

(define (block . lines)
  "Return LINES as one text, one per line, ending in a newline."
  (string-append (string-join lines "\n") "\n"))

(define (find-bash)
  "Return the bash this environment can actually run.

`/usr/bin/env' is not where the hermetic container keeps it, so the script is
started by naming an interpreter rather than through its shebang."
  (let loop ((dirs (string-split (or (getenv "PATH") "") #\:)))
    (cond [(null? dirs) "bash"]
          [(file-exists? (string-append (car dirs) "/bash"))
           (string-append (car dirs) "/bash")]
          [else (loop (cdr dirs))])))

(define (write-executable! path text)
  "Write @var{text} to @var{path} and make it a program."
  (call-with-output-file path (lambda (port) (display text port)))
  (system* "chmod" "755" path))

(define (stub! root name text)
  "Write an executable stub called @var{name} into @var{root}/bin."
  (let ((path (format #f "~a/bin/~a" root name)))
    (write-executable! path text)
    path))

(define (prompt! name)
  "Return a scratch directory holding the rendered prompt and its stubs.

The stubs are the three programs the prompt runs: `cage', which dies at once and
records that it was asked to draw; `tuigreet', which records that it was asked
instead; and `date', which answers from a file, so a run can be given a length
without waiting for one."
  (let ((root (format #f "/tmp/heks-greeter-spec-~a/~a" (getpid) name)))
    (system* "rm" "-rf" root)
    (system* "mkdir" "-p" (format #f "~a/bin" root) (format #f "~a/run" root))
    (write-executable! (format #f "~a/bin/heks-greeter" root) (greeter-script))
    (stub! root "cage"
           (block (format #f "#!~a" (find-bash))
                  "echo \"cage $*\" >> \"$CALLS\""
                  "exit 1"))
    (stub! root "tuigreet"
           (block (format #f "#!~a" (find-bash))
                  "echo \"tuigreet $*\" >> \"$CALLS\""
                  "exit 0"))
    ;; The two calls are the length of one run: the first answers with the value
    ;; in `clock', the second with that value plus STEP.
    (stub! root "date"
           (block (format #f "#!~a" (find-bash))
                  "n=$(cat \"$ROOT/clock\" 2>/dev/null || echo 0)"
                  "echo \"$n\""
                  "echo $((n + $STEP)) > \"$ROOT/clock\""
                  "exit 0"))
    root))

(define (run-prompt! root step)
  "Run the rendered prompt once, as a greeter that lasted @var{step} seconds."
  (system* "env"
           (format #f "PATH=~a/bin:~a" root (or (getenv "PATH") ""))
           (format #f "XDG_RUNTIME_DIR=~a/run" root)
           (format #f "ROOT=~a" root)
           (format #f "CALLS=~a/calls" root)
           (format #f "STEP=~a" step)
           (find-bash)
           (format #f "~a/bin/heks-greeter" root)))

(define (calls root)
  "Return the programs the prompt asked to start, in order."
  (let ((path (format #f "~a/calls" root)))
    (if (file-exists? path)
      (string-split (string-trim-right (call-with-input-file path get-string-all)
                                       #\newline)
                    #\newline)
      '())))

(define (fallback-cases)
  (let ((broken (prompt! "broken"))
        (drawn (prompt! "drawn"))
        (alone (prompt! "alone")))
    ;; Four runs of a compositor that dies before it draws; then four runs that
    ;; stayed up a minute, which is a prompt that drew.  The third machine has no
    ;; terminal prompt to fall back to at all.
    (delete-file (format #f "~a/bin/tuigreet" alone))
    (for-each (lambda (step) (run-prompt! broken step)) '(1 1 1 1))
    (for-each (lambda (step) (run-prompt! drawn step)) '(60 60 60 60))
    (for-each (lambda (step) (run-prompt! alone step)) '(1 1 1 1))
    (suite "What A Compositor That Cannot Draw Does"
      (test "The Prompt Greetd Runs Is A Script"
        (assert-true (string-prefix? "#!/bin/sh" (greeter-script))
          #:name "A shell greeter, and not a command line in a TOML file")
        (assert-true (parses? (greeter-script))
          #:name "Which the shell reads, without running it"))
      (test "The Compositor Is Allowed To Draw On The CPU"
        (assert-true (contains? (greeter-script) "WLR_RENDERER_ALLOW_SOFTWARE=1")
          #:name "wlroots uses a software renderer only when it is told it may"))
      (test "The Prompt Types On The Machine's Keyboard"
        (parameterize ((heks-linux-keyboard-layout "us")
                       (heks-linux-keyboard-options '()))
          (assert-true (contains? (greeter-script) "XKB_DEFAULT_LAYOUT='us'")
            #:name "The layout is named in the variable libxkbcommon reads"))
        (parameterize ((heks-linux-keyboard-layout "nl")
                       (heks-linux-keyboard-options '("ctrl:nocaps" "compose:ralt")))
          (assert-true (contains? (greeter-script)
                                  "XKB_DEFAULT_OPTIONS='ctrl:nocaps,compose:ralt'")
            #:name "And the options, joined the way xkbcommon wants them"))
        ;; The layout is a string a settings file chose, and it lands in a shell
        ;; assignment: one word, whatever it carries.
        (parameterize ((heks-linux-keyboard-layout "us'; reboot; '"))
          (assert-true (contains? (greeter-script)
                                  (string-append "XKB_DEFAULT_LAYOUT="
                                                 "'us'\\''; reboot; '\\'''"))
            #:name "A layout with a quote in it stays a layout")))
      (test "Three Failures In A Row Leave The Terminal Prompt"
        (assert-equal
          #:expect '("cage gtkgreet" "cage gtkgreet" "cage gtkgreet"
                     "tuigreet --time --remember --cmd niri --session")
          #:got (calls broken)
          #:name "A compositor that dies before it draws is replaced, and greetd is not left restarting it"))
      (test "A Prompt That Stayed Up Starts The Count Over"
        (assert-equal
          #:expect (make-list 4 "cage gtkgreet")
          #:got (calls drawn)
          #:name "A run long enough to have drawn something is not a failure"))
      (test "A Machine Without The Terminal Prompt Is Left As It Was"
        (assert-equal
          #:expect (make-list 4 "cage gtkgreet")
          #:got (calls alone)
          #:name "A fallback that is not installed is no fallback: an exec that fails every time is worse than the compositor")))))

(define (spec)
  (veritas-run (package-cases) (config-cases) (fallback-cases)))
