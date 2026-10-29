;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux wallpaper): every palette maps to a curated set
;; of background images, and the three generated artefacts - the engine, the
;; Rofi picker and the systemd units - have to stay valid where they run.
;;
;; The engine and the picker are shell programs, so these tests assert on the
;; text they are rendered from.  The properties pinned here are the ones that
;; used to be broken: a POSIX-only engine, a poll for the Wayland socket
;; instead of a guess at its name, a service that finishes so the timer can
;; fire again, and a picker that previews the collection it offers.

;;; Code:

(define-module (veritas unit wallpaper-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux wallpaper)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:export (spec))

(define (wallpaper-set palette)
  "Wallpapers selected for @var{palette}."
  (parameterize ((heks-linux-palette palette))
    (wallpapers)))

(define (all-under? dir palette)
  "Whether every wallpaper of @var{palette} lives under @var{dir}."
  (every (lambda (path)
           (not (eq? #f
                     (string-contains path dir))))
         (wallpaper-set palette)))

(define (engine)
  "The engine rendered for a known palette."
  (parameterize ((heks-linux-palette 'modus-operandi))
    (mk-random-wall-cmd (wallpapers))))

(define (engine-occurs? fragment)
  "Whether the engine contains @var{fragment}."
  (not (eq? #f
            (string-contains (engine) fragment))))

(define (scratch-dir name)
  "A throwaway directory named @var{name}, unique to this run."
  (format #f "/tmp/heks-wallpaper-spec-~a/~a"
          (getpid) name))

(define (executable? path)
  "Whether @var{path} carries any execute bit."
  (not (zero? (logand (stat:perms (stat path)) #x49))))

(define wallpaper-suite
  (suite "Wallpaper Engine Suite"
         (test "Every Palette Resolves To Absolute Paths"
               (assert-true (every (lambda (name)
                                     (let ((paths (wallpaper-set name)))
                                       (and (not (null? paths))
                                            (every (lambda (path)
                                                     (string-prefix? "/" path))
                                                   paths))))
                                   (palette-names))
                            #:name
                            "No palette may end up without a wallpaper set"))

         (test "Generic Operandi Uses The Bergen Set"
               (assert-true (all-under? "/wallpapers/"
                                        'modus-operandi)
                #:name
                "modus-operandi should stay inside the shared wallpaper tree")
               (assert-true (not (eq? #f
                                      (member (format #f
                                               "~a/.config/digital-art-dreams/wallpapers/bergen-1.jpg"
                                               (or (getenv "HOME") "/tmp"))
                                              (wallpaper-set 'modus-operandi))))
                #:name "modus-operandi should include the Bergen backgrounds"))

         (test "Tinted Operandi Reaches The macOS Set"
               (assert-true (all-under? "/wallpapers/mac/"
                                        'modus-operandi-tinted)
                #:name
                "modus-operandi-tinted must not be swallowed by the generic operandi clause")
               (assert-true (not (null? (wallpaper-set 'modus-operandi-tinted)))
                            #:name
                            "The macOS wallpaper set should not be empty"))

         (test "Catalogued Palettes Use Their Own Directories"
               (assert-true (all-under? "/wallpapers/catppuccin/"
                                        'catppuccin-mocha)
                            #:name
                            "catppuccin-mocha should use its own artwork")
               (assert-true (all-under? "/wallpapers/space/"
                                        'ayu-dark)
                            #:name "ayu-dark should use the space artwork"))

         (test "Unknown Palettes Are Rejected"
               (assert-error (lambda ()
                               (wallpaper-set 'not-a-real-palette))
                #:name
                "An unregistered palette should raise instead of picking nothing"))

         (test "The Engine Is A POSIX Shell Script"
               (assert-true (string-prefix? "#!/usr/bin/env sh"
                                            (engine))
                            #:name "The engine should run under any sh")
               (assert-true (eq? #f
                                 (string-contains (engine) "[["))
                            #:name "The engine must not use bash test syntax")
               (assert-true (eq? #f
                                 (string-contains (engine) "$RANDOM"))
                            #:name
                            "The engine must not read the bash-only RANDOM"))

         (test "The Engine Carries The Whole Palette Set"
               (assert-equal #:expect (length (wallpaper-set 'modus-operandi))
                             #:got (length (filter (lambda (line)
                                                     (string-prefix? "\t\t\""
                                                                     line))
                                                   (string-split (engine)
                                                                 #\newline)))
                             #:name
                             "One quoted wallpaper per line, and no more")
               (assert-true (every (lambda (wall)
                                     (engine-occurs? wall))
                                   (wallpaper-set 'modus-operandi))
                #:name
                "Every palette wallpaper should be reachable from the engine"))

         (test "The Engine Finds The Compositor Instead Of Guessing It"
               (assert-true (engine-occurs? "WAYLAND_DISPLAY")
                            #:name "The engine should read WAYLAND_DISPLAY")
               (assert-true (not (eq? #f
                                      (string-contains (engine)
                                                       "wayland-[0-9]*")))
                #:name
                "The engine should discover the socket in XDG_RUNTIME_DIR")
               (assert-true (eq? #f
                                 (string-contains (engine) "wayland-0 swaybg"))
                            #:name
                            "The old guess at the display name must be gone")
               (assert-true (engine-occurs?
                             "could not reach a Wayland compositor")
                            #:name
                            "Waiting for the compositor should fail loudly"))

         (test "The Engine Detaches Its Renderer"
               (assert-true (engine-occurs? "setsid")
                #:name
                "The renderer should outlive the service that started it")
               (assert-true (engine-occurs? "pkill -x swaybg")
                #:name "The previous swaybg should be replaced, by exact name")
               (assert-true (engine-occurs? "pgrep -x swaybg")
                            #:name
                            "A renderer that died on connect must be noticed")
               (assert-true (engine-occurs? "render_wbg")
                            #:name
                            "The layer-shell renderer should be selectable"))

         (test "The Engine Remembers And Restores"
               (assert-true (engine-occurs? "STATE_FILE")
                            #:name
                            "The engine should keep the wallpaper it set")
               (assert-true (engine-occurs? "restore)")
                #:name
                "The compositor should be able to re-apply that wallpaper")
               (assert-true (engine-occurs? "palette_index_of")
                #:name
                "next and prev need to know where the current image sits"))

         (test "The Service Finishes So The Timer Can Fire Again"
               (assert-true (string-prefix? "[Unit]"
                                            (mk-random-wall-systemd-service
                                             "/tmp/engine"))
                            #:name "The service should be a unit file")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-service
                                                        "/tmp/engine")
                                                       "Type=oneshot")))
                #:name
                "A simple unit around a renderer that never exits cannot be re-triggered")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-service
                                                        "/tmp/engine")
                                                       "KillMode=process")))
                #:name
                "The detached renderer must survive the oneshot finishing")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-service
                                                        "/tmp/engine")
                                                       "/tmp/engine random")))
                            #:name
                            "The service should run the installed engine"))

         (test "The Timer Rotates Every Ninety Minutes"
               ;; A monotonic interval, not a calendar: "every ninety minutes"
               ;; has no wall-clock spelling, since OnCalendar's minute step has
               ;; to divide an hour.
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-timer)
                                                       "OnActiveSec=")))
                            #:name "The timer needs the first change to be scheduled")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-timer)
                                                       "OnUnitActiveSec=")))
                            #:name "And every change after it to repeat")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-timer)
                                                       (wallpaper-rotation-interval))))
                            #:name "The schedule should be the configured interval")
               (assert-equal #:expect "1h30m"
                             #:got (wallpaper-rotation-interval)
                             #:name "The wallpaper should change every ninety minutes by default")
               (assert-equal #:expect #f
                             #:got (string-contains (mk-random-wall-systemd-timer)
                                                    "OnCalendar=")
                             #:name "A calendar entry cannot say ninety minutes, so there should not be one")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-timer)
                                                       (wallpaper-service-filename))))
                            #:name
                            "The timer should name the service it starts")
               (assert-true (not (eq? #f
                                      (string-contains (mk-random-wall-systemd-timer)
                                       "WantedBy=timers.target")))
                            #:name "The timer should be enable-able"))

         (test "Installing Writes Every Artefact"
               (parameterize ((wallpaper-script-dir (scratch-dir "bin"))
                              (wallpaper-systemd-dir (scratch-dir "systemd")))
                 ;; A previous install left the Rofi wall behind: the installer
                 ;; is what removes it, so the spec puts one there first.
                 (ensure-directory-tree! (wallpaper-script-dir))
                 (call-with-output-file
                     (format #f "~a/heks-wallpaper-chooser" (wallpaper-script-dir))
                   (lambda (port) (display "#!/bin/sh\n" port)))
                 (install-wallpaper-config)
                 (assert-true (file-exists? (format #f "~a/~a"
                                                    (wallpaper-script-dir)
                                                    (wallpaper-script-filename)))
                              #:name "The engine should be installed")
                 (assert-true (executable? (format #f "~a/~a"
                                                   (wallpaper-script-dir)
                                                   (wallpaper-script-filename)))
                              #:name "The engine should be executable")
                 ;; The Rofi wall is gone: the gallery page is the picker, and a
                 ;; script left over from an older install is removed.
                 (assert-true (not (file-exists?
                                    (format #f "~a/heks-wallpaper-chooser"
                                            (wallpaper-script-dir))))
                              #:name
                              "The retired Rofi wallpaper picker should not be installed")
                 (assert-true (file-exists? (format #f "~a/~a"
                                                    (wallpaper-systemd-dir)
                                                    (wallpaper-service-filename)))
                              #:name "The service should be installed")
                 (assert-true (file-exists? (format #f "~a/~a"
                                                    (wallpaper-systemd-dir)
                                                    (wallpaper-timer-filename)))
                              #:name "The timer should be installed")))))

(define (spec)
  (veritas-run wallpaper-suite))
