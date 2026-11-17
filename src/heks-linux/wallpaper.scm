;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The palette's wallpaper set, and the front end that chooses from it.
;;
;; The background is whelk's now.  The shell draws one layer surface per
;; monitor, transitions between pictures, rotates through the collection on its
;; own interval, remembers the picture a person picked as a GUI preference and
;; opens `whelk --wallpaper-picker' for browsing.  That is a renderer, a
;; scheduler and a picker in the program that already owns the layer surface the
;; bar sits on, and having a second program set the same background was the one
;; part of this desktop with two owners.
;;
;; What is left here is the half whelk cannot know: which pictures go with which
;; palette.  Every palette curates a handful of images, and that
;; mapping is this project's taste, not the shell's.  So the module owns the
;; set, the interval as it is written down, and the one command a keybinding
;; runs - and `heks-wallpaper' is a thin front end over whelk's preference file
;; rather than an engine of its own.  A machine that never presses the shuffle
;; key never starts it.
;;
;;; Code:

(define-module (heks-linux wallpaper)
  #:declarative? #t
  #:use-module (ice-9 match)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (wallpapers wallpaper-catalog-dir
                       wallpaper-script-dir
                       wallpaper-script-filename
                       wallpaper-scaling
                       wallpaper-state-dir
                       wallpaper-rotation-interval
                       wallpaper-interval-seconds
                       wallpaper-fit
                       wallpaper-script-command
                       wallpaper-picker-command
                       wallpaper-preferences-file
                       wallpaper-whelk-form
                       wallpaper-candidates
                       wallpaper-candidates-file
                       wallpaper-candidates-filename
                       wallpaper-shim-dir
                       wallpaper-shim-script
                       install-wallpaper-config))

(define s
  (scriba-auto-logger))

;; --- Base Paths & Configuration Defaults ---

(define %home-dir
  (or (getenv "HOME") "/tmp"))

;; The home of the wallpaper collection.  ~maak install-wallpaper-files clones
;; it, and %wallpaper-catalog-dir is what the gallery browses.
(define wallpaper-catalog-dir
  (make-parameter (string-append %home-dir "/.config/digital-art-dreams")))

;; Where the generated scripts land.  It has to be on @env{PATH} for the
;; keybindings and the systemd unit to find the engine, which ~/.local/bin is in
;; every Heks session.
(define wallpaper-script-dir
  (make-parameter (string-append %home-dir "/.local/bin")))

;; The front end: the program a keybinding runs to say which picture the shell
;; should be showing.  It is not the renderer - whelk is - and it exists because
;; a keybinding and heks-toon both want to name a picture without knowing how
;; the shell keeps its preferences.
(define wallpaper-script-filename
  (make-parameter "heks-wallpaper"))

;; How the image meets the screen: @code{fill} crops, @code{fit} letterboxes and
;; @code{stretch} distorts.  The words are the previous engine's, because a
;; machine's override should not have to learn a new vocabulary to mean the same
;; thing; @code{wallpaper-fit} translates them into whelk's own policy.
(define wallpaper-scaling
  (make-parameter "fill"))

;; Where the front end records the picture it chose, so heks-toon can show the
;; same one as current.  XDG_STATE_HOME is honoured, with the documented
;; ~/.local/state fallback.  Whelk keeps its own copy in its preference file;
;; this one is for the programs that read heks's state and not whelk's.
(define wallpaper-state-dir
  (make-parameter (let ((xdg (getenv "XDG_STATE_HOME")))
                    (string-append (if (and xdg
                                         (not (string=? xdg ""))) xdg
                                     (string-append %home-dir
                                                    "/.local/state"))
                                   "/heks-linux"))))

;; How often the wallpaper changes: ninety minutes, counted by the shell.
;;
;; It is written the way a person says it and converted to the seconds whelk
;; takes by @code{wallpaper-interval-seconds}.  The interval is the same one the
;; systemd timer used to carry; what changed is who counts it - a shell that is
;; already running, rather than a unit that had to be taught the number.
(define wallpaper-rotation-interval
  (make-parameter "1h30m"))

;; --- Wallpaper Engine: palette selection ---

