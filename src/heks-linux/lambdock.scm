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
;; Renders @file{~/.config/lambdock/settings.scm} and @file{styles.css}, the two
;; files read by [[https://codeberg.org/jjba23/lambdock][lambdock]], the Wayland-native
;; GTK4 dock used as the macOS-style application dock.
;;
;; Unlike the other modules, lambdock's configuration format is @emph{itself}
;; Scheme: a sequence of top-level @code{(define …)} forms.  The module therefore
;; keeps that textually and pretty-prints it with @code{pretty-print} rather than
;; serializing an association list - this is the one place where the generated
;; artefact is code, not data.
;;
;; The dock theme is derived from the palette registry, and the dock item list is
;; built from lambdock's own @code{preset-launchers-for} vocabulary, so adding an
;; icon means adding a symbol to @code{dock-items} below.
;;
;; @code{lambdock-styles} is a parameter holding free-form CSS appended to the
;; generated @file{styles.css}; it defaults to the empty string and is the
;; intended hook for per-machine look-and-feel tweaks.

;;; Code:

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

;; Name of the generated Scheme settings file.  lambdock loads exactly this
;; name from its configuration directory.
(define lambdock-settings-filename
  (make-parameter "settings.scm"))

;; Name of the generated stylesheet.
(define lambdock-styles-filename
  (make-parameter "styles.css"))

;; Directory receiving both files; defaults to @file{~/.config/lambdock}.
(define lambdock-config-dir
  (make-parameter (format #f "~a/.config/lambdock"
                          (or (getenv "HOME") "/tmp"))))

;; Free-form CSS appended verbatim to @file{styles.css}.  Empty by default; a
;; convenient place to override lambdock styling without forking it.  Set it from
;; your @code{lambdock-settings.scm} override file.
(define lambdock-styles
  (make-parameter ""))

;; The dock definition, expressed in lambdock's own vocabulary.  Kept as a list
;; of @code{(define …)} forms so it can be pretty-printed directly; see the
;; module commentary for why this module is the exception to the
;; "configuration as data" rule.
;;
;; Notable keys:
;; - @code{dock-position}: 'bottom, 'top, 'left or 'right.
;; - @code{dock-icon-size}: default pixel resolution of the launcher icons.
;; - @code{dock-theme}: derived from the palette, so the dock matches the rest of
;;   the session.  Run @code{maak install-lambdock} after changing palettes.
;; - @code{dock-monitor}: 'all renders on every connected output.
;; - @code{dock-exclude-apps}: window taskbar ids that must never be listed.
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

    ;; WezTerm runs the terminal, but the dock uses GNOME Terminal's icon for
    ;; it, so the launcher looks the same as a GNOME Terminal dock entry.
    (define dock-items
      (append (list (app-item #:name "WezTerm"
                              #:exec "wezterm"
                              #:icon "org.gnome.Terminal"))
              (preset-launchers-for 'google-chrome
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
              (preset-launchers-for 'cpu
                                    'ram
                                    'cpu-temp)))))

(define lambdock-config
  (make-parameter (with-output-to-string (lambda ()
                                           (for-each (lambda (expr)
                                                       (pretty-print expr)
                                                       (newline))
                                                     lambdock-settings)))))

(define* (install-lambdock-config)
  "Write @file{settings.scm} and @file{styles.css} to @code{lambdock-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/lambdock-settings.scm} first, which is how you
replace the dock item list or point @code{lambdock-styles} at your own CSS."
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
