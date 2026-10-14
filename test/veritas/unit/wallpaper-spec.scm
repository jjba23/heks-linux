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
;; Unit tests for (heks-linux wallpaper): every palette maps to a curated set
;; of background images, and the generated rotation script has to stay valid
;; POSIX shell.

;;; Code:

(define-module (veritas unit wallpaper-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux wallpaper)
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
           (not (eq? #f (string-contains path dir))))
         (wallpaper-set palette)))

(define wallpaper-suite
  (suite "Wallpaper Selection Suite"
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
               (assert-true (all-under? "/wallpapers/" 'modus-operandi)
                            #:name
                            "modus-operandi should stay inside the shared wallpaper tree")
               (assert-true (not (eq? #f (member (format #f "~a/.config/digital-art-dreams/wallpapers/bergen-1.jpg"
                                                         (or (getenv "HOME") "/tmp"))
                                                 (wallpaper-set 'modus-operandi))))
                            #:name
                            "modus-operandi should include the Bergen backgrounds"))

         (test "Tinted Operandi Reaches The macOS Set"
               (assert-true (all-under? "/wallpapers/mac/" 'modus-operandi-tinted)
                            #:name
                            "modus-operandi-tinted must not be swallowed by the generic operandi clause")
               (assert-true (not (null? (wallpaper-set 'modus-operandi-tinted)))
                            #:name
                            "The macOS wallpaper set should not be empty"))

         (test "Catalogued Palettes Use Their Own Directories"
               (assert-true (all-under? "/wallpapers/catppuccin/"
                                        'catppuccin-mocha)
                            #:name "catppuccin-mocha should use its own artwork")
               (assert-true (all-under? "/wallpapers/space/" 'ayu-dark)
                            #:name "ayu-dark should use the space artwork"))

         (test "Unknown Palettes Are Rejected"
               (assert-error (lambda () (wallpaper-set 'not-a-real-palette))
                             #:name
                             "An unregistered palette should raise instead of picking nothing"))

         (let* ((walls (wallpaper-set 'modus-operandi))
                (script (mk-random-wall-cmd walls)))
           (test "Rotation Script Is Valid Shell"
                 (assert-true (string-prefix? "#!/usr/bin/env sh" script)
                              #:name "The rotation script should be POSIX shell")
                 (assert-true (not (eq? #f (string-contains script
                                                            "pkill swaybg")))
                              #:name "The rotation script should replace the running swaybg")
                 (assert-equal #:expect (length walls)
                               #:got (length (filter (lambda (line)
                                                       (not (eq? #f (string-contains
                                                                     line "WALL="))))
                                                     (string-split script #\newline)))
                               #:name
                               "The script should contain one branch per wallpaper")))))

(define (spec)
  (veritas-run wallpaper-suite))
