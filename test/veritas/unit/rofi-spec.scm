;;; heks-linux

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; heks-linux is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; heks-linux is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with heks-linux.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Unit tests for (heks-linux rofi).
;;
;; Assertions are passed straight to `test' on purpose: `assert-*' returns a
;; closure whose value is dropped in a non-final position, which lets Guile's
;; optimizer delete the call before the runner can execute it.  See the note
;; in waybar-spec.scm for the full explanation.

;;; Code:

(define-module (veritas unit rofi-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:export (spec))

(define (string-occurs? haystack needle)
  "Return @code{#t} when @var{needle} appears inside @var{haystack}."
  (not (eq? #f (string-contains haystack needle))))

(define (stages-in-order? script stages)
  "Whether @var{stages} occur in @var{script} in that order."
  (let loop ((rest stages) (at 0))
    (if (null? rest)
        #t
        (let ((index (string-contains script (car rest) at)))
          (and index (loop (cdr rest) index))))))

(define rofi-suite
  (suite "Rofi Configuration and Theming"
         (test "Rofi Config String Template"
               (assert-true (string-occurs?
                             (rofi-configuration)
                             (format #f "font: \"~a 14\""
                                     (heks-linux-sans-font)))
                #:name
                "Configuration should inject the configured sans font")
               (assert-true (string-occurs? (rofi-configuration)
                                            "show-icons: true")
                #:name "Icons should be enabled by default")
               (assert-true (string-occurs? (rofi-configuration)
                                            "@theme \"./sss-theme.rasi\"")
                #:name "Config must reference the generated theme file"))

         (test "Rofi Script Modes Registered"
               (assert-true (string-occurs? (rofi-configuration)
                                            "drun,window,power:")
                #:name
                "The launcher, window switcher and power menu modes should be registered")
               (assert-true (string-occurs? (rofi-configuration)
                                            (rofi-theme-menu-filename))
                #:name "The theme picker mode should be registered")
               (assert-true (string-occurs? (rofi-configuration)
                                            (rofi-power-menu-filename))
                #:name "The power mode should point at the generated script"))

         (test "Rofi Theme (AList Structure)"
               (assert-true (list? (rofi-theme))
                            #:name "Theme should be a list (AList)")
               (assert-true (not (eq? #f (assoc-ref (rofi-theme) "*")))
                #:name "Should contain a global wildcard '*' section")
               (assert-equal #:expect "transparent"
                             #:got
                             (assoc-ref (assoc-ref (rofi-theme)
                                                   "*")
                                        'background-color)
                             #:name "Global background-color should be transparent")
               (assert-equal #:expect "18px"
                             #:got
                             (assoc-ref (assoc-ref (rofi-theme)
                                                   "window")
                                        'border-radius)
                             #:name "The spotlight panel should be softly rounded")
               ;; The launcher wears the same hairline as a mako banner: one
               ;; pixel of the palette's secondary text colour at 15% opacity.
               ;; A zero-pixel border left the panel edgeless against a
               ;; wallpaper of its own tone, and a full-opacity colour turned
               ;; it into the hard frame the rest of the system avoids.
               (assert-equal #:expect "1px"
                             #:got
                             (assoc-ref (assoc-ref (rofi-theme)
                                                   "window")
                                        'border)
                             #:name
                             "The launcher should carry a one-pixel hairline")
               (assert-equal #:expect (hex-to-rgba (get-color (heks-linux-palette)
                                                             'text-l)
                                                   #:alpha 0.15)
                             #:got
                             (assoc-ref (assoc-ref (rofi-theme)
                                                   "window")
                                        'border-color)
                             #:name
                             "The hairline should be the secondary text colour at 15% opacity"))

         (test "Power Menu Script"
               (assert-true (string-occurs? (make-rofi-power-menu-script)
                                            "#!/usr/bin/env bash")
                #:name "The power menu must be a Bash script")
               (assert-true (string-occurs?
                             (make-rofi-power-menu-script)
                             (format #f "printf '~a\\0icon\\x1f~a\\n'"
                                     (car (car (rofi-power-menu-entries)))
                                     (cadr (car (rofi-power-menu-entries)))))
                #:name
                "The first entry must use the rofi \\0icon\\x1f separator")
               (assert-true (string-occurs? (make-rofi-power-menu-script)
                                            "systemctl poweroff")
                #:name "The power menu should expose a shutdown action"))

         (test "Theme Picker Script"
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "#!/usr/bin/env bash")
                #:name "The theme picker must be a Bash script")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "maak install-theme")
                #:name
                "Choosing a palette must re-render the palette-dependent configs")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "local-settings.scm")
                #:name
                "Choosing a palette must persist itself as a local override"))

         (test "Theme Picker Offers Every Palette With A Swatch"
               ;; One row per palette plus the `*' fallback that keeps an
               ;; unknown name from rendering an empty swatch.
               (assert-equal #:expect (1+ (length (palette-names)))
                             #:got
                             (length (filter (lambda (line)
                                               (string-occurs? line
                                                               "printf '%s %s %s %s'"))
                                             (string-split
                                              (make-rofi-theme-menu-script)
                                              #\newline)))
                             #:name
                             "Every registered palette should get a swatch table row")
               (assert-true (every (lambda (p)
                                     (string-occurs? (make-rofi-theme-menu-script)
                                                     (format #f "\"~a\"" p)))
                                   (palette-names))
                            #:name "Every registered palette should be listed")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            (format #f
                                                    "~a) printf '%s %s %s %s' '~a' '~a' '~a' '~a'"
                                                    'heavy-metal
                                                    (get-color 'heavy-metal
                                                               'background)
                                                    (get-color 'heavy-metal
                                                               'primary)
                                                    (get-color 'heavy-metal
                                                               'background-l)
                                                    (get-color 'heavy-metal
                                                               'text)))
                            #:name
                            "A swatch should be painted from the palette's own colours"))

         (test "Theme Picker Wears The Right Emacs Theme"
               (assert-true (string-occurs?
                             (make-rofi-theme-menu-script)
                             "heavy-metal) printf '%s' 'ef-tritanopia-dark'")
                            #:name
                            "A palette should carry the Emacs theme it wears, not a rename of its own name")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "emacsclient --eval")
                            #:name
                            "The running Emacs should be told about the theme instead of waiting for a restart"))

         (test "Theme Picker Caches Its Swatches"
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "SWATCH_DIR=")
                            #:name
                            "The swatches should be cached outside the config")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "SWATCH_SIG=")
                            #:name
                            "A palette change should invalidate the cached swatches exactly once")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "magick")
                            #:name "ImageMagick should draw the swatches"))

         (test "Theme Picker Knows Which Palette Is Running"
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            (format #f "CURRENT=\"~a\""
                                                    (heks-linux-palette)))
                            #:name
                            "The picker should know which palette is currently active"))

         (test "Theme Picker Reports Its Progress"
               ;; A switch takes seconds; silence for seconds reads as a hang.
               (assert-true (stages-in-order? (make-rofi-theme-menu-script)
                                              '("progress settings"
                                                "progress rendering"
                                                "progress wallpaper"
                                                "progress emacs"
                                                "progress done"))
                            #:name
                            "The picker should write its stages in the order it does them")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "progress failed")
                            #:name "A switch that fails should say so")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "heks-theme-progress")
                            #:name
                            "The stage should be written where the gallery page reads it")

               ;; One notification, edited as the work happens: two
               ;; notifications for one switch is a stack to clear afterwards.
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "fyi -p")
                            #:name
                            "The picker should keep the id of the notification it opened")
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "fyi -r")
                            #:name
                            "The picker should edit that notification rather than add another")
               ;; fyi prints "id=33", not "33": handing that straight to -r is
               ;; rejected as an invalid id.
               (assert-true (string-occurs? (make-rofi-theme-menu-script)
                                            "${NOTIFICATION#id=}")
                            #:name
                            "The id prefix fyi prints should be stripped before reuse"))))

(define (spec)
  (veritas-run rofi-suite))