(define (wallpapers)
  "Return active wallpaper absolute file paths based on the running theme palette."
  (let* ((base-path (wallpaper-catalog-dir))
         (build-paths (lambda (loc files)
                        (map (lambda (f)
                               (format #f "~a/~a/~a" base-path loc f)) files)))
         (palette (heks-linux-palette)))
    (match palette
      ((or 'ef-melissa-light
         'ef-cyprus
         'ef-day
         'ef-kassio
         'everforest-light
         'gruvbox-light)
       (build-paths "wallpapers/sss"
                    '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))

      ('ef-dream (build-paths "wallpapers/sss"
                              '("paisaje-de-la-luna-en-el-anime.jpg"
                                "1362745.png" "inazuma.jpg" "diluc-tree.jpg"
                                "tempel-pink-sun.jpg")))

      ('heavy-metal (build-paths "wallpapers/sss"
                                 '("heavy-wall3.jpg" "heavy-wall2.jpg"
                                   "heavy-wall.jpg" "tempel-red-sun.jpg")))

      ((or 'solarized-light
         'doom-molokai)
       (build-paths "wallpapers"
                    '("wild-hunt.jpg")))

      ('ef-autumn (build-paths "wallpapers/sss"
                               '("0mar2ygf59je1.jpeg" "ofcoisp7abfe1.jpeg")))

      ((or 'ef-bio
         'everforest-dark
         'gruvbox-dark
         'doom-tomorrow-night
         'nord)
       (build-paths "wallpapers/sss"
                    '("some-forest.jpg" "redwood-forest.jpg")))

      ('dracula (build-paths "wallpapers/sss"
                             '("paisaje-de-la-luna-en-el-anime.jpg"
                               "dracula/Dracula.png" "dracula/Kraken.png"
                               "dracula/dracula-soft-waves-44475a.png"
                               "tempel-pink-sun.jpg")))

      ('catppuccin-latte (build-paths "wallpapers/catppuccin"
                                      '("bergen-1.png" "bergen-2.png")))

      ((or 'modus-vivendi
         'modus-vivendi-tinted
         'modus-vivendi-deuteranopia
         'modus-vivendi-tritanopia
         'kaolin-dark
         'solarized-dark)
       (build-paths "wallpapers/sss"
                    '("space/heic2002a.jpg" "space/heic2007a.jpg"
                      "space/potw2006a.jpg")))

      ((or 'modus-operandi
         'modus-operandi-deuteranopia
         'modus-operandi-tritanopia
         'doom-one-light
         'rose-pine-dawn)
       (build-paths "wallpapers"
                    '("bergen-1.jpg" "bergen-2.jpg")))
      ;; `modus-operandi-tinted` is deliberately absent from the generic
      ;; `modus-operandi` family above so it reaches the system wallpaper set.
      ((or 'modus-operandi-tinted)
       (build-paths "wallpapers/mac"
                    '("10-5-6k.jpg" "10-5-Server-6k.jpg"
                      "10-6-6k.jpg"
                      "10-6-Server-6k.jpg"
                      "10-10-6k.jpg"
                      "10-11-6k.jpg"
                      "10-13-6k.jpg"
                      "10-14-Day-6k.jpg")))
      ((or 'ayu-dark
         'ayu-mirage)
       (build-paths "wallpapers/space"
                    '("1.jpg" "2.jpg" "3.jpg" "4.jpg" "5.jpg")))
      ((or 'ayu-light)
       (build-paths "wallpapers/mac"
                    '("10-10-6k.jpg" "10-14-Day-6k.jpg"
                      "15-Sequoia-Sunrise.png")))
      ;; Golden Gate wears the system artwork: the day set for the light
      ;; palette, the night set for the dark one.
      ('golden-gate-light (build-paths "wallpapers/mac"
                                       '("10-14-Day-6k.jpg" "10-15-Day-6k.jpg"
                                         "11-Big-Sur-Day-6k.jpg"
                                         "12-Monterey-Light.jpg"
                                         "15-Sequoia-Sunrise.png")))
      ('golden-gate-dark (build-paths "wallpapers/mac"
                                      '("10-14-Night-6k.jpg"
                                        "10-15-Night-6k.jpg"
                                        "11-Big-Sur-Night-6k.jpg"
                                        "12-Monterey-Dark.jpg")))
      ((or 'kanagawa)
       (build-paths "wallpapers"
                    '("kanagawa.jpg")))

      ((or 'catppuccin-mocha
         'catppuccin-frappe
         'catppuccin-macchiato
         'doom-one
         'tokyo-night)
       (build-paths "wallpapers/catppuccin"
                    '("raiden.png" "varesa-tribe-reputation.png"
                      "moonlight-shadow.png")))

      ((or 'rose-pine
         'rose-pine-moon)
       (build-paths "wallpapers/sss"
                    '("paisaje-de-la-luna-en-el-anime.jpg"
                      "tempel-pink-sun.jpg")))

      ;; Luna's rolling hills, as close as the catalogue comes: the Norwegian
      ;; set, green over water, for a desktop that put a photograph of a hill
      ;; behind every window.
      ('windows-xp (build-paths "wallpapers"
                                '("bergen-1.jpg" "bergen-2.jpg")))

      (_ (raise-exception (make-exception-with-message (format #f
                                                               "unknown palette selected: ~a, so there is no wallpaper set"
                                                               palette)))))))

;; --- The engine whelk owns ---
;;
;; The background is drawn by whelk now: one layer surface per monitor, the
;; transition, the rotation and the picker are its own, and `heks-wallpaper'
;; is a front end over the shell's preference rather than a second renderer.
;; Two programs drawing one background is one program losing, and the one that
;; should win is the one that also owns the bar over it.

(define (wallpaper-script-command)
  "Return the absolute command a keybinding or a session startup runs.

Absolute, because a binding runs with the session's environment rather than with
this module's: the path a render measured is the path the key presses."
  (format #f "~a/~a" (wallpaper-script-dir) (wallpaper-script-filename)))

(define (wallpaper-interval-seconds)
  "Return @code{wallpaper-rotation-interval} in seconds, as whelk counts time.

The parameter is written the way a person says it - @code{\"1h30m\"} - and whelk
takes an integer.  A bare number is read as seconds, so a machine that always
wanted the simple thing can write one."
  (let* ((text (format #f "~a" (wallpaper-rotation-interval)))
         (pattern (make-regexp "([0-9]+)([hms]?)")))
    (if (string->number text)
      (string->number text)
      (let loop ((index 0)
                 (total 0))
        (let ((match (regexp-exec pattern text index)))
          (if (not match)
            (if (zero? total) 5400 total)
            (let ((amount (string->number (match:substring match 1)))
                  (unit (match:substring match 2)))
              (loop (match:end match 0)
                    (+ total
                       (* amount
                          (cond
                            [(string=? unit "h") 3600]
                            [(string=? unit "m") 60]
                            [else 1])))))))))))

(define (wallpaper-fit)
  "Return whelk's fit policy matching @code{wallpaper-scaling}.

The parameter keeps the words the previous engine used, because a machine's
override should not have to learn a new vocabulary to mean the same thing:
@code{fill} crops, @code{fit} letterboxes and @code{stretch} distorts."
  (cond
    [(string=? (format #f "~a" (wallpaper-scaling)) "fit") 'contain]
    [(string=? (format #f "~a" (wallpaper-scaling)) "stretch") 'fill]
    [else 'cover]))

(define (wallpaper-picker-command)
  "Return the command that opens whelk's own wallpaper picker.

heks-toon's wall view is a second way into the same collection; this is the one
the compositor binds and the bar's picture glyph opens in a click."
  "whelk --wallpaper-picker")

(define (wallpaper-shim-dir)
  "Return the directory the front end and its candidate list live in."
  (wallpaper-script-dir))

;; The list the front end reads, beside the front end itself: the two are
;; installed together and a stale half is worse than either.
(define wallpaper-candidates-filename
  (make-parameter "heks-wallpaper.list"))

(define (wallpaper-preferences-file)
  "Return the GUI preference file whelk keeps for its settings.

Whelk writes one override file per settings file, under
@env{XDG_STATE_HOME}/whelk, and the wallpaper a person picked is one of those
overrides.  The front end writes the same file the picker does, so a picture
chosen from a keybinding and one chosen from the picker are remembered the same
way."
  (let ((xdg (getenv "XDG_STATE_HOME")))
    (format #f "~a/whelk/preferences-settings.scm"
            (if (and xdg (not (string=? xdg "")))
              xdg
              (format #f "~a/.local/state" %home-dir)))))

(define (wallpaper-whelk-form)
  "Return the @code{(wallpaper-settings ...)} form for whelk's settings file.

The form is returned as data, not text, so it is spliced into the generated
settings program the way every other whelk setting is - one printer, one
escape.  The collection is the palette's own: the same handful of pictures the
previous engine rotated through, now rotated by the shell that draws them."
  (let ((paths (wallpapers)))
    `(wallpaper-settings #:enabled? #t
                         #:paths (list ,@(map (lambda (path)
                                                path)
                                              paths))
                         #:interval ,(wallpaper-interval-seconds)
                         #:shuffle? #t
                         #:animation 'crossfade
                         #:animation-duration 1200
                         #:fit ',(wallpaper-fit)
                         #:ken-burns? #f
                         #:video? #t
                         #:mute-video? #t
                         #:picker-width 1100
                         #:picker-height 720
                         #:picker-columns 4)))

(define (wallpaper-candidates)
  "Return every picture the palette set names, absolute and sorted.

The list file is what the front end reads, so it is written from the same
function the whelk settings are: a keybinding cannot walk a collection the shell
is not rotating."
  (sort (wallpapers) string<?))

(define (wallpaper-candidates-file)
  "Return the candidate list as text, one absolute path per line."
  (string-join (wallpaper-candidates) "\n"))

(define (wallpaper-shim-script)
  "Return the @command{heks-wallpaper} front end, as a shell script.

The work is in @code{(heks-linux wallpaper-shim)}, because it is Scheme and
testable; this is the launcher that gives it the paths it needs and the tree it
is loaded from.  The paths are written absolute: a keybinding runs with the
session's environment, not with this module's."
  (string-join
   (list "#!/usr/bin/env bash"
         "# ====== Heks-Linux wallpaper front end ======"
         "#"
         "# auto-generated by heks-linux, DO NOT EDIT!"
         "#"
         "# whelk draws the background, rotates it and owns the picker; this"
         "# program only says which picture the shell should be showing."
         "set -u"
         (format #f "export HEKS_WALLPAPER_LIST=~s"
                 (format #f "~a/~a" (wallpaper-shim-dir)
                         (wallpaper-candidates-filename)))
         (format #f "export HEKS_WALLPAPER_PREFERENCES=~s"
                 (wallpaper-preferences-file))
         (format #f "export HEKS_WALLPAPER_STATE=~s"
                 (format #f "~a/wallpaper" (wallpaper-state-dir)))
         (format #f "exec guile --no-auto-compile -L ~s -c '((@ (heks-linux wallpaper-shim) main) (command-line))' -- \"$@\""
                 (format #f "~a/src" (heks-linux-clone-dir))))
   "\n"))

(define (install-wallpaper-config)
  "Write the wallpaper front end, and retire the engine it replaces.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/wallpaper-settings.scm} first, so a machine
can pin the collection, the interval or the fit without touching the module.

The old engine was a systemd timer around a script that started swaybg.  Whelk
draws the background itself now, so all three are retired here: the units are
disabled and removed rather than left to fire a script this configuration no
longer writes, and the renderer is not started by anything any more.  A
machine that still has the timer would otherwise change its wallpaper twice,
which is one owner too many."
  (log-info s "Installing the wallpaper front end")
  (load-local-overrides '(heks-linux wallpaper)
                        'wallpaper-settings)
  (install-config-file! #:name (wallpaper-candidates-filename)
                        #:dir (wallpaper-shim-dir)
                        #:contents (wallpaper-candidates-file))
  (install-config-file! #:name (wallpaper-script-filename)
                        #:dir (wallpaper-shim-dir)
                        #:contents (wallpaper-shim-script)
                        #:perms 493)
  (unless (dry-run?)
    (let ((timer (format #f "~a/heks-wallpaper.timer" (wallpaper-state-dir))))
      (when (file-exists? timer)
        (system* "systemctl" "--user" "disable" "--now" "heks-wallpaper.timer")
        (delete-file timer)))
    (for-each (lambda (stale)
                (when (file-exists? stale)
                  (delete-file stale)
                  (log-info s "Removed the retired wallpaper unit: ~a" stale)))
              (list (format #f "~a/heks-wallpaper.service"
                            (wallpaper-state-dir))
                    (format #f "~a/heks-wallpaper.timer"
                            (wallpaper-state-dir)))))
  (log-success s "Installed the wallpaper front end"))

;;; wallpaper.scm ends here
