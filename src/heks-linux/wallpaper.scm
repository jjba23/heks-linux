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

(define-module (heks-linux wallpaper)
  #:declarative? #t
  #:use-module (ice-9 match)
  #:use-module (ice-9 exceptions)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux palette)
  #:export (wallpapers mk-random-wall-cmd install-wallpaper-config))

(define* (wallpapers)
  "Define diverse wallpapers based on the active color scheme. "
  (let* ((wall-path (format #f "~a/.config/digital-art-dreams"
                            (getenv "HOME")))
         (digital-art-dreams-heks-linux-wallpaper (lambda* (w #:key (location
                                                                     "wallpapers/sss"))
                                                    (format #f "~a/~a/~a"
                                                            wall-path location
                                                            w))))
    (match (heks-linux-palette)
      ('ef-melissa-light (map digital-art-dreams-heks-linux-wallpaper
                              '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))
      ('ef-cyprus (map digital-art-dreams-heks-linux-wallpaper
                       '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))
      ('ef-dream (map digital-art-dreams-heks-linux-wallpaper
                      '("paisaje-de-la-luna-en-el-anime.jpg" "1362745.png"
                        "inazuma.jpg" "diluc-tree.jpg" "tempel-pink-sun.jpg")))
      ('heavy-metal (map digital-art-dreams-heks-linux-wallpaper
                         '("heavy-wall3.jpg" "heavy-wall2.jpg"
                           "heavy-wall.jpg" "tempel-red-sun.jpg")))
      ('solarized-light (map digital-art-dreams-heks-linux-wallpaper
                             '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))
      ('ef-autumn (map digital-art-dreams-heks-linux-wallpaper
                       '("0mar2ygf59je1.jpeg" "ofcoisp7abfe1.jpeg")))
      ('ef-bio (map digital-art-dreams-heks-linux-wallpaper
                    '("some-forest.jpg" "redwood-forest.jpg")))
      ('everforest-dark (map digital-art-dreams-heks-linux-wallpaper
                             '("some-forest.jpg" "redwood-forest.jpg")))
      ('everforest-light (map digital-art-dreams-heks-linux-wallpaper
                              '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))
      ('gruvbox-dark (map digital-art-dreams-heks-linux-wallpaper
                          '("some-forest.jpg" "redwood-forest.jpg")))
      ('gruvbox-light (map digital-art-dreams-heks-linux-wallpaper
                           '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))

      ('dracula (map digital-art-dreams-heks-linux-wallpaper
                     '("paisaje-de-la-luna-en-el-anime.jpg"
                       "dracula/Dracula.png" "dracula/Kraken.png"
                       "dracula/dracula-soft-waves-44475a.png"
                       "tempel-pink-sun.jpg")))
      ('catppuccin-latte (map digital-art-dreams-heks-linux-wallpaper
                              '("joshua.jpg" "PXL_20250326_193029385.MP.jpg")))
      ('modus-vivendi (map digital-art-dreams-heks-linux-wallpaper
                           '("space/heic2002a.jpg" "space/heic2007a.jpg"
                             "space/potw2006a.jpg")))
      ('modus-operandi (map (lambda (w)
                              (digital-art-dreams-heks-linux-wallpaper w
                               #:location "wallpapers"))
                            '("bergen-1.jpg" "bergen-2.jpg")))
      ('kaolin-dark (map digital-art-dreams-heks-linux-wallpaper
                         '("space/heic2002a.jpg" "space/heic2007a.jpg"
                           "space/potw2006a.jpg")))
      ('catppuccin-mocha (map (lambda (w)
                                (digital-art-dreams-heks-linux-wallpaper w
                                 #:location "wallpapers/catppuccin"))
                              '("raiden.png" "varesa-tribe-reputation.png")))
      (_ (raise-exception (make-exception-with-message (format #f
                                                        "exception ocurred! unknown palette selected, could not choose wallpaper for: ~a"
                                                        (heks-linux-palette))))))))

(define (mk-random-wall-cmd walls)
  (let* ((wall-idx -1))
    (format #f
            (string-join '("#!/usr/bin/env sh" ""
                           "# ====== HEKS-LINUX wallpaper setter ======"
                           "#"
                           "# auto-generated file, DO NOT EDIT!"
                           ""
                           "case $(( $(date +%s) % ~a )) in"
                           "~a"
                           "esac;"
                           ""
                           "pkill swaybg || true \\"
                           "\t&& echo \"setting current wallpaper: $WALL\" \\"
                           "\t&& WAYLAND_DISPLAY=wayland-0 swaybg -i \"$WALL\" || true \\"
                           "\t&& WAYLAND_DISPLAY=wayland-1 swaybg -i \"$WALL\" || true \\"
                           "\t&& WAYLAND_DISPLAY=wayland-2 swaybg -i \"$WALL\" || true ")
                         "\n")
            (length walls)
            (string-join (map (lambda (w)
                                (set! wall-idx
                                      (+ 1 wall-idx))
                                (format #f "\t~a) WALL=\"~a\";;" wall-idx w))
                              walls) "\n"))))

(define (install-wallpaper-config)
  (let* ((file (format #f "~a/.local/bin/user-script-set-random-wallpaper"
                       (getenv "HOME"))))
    (with-output-to-file file
      (lambda ()
        (display (mk-random-wall-cmd (wallpapers)))))
    (syscall (format #f "chmod +x ~a" file))))

