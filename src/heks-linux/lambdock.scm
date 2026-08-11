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

(define-module (heks-linux lambdock)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 pretty-print)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (lambdock-config lambdock-config-dir lambdock-settings-filename
                            lambdock-styles-filename install-lambdock-config
                            lambdock-styles))

(define s
  (scriba-auto-logger))

(define lambdock-settings-filename
  (make-parameter "settings.scm"))

(define lambdock-styles-filename
  (make-parameter "styles.css"))

(define lambdock-config-dir
  (make-parameter (format #f "~a/.config/lambdock"
                          (or (getenv "HOME") "/tmp"))))

;; Lambdock style overrides
(define lambdock-styles
  (make-parameter ""))

;; Lambdock settings
(define lambdock-settings
  `( ;Enable/disable smooth edge sliding auto-hide
     (define dock-auto-hide?
       #t)

    ;; Show dock when last window was closed
    (define dock-show-when-clear?
      #t)

    ;; Dock edge attachment: 'bottom | 'top | 'left | 'right
    (define dock-position
      'bottom)

    ;; Default icon pixel resolution
    (define dock-icon-size
      48)

    ;; Themes:
    ;; 'vanilla | 'vanilla-light | 'snow-leopard | 'solarized-light
    ;; 'nature | 'unity | 'none
    (define dock-theme
      ',(get-lambdock-theme (heks-linux-palette)))

    ;; 'all         -> Render dock on every connected monitor
    ;; "DP-1"       -> Target specific monitor output connector
    ;; 'default     -> Default compositor monitor assignment
    (define dock-monitor
      'all)

    ;; List of app ids to never show in the dock
    (define dock-exclude-apps
      '("warp-taskbar"))

    ;; Whether to enable the lambdock REPL
    (define dock-enable-repl?
      #t)

    ;; Whether to animate dock items when hovering on them with the mouse
    (define dock-hover-animate?
      #t)

    ;; Whether to keep track of open apps and windows and show indicators and popovers
    (define dock-track-windows?
      #t)

    (define dock-items
      (append (preset-launchers-for 'alacritty
                                    'google-chrome
                                    'spotify-flatpak
                                    'nautilus
                                    'nyxt-flatpak
                                    'gnome-calendar
                                    'gnome-calculator
                                    'zapzap-flatpak)
              (list (separator-item))
              (preset-launchers-for 'emacs
                                    'intellij
                                    'bruno-flatpak)
              (list (separator-item))
              (preset-launchers-for 'btop
                                    'pavucontrol
                                    'onepassword)
              (list (separator-item))
              (preset-launchers-for 'ram
                                    'cpu
                                    'cpu-temp
                                    'battery)))))

(define lambdock-config
  (make-parameter (with-output-to-string (lambda ()
                                           (for-each (lambda (expr)
                                                       (pretty-print expr)
                                                       (newline))
                                                     lambdock-settings)))))

(define* (install-lambdock-config)
  (log-info s "Installing lambdock configuration")
  (load-local-overrides '(heks-linux lambdock)
                        'lambdock-settings)
  (install-config-file! #:name (lambdock-settings-filename)
                        #:dir (lambdock-config-dir)
                        #:contents (lambdock-config))
  (install-config-file! #:name (lambdock-styles-filename)
                        #:dir (lambdock-config-dir)
                        #:contents (lambdock-styles))
  (log-success s "Installed lambdock configuration"))
