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

(define-module (heks-linux niri)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux wallpaper)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:export (niri-config install-niri-config
                        serialize-kdl
                        serialize-bindings
                        serialize-declaration
                        rule
                        make-rule
                        rule?
                        rule-selector
                        rule-declarations
                        set-rule-selector!
                        declaration
                        make-declaration
                        declaration?
                        declaration-property
                        declaration-value
                        prop
                        make-declaration-prop
                        declaration-prop
                        declaration-prop-props
                        rul
                        dec
                        niri-config-dir
                        niri-config-filename
                        niri-palette
                        niri-sans-font
                        niri-mono-font
                        niri-keyboard-layout
                        niri-caps-to-ctrl?
                        niri-extra-startups))

(define s
  (scriba-auto-logger))

(define-record-type rule
  (make-rule selector declarations) rule?
  (selector rule-selector set-rule-selector!)
  (declarations rule-declarations set-rule-declarations!))

(define* (rul selector . args)
  "Construct a KDL @code{rule} node with a given @var{selector} symbol and nested arguments.

@example
(rul 'cursor (dec 'theme \"Adwaita\"))
@end example"
  (make-rule selector
             (flatten-list args)))

(define-record-type declaration
  (make-declaration property value) declaration?
  (property declaration-property)
  (value declaration-value))

(define dec
  make-declaration)

(define-record-type declaration-prop
  (make-declaration-prop props) declaration-prop?
  (props declaration-prop-props))

(define prop
  make-declaration-prop)

;; =====================================================================
;; Configuration Parameters
;; =====================================================================

(define niri-config-dir
  (make-parameter (format #f "~a/.config/niri"
                          (or (getenv "HOME") "/tmp"))))

(define niri-config-filename
  (make-parameter "config.kdl"))

(define niri-palette
  (make-parameter (heks-linux-palette)))

(define niri-sans-font
  (make-parameter (heks-linux-sans-font)))

(define niri-mono-font
  (make-parameter (heks-linux-mono-font)))

(define niri-keyboard-layout
  (make-parameter (heks-linux-keyboard-layout)))

(define niri-caps-to-ctrl?
  (make-parameter (heks-linux-caps-to-ctrl?)))

(define niri-extra-startups
  (make-parameter '()))

;; =====================================================================
;; Configuration Logic
;; =====================================================================

(define* (niri-input-config #:key (caps-to-ctrl? (niri-caps-to-ctrl?))
                            (keyboard-layout (niri-keyboard-layout)))
  "Generate the KDL abstract syntax tree representing Niri keyboard and mouse input configurations."
  (rul 'input
       (rul 'keyboard
            (rul 'xkb
                 (dec 'layout keyboard-layout)
                 (dec 'options
                      (if caps-to-ctrl? "ctrl:nocaps" "")))
            (dec 'numlock #t))
       (rul 'touchpad
            (dec 'tap #t))
       (dec 'warp-mouse-to-focus #t)
       (dec 'focus-follows-mouse
            (prop '((max-scroll-amount "\"0%\""))))
       (dec 'workspace-auto-back-and-forth #t)))

(define* (niri-layout-config #:key (palette (niri-palette)))
  "Generate the KDL layout node matching visual elements like gaps, focus rings, and borders against a given @var{palette}."
  (rul 'layout
       (dec 'background-color "transparent")
       (dec 'gaps 10)
       (dec 'center-focused-column "never")
       (rul 'preset-column-widths
            (dec 'proportion 0.333333)
            (dec 'proportion 0.5)
            (dec 'proportion 0.666666))
       (rul 'default-column-width
            (dec 'proportion 0.666666))
       (rul 'focus-ring
            (dec 'width 2)
            (dec 'active-color
                 (get-color palette
                            'primary))
            (dec 'inactive-color
                 (get-color palette
                            'background-l)))
       (rul 'shadow
            (dec 'on #t)
            (dec 'draw-behind-window
                 'true)
            (dec 'softness 30)
            (dec 'spread 5)
            (dec 'offset
                 (prop '((x 0)
                         (y 5))))
            (dec 'color "#0007"))
       (rul 'struts
            (dec 'left 5)
            (dec 'right 5)
            (dec 'top 5)
            (dec 'bottom 5))))

(define (niri-intro)
  "Return a standard configuration file block comment warning."
  "// ====== Heks-Linux Niri configuration ======
//
// auto-generated file, DO NOT EDIT!")

(define (spawn-sh cmd)
  "Wrap shell command string @var{cmd} inside a Niri @code{spawn-sh} directive string."
  (format #f "spawn-sh \"~a\"" cmd))

(define (spawn-sh-at-startup cmd)
  "Wrap shell command string @var{cmd} inside a Niri @code{spawn-sh-at-startup} directive string."
  (format #f "spawn-sh-at-startup \"~a\"" cmd))

(define (swaylock-cmd background-image)
  "Construct a full CLI command execution block for executing @code{swaylock} matching the path @var{background-image}."
  (string-join (list "swaylock"
                     (format #f "--image ~a" background-image)
                     "--indicator-idle-visible"
                     "--scaling fill"
                     "--indicator-radius 120"
                     "--indicator-thickness 10"
                     "--ring-color cba6f7"
                     "--key-hl-color f5c2e7"
                     "--line-color 00000000"
                     "--inside-color 1e1e2e88"
                     "--separator-color 00000000"
                     "--text-color cdd6f4") " "))

(define (niri-bindings)
  "Compile the complete list of system-wide key bindings mappings used by the Heks environment manager window session."
  (list (bnd #:mod "s"
             #:bind "K"
             #:desc "Close focused window"
             #:cmd "close-window")
        (bnd #:mod "s"
             #:bind "O"
             #:desc "Toggle workspace overview layout"
             #:cmd "toggle-overview")
        (bnd #:mod "s"
             #:bind "?"
             #:desc "Show hotkey cheatsheet overlay"
             #:cmd "show-hotkey-overlay")

        ;; Audio controls
        (bnd #:mod "XF86AudioRaiseVolume"
             #:desc "Volume +5%"
             #:cmd (spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86AudioLowerVolume"
             #:desc "Volume -5%"
             #:cmd (spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86AudioMute"
             #:desc "Mute/Unmute toggle"
             #:cmd (spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86AudioPlay"
             #:desc "Media player play/pause toggle"
             #:cmd (spawn-sh "playerctl play-pause")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86AudioStop"
             #:desc "Media player stop"
             #:cmd (spawn-sh "playerctl stop")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86AudioPrev"
             #:desc "Media player previous track"
             #:cmd (spawn-sh "playerctl previous")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86AudioNext"
             #:desc "Media player next track"
             #:cmd (spawn-sh "playerctl next")
             #:allow-when-locked? #t)

        ;; Hardware monitors
        (bnd #:mod "XF86MonBrightnessUp"
             #:desc "Monitor brightness up"
             #:cmd (spawn-sh "brightnessctl set +5%")
             #:allow-when-locked? #t)
        (bnd #:mod "XF86MonBrightnessDown"
             #:desc "Monitor brightness down"
             #:cmd (spawn-sh "brightnessctl set 5%-")
             #:allow-when-locked? #t)

        ;; Session management
        (bnd #:mod "s-S"
             #:bind "Q"
             #:desc "Quit window session safely"
             #:cmd "quit")
        (bnd #:mod "C-M"
             #:bind "DEL"
             #:desc "Force terminate shell context"
             #:cmd "quit")
        (bnd #:mod "s-C"
             #:bind "E"
             #:desc "Restart core Emacs server process"
             #:cmd (spawn-sh
                    "bash ~/.local/bin/user-script-restart-emacs.bash"))

        ;; Core Applications
        (bnd #:mod "s"
             #:bind "T"
             #:desc "Launch Alacritty terminal emulator"
             #:cmd (spawn-sh "alacritty"))
        (bnd #:mod "s"
             #:bind "E"
             #:desc "Launch Emacs window manager frame"
             #:cmd (spawn-sh "emacsclient -c"))
        (bnd #:mod "s-S"
             #:bind "T"
             #:desc "Open sandboxed Eshell instance window"
             #:cmd (spawn-sh
                    "emacsclient -ce '(eshell \\\"new\\\")(rename-buffer (concat \\\"*eshell: \\\" (float-time) \\\"*\\\"))'"))
        (bnd #:mod "s-S"
             #:bind "E"
             #:desc "Open fallback terminal-mode Emacs client"
             #:cmd (spawn-sh
                    "alacritty -o 'keyboard.bindings=[]' -e emacsclient -t"))
        (bnd #:mod "s"
             #:bind "I"
             #:desc "Launch primary Web Browser instance"
             #:cmd (spawn-sh "google-chrome"))
        (bnd #:mod "s-S"
             #:bind "I"
             #:desc "Launch Nyxt programmatic web keyboard framework"
             #:cmd (spawn-sh "flatpak run engineer.atlas.Nyxt"))
        (bnd #:mod "s"
             #:bind "B"
             #:desc "Launch Nautilus visual file hierarchy explorer"
             #:cmd (spawn-sh "nautilus -w"))
        (bnd #:mod "s"
             #:bind "M"
             #:desc "Launch music player RMPC in terminal"
             #:cmd (spawn-sh "kitty -e 'rmpc'"))
        (bnd #:mod "s"
             #:bind "/"
             #:desc "Open Rofi system program application menu"
             #:cmd (spawn-sh "pkill rofi || rofi -show drun"))
        (bnd #:mod "s-S"
             #:bind "B"
             #:desc "Shuffle system decorative background canvas"
             #:cmd (spawn-sh
                    "bash ~/.local/bin/user-script-set-random-wallpaper"))
        (bnd #:mod "s-S"
             #:bind "D"
             #:desc "Start Lambdock dock process"
             #:cmd (spawn-sh "pkill lambdock || true; lambdock || true"))

        ;; Window states
        (bnd #:mod "s"
             #:bind "space"
             #:desc "Toggle selected layout floating mode status"
             #:cmd "toggle-window-floating")
        (bnd #:mod "s"
             #:bind "F"
             #:desc "Maximize width expansion of current column block"
             #:cmd "maximize-column")
        (bnd #:mod "s-S"
             #:bind "F"
             #:desc "Force total hardware screen full-display context"
             #:cmd "fullscreen-window")
        (bnd #:mod "s"
             #:bind "C"
             #:desc "Anchor active viewport targeted column horizontally"
             #:cmd "center-column")
        (bnd #:mod "s"
             #:bind ","
             #:desc "Merge adjacent floating frame windows inwards"
             #:cmd "consume-window-into-column")
        (bnd #:mod "s"
             #:bind "."
             #:desc "Extract bounded element node into solo row layout"
             #:cmd "expel-window-from-column")
        (bnd #:mod "s"
             #:bind "R"
             #:desc "Cycle across native desktop column geometry templates"
             #:cmd "switch-preset-column-width")
        (bnd #:mod "s"
             #:bind "ESC"
             #:desc "Inhibit active workspace application intercepts"
             #:cmd "toggle-keyboard-shortcuts-inhibit"
             #:allow-inhibiting? #f)
        (bnd #:mod "s"
             #:bind "L"
             #:desc "Lock environment layout layer instantly"
             #:cmd (spawn-sh (swaylock-cmd (car (wallpapers)))))
        (bnd #:mod "s-S"
             #:bind "/"
             #:desc "Show hotkey cheatsheet overlay fallback alternative"
             #:cmd "show-hotkey-overlay")

        ;; Media captures
        (bnd #:mod "s"
             #:bind "S"
             #:desc "Capture region screenshot snip clipping"
             #:cmd "screenshot")
        (bnd #:mod "s-S"
             #:bind "S"
             #:desc "Capture complete active monitor interface screenshot"
             #:cmd "screenshot-screen")
        (bnd #:mod "C-M"
             #:bind "S"
             #:desc "Capture standalone program window focus context"
             #:cmd "screenshot-window")
        (bnd #:mod "s-S"
             #:bind "G"
             #:desc "Toggle region GIF recording"
             #:cmd (spawn-sh "bash ~/.local/bin/gif-record"))

        ;; Structural focus navigation
        (bnd #:mod "s"
             #:bind "Left"
             #:desc "Focus element columns to the left"
             #:cmd "focus-column-left")
        (bnd #:mod "s"
             #:bind "Right"
             #:desc "Focus element columns to the right"
             #:cmd "focus-column-right")
        (bnd #:mod "s"
             #:bind "Down"
             #:desc "Shift active item viewport downstream"
             #:cmd "focus-window-down")
        (bnd #:mod "s"
             #:bind "Up"
             #:desc "Shift active item viewport upstream"
             #:cmd "focus-window-up")

        ;; Structural window moving
        (bnd #:mod "s-S"
             #:bind "Left"
             #:desc "Move focused column leftwards layout track"
             #:cmd "move-column-left")
        (bnd #:mod "s-S"
             #:bind "Right"
             #:desc "Move focused column rightwards layout track"
             #:cmd "move-column-right")
        (bnd #:mod "s-S"
             #:bind "Down"
             #:desc "Move target item structural placement down row"
             #:cmd "move-window-down")
        (bnd #:mod "s-S"
             #:bind "Up"
             #:desc "Move target item structural placement up row"
             #:cmd "move-window-up")

        ;; Cross-monitor navigation
        (bnd #:mod "C-M"
             #:bind "Left"
             #:desc "Focus display surface mapping leftwards"
             #:cmd "focus-monitor-left")
        (bnd #:mod "C-M"
             #:bind "Down"
             #:desc "Focus display surface mapping downwards"
             #:cmd "focus-monitor-down")
        (bnd #:mod "C-M"
             #:bind "Up"
             #:desc "Focus display surface mapping upwards"
             #:cmd "focus-monitor-up")
        (bnd #:mod "C-M"
             #:bind "Right"
             #:desc "Focus display surface mapping rightwards"
             #:cmd "focus-monitor-right")

        ;; Cross-monitor migration
        (bnd #:mod "C-M-S"
             #:bind "Left"
             #:desc "Migrate selected elements array leftward display"
             #:cmd "move-column-to-monitor-left")
        (bnd #:mod "C-M-S"
             #:bind "Down"
             #:desc "Migrate selected elements array downward display"
             #:cmd "move-column-to-monitor-down")
        (bnd #:mod "C-M-S"
             #:bind "Up"
             #:desc "Migrate selected elements array upward display"
             #:cmd "move-column-to-monitor-up")
        (bnd #:mod "C-M-S"
             #:bind "Right"
             #:desc "Migrate selected elements array rightward display"
             #:cmd "move-column-to-monitor-right")

        ;; Workspaces virtual navigation
        (bnd #:mod "s"
             #:bind "Page_Down"
             #:desc "Navigate context view downstream layer"
             #:cmd "focus-workspace-down")
        (bnd #:mod "s"
             #:bind "Page_Up"
             #:desc "Navigate context view upstream layer"
             #:cmd "focus-workspace-up")
        (bnd #:mod "s-S"
             #:bind "Page_Down"
             #:desc "Migrate target frame collections downstream layout"
             #:cmd "move-column-to-workspace-down")
        (bnd #:mod "s-S"
             #:bind "Page_Up"
             #:desc "Migrate target frame collections upstream layout"
             #:cmd "move-column-to-workspace-up")

        ;; Viewport scalings
        (bnd #:mod "s"
             #:bind "-"
             #:desc "Shrink column layout boundary size (-10%)"
             #:cmd "set-column-width \"-10%\"")
        (bnd #:mod "s"
             #:bind "="
             #:desc "Expand column layout boundary size (+10%)"
             #:cmd "set-column-width \"+10%\"")
        (bnd #:mod "s-S"
             #:bind "-"
             #:desc "Shrink window layout vertical geometry (-10%)"
             #:cmd "set-window-height \"-10%\"")
        (bnd #:mod "s-S"
             #:bind "="
             #:desc "Expand window layout vertical geometry (+10%)"
             #:cmd "set-window-height \"+10%\"")))

(define (niri-translate-mod mod)
  "Translate localized short-shorthand modifier flags into formal Niri modifier strings."
  (cond
    ((equal? "s" mod)
     "Mod")
    ((equal? "s-S" mod)
     "Mod+Shift")
    ((equal? "s-C" mod)
     "Mod+Ctrl")
    ((equal? "C-M" mod)
     "Ctrl+Alt")
    ((equal? "M" mod)
     "Alt")
    ((equal? "C-M-S" mod)
     "Ctrl+Alt+Shift")
    (else mod)))

(define (niri-translate-bind bind)
  "Convert canonical Lisp keyboard and mouse tokens to matching hardware identifiers used by Niri layout configuration bindings."
  (cond
    ((equal? "mouse-left" bind)
     "mouse:272")
    ((equal? "mouse-right" bind)
     "mouse:273")
    ((equal? "DEL" bind)
     "Delete")
    ((equal? "RET" bind)
     "Return")
    ((equal? "." bind)
     "Period")
    ((equal? "," bind)
     "Comma")
    ((equal? "?" bind)
     "question")
    ((equal? "-" bind)
     "Minus")
    ((equal? "=" bind)
     "Equal")
    ((equal? "/" bind)
     "slash")
    ((equal? "ESC" bind)
     "Escape")
    (else bind)))

(define (serialize-bindings xs)
  "Format an association list array of keybinding declarations @var{xs} into valid KDL key binding rulesets with inline hotkey overlay titles."
  (string-join (map (lambda (b)
                      (let* ((mod (niri-translate-mod (assoc-ref b
                                                                 'mod)))
                             (bind (assoc-ref b
                                              'bind))
                             (bind-suffix (if bind
                                              (format #f "+~a"
                                                      (niri-translate-bind
                                                       bind)) ""))
                             (desc (assoc-ref b
                                              'desc))
                             (desc-attr (if (and desc
                                                 (not (string-null? desc)))
                                            (format #f
                                             " hotkey-overlay-title=\"~a\""
                                             desc) ""))
                             (locked-attr (if (assoc-ref b
                                                         'allow-when-locked?)
                                              " allow-when-locked=true" ""))
                             (inhibiting-attr (if (not (assoc-ref b
                                                                  'allow-inhibiting?))
                                                  " allow-inhibiting=false" ""))
                             (cmd (assoc-ref b
                                             'cmd)))
                        (format #f
                                "~a~a~a~a~a { ~a; }"
                                mod
                                bind-suffix
                                desc-attr
                                locked-attr
                                inhibiting-attr
                                cmd))) xs) "\n  "))

(define* (bnd #:key mod
              bind
              cmd
              (desc #f)
              (allow-when-locked? #f)
              (allow-inhibiting? #t))
  "Helper builder initializing safe dictionary tables mapping hotkey definitions along with optional contextual strings."
  `((mod unquote mod)
    (bind unquote bind)
    (cmd unquote cmd)
    (desc unquote desc)
    (allow-when-locked? unquote allow-when-locked?)
    (allow-inhibiting? unquote allow-inhibiting?)))

(define* (niri-startup-programs #:key (palette (niri-palette))
                                (sans-font (niri-sans-font))
                                (mono-font (niri-mono-font))
                                (extra-startups (niri-extra-startups)))
  "Construct the list of environmental base system services and initial system visual targets executing upon startup layer initialization."
  (let* ((xs (append extra-startups
                     `("mako" "waybar"
                       "bash ~/.local/bin/user-script-set-random-wallpaper"
                       "alacritty --daemon"
                       "pkill lambdock || true; lambdock || true"
                       "emacs --daemon"
                       "podman system service --time=0 unix:///tmp/podman.sock"
                       "xdg-user-dirs-update"
                       "nm-applet"
                       "blueman-applet"
                       "sudo warp-svc"
                       "warp-taskbar"
                       "flatpak run com.onepassword.OnePassword --silent"
                       ,(format #f "fyi \\\"~a\\\" \\\"~a\\\""
                                (G_
                                 "Welcome to the Heks-Linux power user session")
                                (G_
                                 "Enter and explore, for the cosmos of computation is yours to command."))
                       "bash ~/.local/bin/write-gtk-dconf-settings"
                       "bash ~/.local/bin/write-heks-dconf-settings"))))
    xs))

(define* (serialized-startups #:key (palette (niri-palette))
                              (sans-font (niri-sans-font))
                              (mono-font (niri-mono-font))
                              (extra-startups (niri-extra-startups)))
  "Wrap and stitch mapped startup items into newline delimited KDL execution arrays."
  (string-join (map spawn-sh-at-startup
                    (niri-startup-programs #:palette palette
                                           #:sans-font sans-font
                                           #:mono-font mono-font
                                           #:extra-startups extra-startups))
               "\n"))

(define* (niri-config #:key (palette (niri-palette))
                      (sans-font (niri-sans-font))
                      (mono-font (niri-mono-font))
                      (keyboard-layout (niri-keyboard-layout))
                      (caps-to-ctrl? (niri-caps-to-ctrl?))
                      (extra-startups (niri-extra-startups)))
  "Assemble the master schema manifest containing layout properties, hooks, bindings, animations and rules ready for serialization."
  (list (niri-intro)
        (niri-input-config #:caps-to-ctrl? caps-to-ctrl?
                           #:keyboard-layout keyboard-layout)
        (niri-layout-config #:palette palette)
        (rul 'hotkey-overlay
             (dec 'skip-at-startup #t))
        (if (heks-linux-client-side-decorations?)
            (dec 'prefer-no-csd #f)
            (dec 'prefer-no-csd #t))
        (rul 'cursor
             (dec 'xcursor-size
                  (string->number (get-cursor-size palette)))
             (dec 'xcursor-theme
                  (get-cursor-theme palette)))
        (rul 'layer-rule
             (dec 'match
                  (prop '((namespace "\"^wallpaper$\""))))
             (dec 'place-within-backdrop
                  'true))
        (dec 'screenshot-path
             "~/Afbeeldingen/Schermafdrukken/screen-%Y-%m-%d-%H-%M-%S.png")
        (rul 'animations
             (dec 'slowdown 1.0))
        (rul 'binds
             (serialize-bindings (niri-bindings)))
        (rul 'window-rule
             (dec 'match
                  (prop '((app-id "\"^Alacritty$\""))))
             (rul 'background-effect
                  (dec 'blur
                       'true)))
        (rul 'window-rule
             (dec 'match
                  (prop '((app-id "\"^kitty$\""))))
             (rul 'background-effect
                  (dec 'blur
                       'true)))
        (rul 'window-rule
             (dec 'match
                  (prop '((app-id "\"^emacs$\""))))
             (rul 'background-effect
                  (dec 'blur
                       'true)))
        (rul 'layer-rule
             (dec 'match
                  (prop '((namespace "\"^rofi$\""))))
             (rul 'background-effect
                  (dec 'blur
                       'true)))
        (rul 'layer-rule
             (dec 'match
                  (prop '((namespace "\"^waybar$\""))))
             (rul 'background-effect
                  (dec 'blur
                       'true)))
        (rul 'window-rule
             (dec 'geometry-corner-radius 10)
             (dec 'clip-to-geometry
                  'true)
             (dec 'draw-border-with-background
                  'false)
             (rul 'default-column-width
                  (dec 'proportion 0.6666666)))
        (serialized-startups #:palette palette
                             #:sans-font sans-font
                             #:mono-font mono-font
                             #:extra-startups extra-startups)))

(define* (serialize-kdl xs
                        #:key (indent ""))
  "Recursively transform record definitions and vectors @var{xs} into string blocks validating KDL configuration semantics."
  (let* ((new-indent (format #f "~a~a" indent "  ")))
    (cond
      ((list? xs)
       (map (lambda (x)
              (serialize-kdl x
                             #:indent new-indent)) xs))
      ((rule? xs)
       (format #f
               "~a {\n~a~a\n~a}"
               (rule-selector xs)
               indent
               (cond
                 ((rule? (rule-declarations xs))
                  (serialize-kdl (rule-declarations xs)
                                 #:indent new-indent))
                 ((list? (rule-declarations xs))
                  (string-join (map (lambda (xx)
                                      (cond
                                        ((rule? xx)
                                         (serialize-kdl xx
                                                        #:indent new-indent))
                                        ((declaration? xx)
                                         (serialize-declaration xx))
                                        (else (format #f "~a" xx))))
                                    (rule-declarations xs))
                               (format #f "\n~a" indent)))
                 (else (begin
                         (serialize-declaration (rule-declarations xs)))))
               (string-drop indent 2)))
      ((declaration? xs)
       (serialize-declaration xs))
      (else (format #f "~a" xs)))))

(define (serialize-declaration xs)
  "Convert individual property-value configurations into structurally typed KDL declaration syntax values."
  (let ((val (declaration-value xs))
        (prop (declaration-property xs)))
    (cond
      ;; If the value is #f, return an empty string for the entire declaration.
      ((not val)
       "")

      ;; If the value is #t, just return the property (avoids a trailing space).
      ((eq? #t val)
       (format #f "~a" prop))

      ;; If the value is a declaration-prop, format its key-value pairs.
      ((declaration-prop? val)
       (format #f "~a ~a" prop
               (string-join (map (lambda (p)
                                   (format #f "~a=~a"
                                           (car p)
                                           (cadr p)))
                                 (declaration-prop-props val)) " ")))

      ;; If the value is a string, format it directly with quotes.
      ((string? val)
       (format #f "~a \"~a\"" prop val))

      ;; Fallback for other types (e.g., numbers).
      (else (format #f "~a ~a" prop val)))))

(define (install-niri-config)
  "Generate and serialize the target Heks Linux system active attributes pipeline configuration directly to disk space."
  (log-info s "Installing Niri configuration")
  (load-local-overrides '(heks-linux niri)
                        'niri-settings)
  (install-config-file! #:name (niri-config-filename)
                        #:dir (niri-config-dir)
                        #:contents (string-join (serialize-kdl (niri-config))
                                                "\n"))
  (log-success s "Installed Niri configuration"))
