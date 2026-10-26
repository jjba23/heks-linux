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
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 pretty-print)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (lambdock-config lambdock-config-dir lambdock-settings-filename
                            lambdock-styles-filename install-lambdock-config
                            lambdock-styles lambdock-theme
                            lambdock-screenshots-dir lambdock-hacking-dir
                            lambdock-downloads-dir))

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

;; ===========================================
;; The three stacks, and where they point
;; ===========================================

;; A stack is a dock icon that opens a popover with a folder's contents: the
;; macOS Downloads stack, three times.  Each one is a directory somebody has to
;; be able to override, because a machine keeps its screenshots and its
;; downloads wherever its owner said so.

;; The screenshots the compositor takes: the stack and niri's `screenshot-path'
;; are the same setting, so the folder the dock shows is the folder that fills
;; up.  A literal here and a different one there would have been an empty
;; popover with a plausible name.
(define lambdock-screenshots-dir
  (make-parameter (heks-linux-screenshots-dir)))

;; Everything checked out, which is where the projects live: the parent of this
;; configuration's own clone, so a machine that keeps its checkouts elsewhere
;; gets the right folder by saying so once.
(define lambdock-hacking-dir
  (make-parameter (dirname (heks-linux-clone-dir))))

;; And where a browser puts things it was asked to keep.
(define lambdock-downloads-dir
  (make-parameter (format #f "~a/Downloads" (or (getenv "HOME") "/tmp"))))

;; Free-form CSS appended verbatim to @file{styles.css}: the per-machine hook for
;; dock look-and-feel tweaks without forking lambdock.  Set it from your
;; @code{lambdock-settings.scm} override file to replace it entirely.
;;
;; It is empty, and it used to carry one rule.  That rule pulled *text* widgets
;; down onto the glass, because the shelf geometry makes the icon row overhang
;; it: `.dynamic-item:not(.dynamic-meter) { margin-bottom: -33px }'.  Two things
;; were wrong with it.  It selected a button class that separators carry too, so
;; every separator was asked for a negative height and GTK complained six times
;; per start ("reported min height -15, but sizes must be >= 0"); and the dock
;; now has no text widget to place - its dynamic items are all gauges, which are
;; icons and belong on the icon row, where the rule did not apply.
;;
;; lambdock names the label of a text item `.dynamic-item-label', so a dock that
;; puts one back should target that, and re-derive the offset: it was 33px for a
;; 48px icon, a -23px margin, 19px of front glass and a 0.38 mirror.
(define lambdock-styles
  (make-parameter ""))

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

    ;; Default icon pixel resolution.  48 is the size the shelf geometry below
    ;; was measured at, and it is also what makes 27 items fit a 1880-wide
    ;; logical screen: at 64 the last group ran off the right edge, and at 56 it
    ;; still did.  At 48 the shelf numbers below work out to a slab exactly one
    ;; icon tall.
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
    ;; dock, scaled to dock-icon-size: the slab ends up exactly one icon tall,
    ;; the icons overhang it by a little over a quarter icon and the mirrors fill
    ;; the glass in front of them:
    ;;
    ;;   slab height = icon + margin + front = 48 - 14 + 14 = 48px (1 icon)
    ;;   overhang    = -margin              = 14px (a little over a quarter icon)
    ;;   mirror band = round(icon * 0.30)   = 14px, exactly the front glass
    ;;
    ;; With the icons' bottom edge `front' pixels from the screen edge, their
    ;; centre lands 10px below the slab's top edge: embedded in the glass rather
    ;; than floating half an icon above it.
    ;;
    ;; They are independent knobs; lambdock derives the rest from them, so
    ;; changing dock-icon-size keeps the proportions.

    ;; Glass inside the icons (negative = the icons overhang it)
    (define dock-shelf-margin
      -14)

    ;; Glass in front of the icons, where the mirrors live
    (define dock-shelf-front
      14)

    ;; Room between the capsule's ends and the first/last icon (the reference
    ;; dock keeps about a quarter of an icon there; the theme's button padding
    ;; adds ~4px on top of this).
    (define dock-capsule-padding
      8)

    ;; Mirror height as a fraction of the icon size (0 = no mirrors)
    (define dock-reflection
      0.30)

    ;; Alpha of the mirror where it touches the icon
    (define dock-reflection-intensity
      0.70)

    ;; Blur radius as a fraction of the icon size
    (define dock-reflection-blur
      0.03)

    ;; The 10.9 slab is not a rectangle: it is wider where it meets the screen
    ;; than at the edge the icons overhang, which is what reads as a 3D shelf.
    ;; This is how much wider, per side, at dock-icon-size 48 (27px at 50px
    ;; icons in the reference shot).
    (define dock-shelf-flare
      24)

    ;; Orthographic, like the real 10.9 dock: no tilt.  The flare above does the
    ;; keystone; a tilt would additionally tip the slab towards the viewer.
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

    ;; Gap between items, in px.  The theme's own padding adds to it; four is
    ;; the theme's default and six reads as a dock that is spaced rather than
    ;; packed at this icon size.
    (define dock-item-spacing
      6)

    ;; The dock, grouped the way it is read: what you launch, what you work in,
    ;; what you make with, then the folders, then the gauges.
    ;;
    ;; Every launcher is a `preset-launcher' where lambdock has one - it is the
    ;; list of icons and commands the project keeps current - and an `app-item'
    ;; where it does not; a flatpak is its desktop id, which is what v0.10
    ;; matches windows and icons by.
    ;;
    ;; WezTerm runs the terminal, but the dock uses GNOME Terminal's icon for
    ;; it, so the launcher looks the same as a GNOME Terminal dock entry.
    (define dock-items
      (append
       ;; The launchpad first, where macOS keeps it: the dock is the short list,
       ;; the launchpad is everything installed.
       (preset-launchers-for 'nautilus)
       (list (launchpad-item))
       (list (app-item #:name "WezTerm"
                       #:exec "wezterm"
                       #:icon "org.gnome.Terminal"))
       ;; Look at, talk to, keep.
       (preset-launchers-for 'google-chrome
                             'firefox
                             'nyxt-flatpak
                             'gnome-calendar
                             'gnome-calculator
                             'zapzap-flatpak)
       (list (app-item #:name "Signal"
                       #:exec "flatpak run org.signal.Signal"
                       #:icon "org.signal.Signal"))
       (list (separator-item))
       ;; Work in.
       (preset-launchers-for 'emacs
                             'intellij
                             'bruno-flatpak)
       (list (separator-item))
       ;; Make with, and listen to.
       (preset-launchers-for 'spotify-flatpak
                             'gimp
                             'obs
                             'vlc)
       (list (separator-item))
       ;; The folders, in the order the day fills them up: what the compositor
       ;; just took, what is being worked on, what arrived.  A grid for the two
       ;; that fill with pictures and files, a list for the one that fills with
       ;; projects, because a hundred checkouts are read by name.
       (list (stack-item #:name "Screenshots"
                         #:icon "folder-pictures"
                         #:path ,(lambdock-screenshots-dir)
                         #:view-mode 'grid)
             (stack-item #:name "Hacking"
                         #:icon "folder"
                         #:path ,(lambdock-hacking-dir)
                         #:view-mode 'list)
             (stack-item #:name "Downloads"
                         #:icon "folder-download"
                         #:path ,(lambdock-downloads-dir)
                         #:view-mode 'grid))
       (list (separator-item))
       ;; The system: the window onto it, the mixer, the keyring - then the
       ;; gauges, the one kind of item that is an icon and a reading at the same
       ;; time.  Three, not four: the battery is a bar item, with its bolt and
       ;; its percentage, and a dock that repeats it is a dock that has run out
       ;; of room.
       (preset-launchers-for 'btop
                             'pavucontrol
                             'onepassword)
       (preset-launchers-for 'ram)))))

(define (lambdock-stack-directories)
  "Return the directories the dock's stacks show.

The three are created when the dock is installed: a stack whose folder does not
exist is a dock item that opens an empty popover, which reads as broken rather
than as empty."
  (list (lambdock-screenshots-dir)
        (lambdock-hacking-dir)
        (lambdock-downloads-dir)))

(define lambdock-config
  (make-parameter (with-output-to-string (lambda ()
                                           (for-each (lambda (expr)
                                                       (pretty-print expr)
                                                       (newline))
                                                     lambdock-settings)))))

(define* (install-lambdock-config)
  "Write @file{settings.scm} and @file{styles.css} to @code{lambdock-config-dir}.

The folders behind the dock's stacks are created first: a stack whose directory
does not exist opens an empty popover, and an empty popover reads as a broken
dock rather than as an empty folder.  Creating them is the difference between a
macOS Downloads stack and a dock item that does nothing.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/lambdock-settings.scm} first, which is how you
replace the dock item list or point @code{lambdock-styles} at your own CSS."
  (log-info s "Installing lambdock configuration")
  (load-local-overrides '(heks-linux lambdock)
                        'lambdock-settings)
  (for-each (lambda (directory)
              (ensure-directory-tree! directory)
              (log-info s "Stack folder: ~a" directory))
            (lambdock-stack-directories))
  (install-config-file! #:name (lambdock-settings-filename)
                        #:dir (lambdock-config-dir)
                        #:contents (lambdock-config))
  (install-config-file! #:name (lambdock-styles-filename)
                        #:dir (lambdock-config-dir)
                        #:contents (lambdock-styles))
  (log-success s "Installed lambdock configuration"))
