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
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (wallpapers mk-random-wall-cmd
                       install-wallpaper-config
                       wallpaper-script-dir
                       wallpaper-script-filename
                       wallpaper-systemd-dir
                       wallpaper-service-filename
                       wallpaper-timer-filename))

(define s
  (scriba-auto-logger))

;; --- Base Paths & Configuration Defaults ---

(define %home-dir
  (or (getenv "HOME") "/tmp"))

(define wallpaper-script-dir
  (make-parameter (string-append %home-dir "/.local/bin")))

(define wallpaper-script-filename
  (make-parameter "user-script-set-random-wallpaper"))

(define wallpaper-systemd-dir
  (make-parameter (string-append %home-dir "/.config/systemd/user")))

(define wallpaper-service-filename
  (make-parameter "random-wallpaper.service"))

(define wallpaper-timer-filename
  (make-parameter "random-wallpaper.timer"))

;; --- Wallpaper Engine ---

(define (wallpapers)
  "Return active wallpaper absolute file paths based on the running theme palette."
  (let* ((base-path (string-append %home-dir "/.config/digital-art-dreams"))
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
           'modus-operandi-tinted
           'modus-operandi-deuteranopia
           'modus-operandi-tritanopia
           'doom-one-light
           'rose-pine-dawn)
       (build-paths "wallpapers"
                    '("bergen-1.jpg" "bergen-2.jpg")))
      ((or 'ayu-dark
           'ayu-mirage)
       (build-paths "wallpapers/space"
                    '("1.jpg" "2.jpg" "3.jpg" "4.jpg" "5.jpg")))
      ((or 'ayu-light)
       (build-paths "wallpapers/mac"
                    '("10-10-6k.jpg" "10-14-Day-6k.jpg"
                      "15-Sequoia-Sunrise.png")))
      ((or 'kanagawa)
       (build-paths "wallpapers"
                    '("kanagawa.jpg")))

      ((or 'catppuccin-mocha
           'doom-one
           'tokyo-night)
       (build-paths "wallpapers/catppuccin"
                    '("raiden.png" "varesa-tribe-reputation.png"
                      "moonlight-shadow.png")))

      ('rose-pine-moon (build-paths "wallpapers/sss"
                                    '("paisaje-de-la-luna-en-el-anime.jpg"
                                      "tempel-pink-sun.jpg")))

      (_ (raise-exception (make-exception-with-message (format #f
                                                        "exception occurred! unknown palette selected (~a), could not determine wallpaper set."
                                                        palette)))))))

;; --- Script & Configuration Templates ---

(define (mk-random-wall-cmd walls)
  (let* ((len (length walls))
         (cases (string-join (map (lambda (idx w)
                                    (format #f "\t~a) WALL=\"~a\";;" idx w))
                                  (iota len) walls) "\n")))
    (format #f "#!/usr/bin/env sh
# ====== HEKS-LINUX wallpaper setter ======
#
# auto-generated file, DO NOT EDIT!

case $(( $(date +%s) % ~a )) in
~a
esac;

pkill swaybg || true \\
	&& echo \"setting current wallpaper: $WALL\" \\
	&& WAYLAND_DISPLAY=wayland-0 swaybg -i \"$WALL\" || true \\
	&& WAYLAND_DISPLAY=wayland-1 swaybg -i \"$WALL\" || true \\
	&& WAYLAND_DISPLAY=wayland-2 swaybg -i \"$WALL\" || true "
            len cases)))

(define (mk-random-wall-systemd-service script-path)
  (format #f "[Unit]
Description=Set Random Wallpaper
[Service]
Type=simple
ExecStart=/usr/bin/env bash ~a" script-path))

(define (mk-random-wall-systemd-timer)
  "[Unit]
Description=Timer to trigger random-wallpaper.service
[Timer]
OnCalendar=*-*-* *:00/10:00
Persistent=true
[Install]
WantedBy=timers.target")

;; --- Execution/Deployment Core ---

(define (install-wallpaper-config)
  (log-info s "Installing wallpaper management configuration")
  (load-local-overrides '(heks-linux wallpaper)
                        'wallpaper-settings)

  (let ((script-path (format #f "~a/~a"
                             (wallpaper-script-dir)
                             (wallpaper-script-filename))))
    
    (install-config-file! #:name (wallpaper-script-filename)
                          #:dir (wallpaper-script-dir)
                          #:contents (mk-random-wall-cmd (wallpapers)))

    (install-config-file! #:name (wallpaper-service-filename)
                          #:dir (wallpaper-systemd-dir)
                          #:contents (mk-random-wall-systemd-service
                                      script-path))

    (install-config-file! #:name (wallpaper-timer-filename)
                          #:dir (wallpaper-systemd-dir)
                          #:contents (mk-random-wall-systemd-timer))

    (syscall (format #f "chmod +x ~a" script-path))
    (log-success s "Installed wallpaper management configuration")))
