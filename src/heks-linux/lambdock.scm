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
;; The dock theme is the OS X Mavericks material by default -- the dock is
;; deliberately dressed as the 10.9 dock, shelf and all -- and can be pointed back
;; at the palette with @code{lambdock-theme}.  The dock item list is built from
;; lambdock's own @code{preset-launchers-for} vocabulary, so adding an icon means
;; adding a symbol to @code{dock-items} below.
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
                            lambdock-styles lambdock-theme))

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

;; Free-form CSS appended verbatim to @file{styles.css}: the per-machine hook for
;; dock look-and-feel tweaks without forking lambdock.  Set it from your
;; @code{lambdock-settings.scm} override file to replace it entirely.
;;
;; It carries one rule by default.  The shelf geometry below makes the icons
;; overhang the glass, and lambdock draws every item on that same row, so the
;; text widgets (CPU, RAM, temperature) would hang over the wallpaper instead of
;; sitting on the slab.  Pulling them down by the row's offset from the centre of
;; the slab fixes that: 33px is that offset for a 48px icon, a -22px margin, 18px
;; of front glass and a 0.28 mirror.  Re-check it if you change those numbers.
(define lambdock-styles
  (make-parameter
   "\
/* heks-linux: keep the text widgets (CPU, RAM, temperature) on the glass
   instead of on the overhanging icon row. */
.dynamic-item {
  margin-bottom: -33px;
}
"))

;; The material the dock is dressed in.  Each palette names a lambdock theme, so
;; by default the dock follows the palette like every other surface; here it is
;; pinned to the OS X Mavericks platinum slab instead, which is what the shelf
;; geometry below is shaped for.  Set it to @code{#f} to fall back to the
;; palette's own theme (the geometry stays: any theme can wear it).
(define lambdock-theme
  (make-parameter
   'macos-mavericks
   (lambda (theme)
     (if theme
         theme
         (get-lambdock-theme (heks-linux-palette))))))

;; The dock definition, expressed in lambdock's own vocabulary.  Kept as a list
;; of @code{(define …)} forms so it can be pretty-printed directly; see the
;; module commentary for why this module is the exception to the
;; "configuration as data" rule.
;;
;; Notable keys:
;; - @code{dock-position}: 'bottom, 'top, 'left or 'right.
;; - @code{dock-icon-size}: default pixel resolution of the launcher icons.
;; - @code{dock-theme}: the material, from @code{lambdock-theme} (the OS X
;;   Mavericks platinum slab unless the palette is asked for).
;; - @code{dock-shelf-*}, @code{dock-reflection*}: the shelf geometry that turns
;;   the capsule into the Mavericks slab -- icons overhanging the glass, short
;;   blurred mirrors in front of them.  Each knob is independent; lambdock's
;;   README has the table and the "platinum slab" recipe these numbers come from.
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
    ;; 'vanilla | 'vanilla-light | 'snow-leopard | 'snow-leopard-dark
    ;; 'solarized-light | 'nature | 'unity
    ;; 'macos-big-sur | 'macos-ventura | 'macos-mavericks
    ;; 'windows-xp | 'windows-10 | 'windows-11 | 'none
    (define dock-theme
      ',(lambdock-theme))

    ;; The glass shelf.  These numbers shape the capsule into the OS X Mavericks
    ;; dock: a light platinum slab the icons overhang, with short blurred mirrors
    ;; fading over the glass in front of them.  lambdock derives all the geometry
    ;; from them (margin and front are glass thickness, reflection is a fraction
    ;; of the icon size), so the dock follows dock-icon-size automatically.

    ;; Glass inside the icons (negative = the icons overhang it)
    (define dock-shelf-margin
      -22)

    ;; Glass in front of the icons, where the mirrors live
    (define dock-shelf-front
      18)

    ;; Mirror height as a fraction of the icon size (0 = no mirrors)
    (define dock-reflection
      0.28)

    ;; Alpha of the mirror where it touches the icon
    (define dock-reflection-intensity
      0.5)

    ;; Blur radius as a fraction of the icon size
    (define dock-reflection-blur
      0.05)

    ;; Orthographic, like the real 10.9 dock: no tilt
    (define dock-shelf-tilt
      0)

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
