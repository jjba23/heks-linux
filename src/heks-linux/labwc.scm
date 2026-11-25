;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The second session: LabWC, where windows float and the compositor is quiet.
;;
;; Niri is a scrollable tiling compositor and the official path; that is a
;; decision about how a desktop should feel, not a claim that it is the only way
;; to feel.  A machine that runs three windows at a time, or a person who drags
;; things where they belong, wants the other shape: a stacking compositor where a
;; new window opens where it opens and stays there until it is moved.  LabWC is
;; that compositor - wlroots, Openbox's configuration vocabulary, one process and
;; no shell of its own.
;;
;; This module renders the session's five files, in the same shape as every other
;; module here: the keybindings are data, the theme is derived from the palette,
;; and the whole thing is a function of parameters.  What a prompt lists is not
;; one of them: that entry is a system file read by an account that cannot see
;; this home, so (heks-linux greeter) owns the list and the command it runs.
;; It is the same desktop around the compositor - whelk for the bar and the
;; launcher, Lambdock for the dock, Kitty and Emacs on the same keys - so
;; switching sessions changes how windows are managed and nothing else.
;;
;; It is honest about its testing: the spec asserts the text a LabWC release
;; would parse - well-formed XML, a key that names an action LabWC has, a theme
;; key that exists - and the configuration has since been read by a real LabWC
;; (0.20, headless backend): what that caught was a `<windowSwitcher>' in
;; `<core>', where LabWC does not look for it, and a `CloseMenu' action that no
;; LabWC release has ever had, neither of which the text of the file could show.
;; A session on a screen is still the test this module cannot run for you.
;;
;;; Code:

(define-module (heks-linux labwc)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (sxml simple)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux session)
  #:use-module (heks-linux toon)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux wallpaper)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (labwc-config-dir
            labwc-config-filename
            labwc-theme-filename
            labwc-autostart-filename
            labwc-environment-filename
            labwc-menu-filename
            labwc-palette
            labwc-sans-font
            labwc-mono-font
            labwc-gap
            labwc-corner-radius
            labwc-desktops
            labwc-whelk-preset
            labwc-bindings
            labwc-rc-xml
            labwc-themerc
            labwc-autostart
            labwc-environment
            labwc-menu-xml
            install-labwc-config))

(define s
  (scriba-auto-logger))

(define %home
  (or (getenv "HOME") "/tmp"))

(define labwc-config-dir
  (make-parameter (format #f "~a/.config/labwc" %home)))

(define labwc-config-filename
  (make-parameter "rc.xml"))

(define labwc-theme-filename
  (make-parameter "themerc-override"))

(define labwc-autostart-filename
  (make-parameter "autostart"))

(define labwc-environment-filename
  (make-parameter "environment"))

(define labwc-menu-filename
  (make-parameter "menu.xml"))

;; The session entry is not here: what a prompt lists is a system file, read by
;; an account that cannot see this home, so (heks-linux greeter) owns the list,
;; the entry and the command it runs.

(define labwc-palette
  (make-parameter (heks-linux-palette)))

(define labwc-sans-font
  (make-parameter (heks-linux-sans-font)))

(define labwc-mono-font
  (make-parameter (heks-linux-mono-font)))

;; A floating desktop still wants its windows to breathe.  Zero is the reference's
;; own answer - a stacking compositor's windows are drawn at their own size, so a
;; gap is only ever asked for by someone who wants one - and it is a parameter
;; because a laptop screen and a 4K monitor do not want the same number.
(define labwc-gap
  (make-parameter 0))

(define labwc-corner-radius
  (make-parameter 10))

;; The desktops this session has, as the names LabWC shows.  Four, because a
;; floating session's windows are not arranged onto one by the compositor: a
;; second desktop is simply where the second project goes.  The list is the one
;; place the count lives - the file's `<desktops>' and the numbered chords are
;; both printed from it, so a fifth desktop is a fifth key.
(define labwc-desktops
  (make-parameter '("one" "two" "three" "four")))

;; The bar this session wears.  whelk ships presets - the `xp' one is a
;; Luna-blue bottom taskbar with Start at the left, the notification area and a
;; 24-hour clock at the right - and WHELK_PRESET is how one session asks for a
;; bar without writing a second settings file: LabWC reads the environment file
;; below and exports it before the first client starts.  The empty string is the
;; answer for a machine that would rather have the same bar as Niri.
;;
;; shortcut: whelk's `tasks' module reads niri, sway, Hyprland or X11 IPC and has
;; no labwc backend yet, so the XP preset's task buttons are blank in this
;; session and the dock is the window list; drop this note when whelk reads the
;; wlr-foreign-toplevel protocol.
(define labwc-whelk-preset
  (make-parameter "xp"))

;; LabWC's binding vocabulary, written once as data.  The XML is a printer over
;; this list, so the reference and the configuration cannot disagree about what a
;; key does.  Keys are LabWC's spelling: `W' is Super, `S' is Shift, `C' is
;; Control, `A' is Alt, and a dash joins the modifiers to the key.
(define (labwc-bindings)
  "Return the LabWC keybindings, as alists of key, command and description.

The same chords as the Niri session wherever the action exists in both: a person
switching sessions should not have to learn a second set of keys to open a
terminal, lock the screen or take a screenshot."
  (append
   (list (list (cons 'key "W-Return")
               (cons 'cmd "kitty")
               (cons 'desc "Launch Kitty"))
         (list (cons 'key "W-e")
               (cons 'cmd "emacsclient -c")
               (cons 'desc "Launch Emacs frame"))
         (list (cons 'key "W-t")
               (cons 'cmd "kitty bash")
               (cons 'desc "Launch a shell in Kitty"))
         (list (cons 'key "W-i")
               (cons 'cmd "google-chrome")
               (cons 'desc "Launch Chrome"))
         (list (cons 'key "W-b")
               (cons 'cmd "nautilus -w")
               (cons 'desc "Launch Nautilus"))
         (list (cons 'key "W-m")
               (cons 'cmd "kitty rmpc")
               (cons 'desc "Launch RMPC"))
         (list (cons 'key "W-space")
               (cons 'cmd "whelk --launcher")
               (cons 'desc "Open the launcher"))
         (list (cons 'key "W-Tab")
               (cons 'cmd "whelk --launcher --launcher-mode=window")
               (cons 'desc "Switch between open windows"))
         (list (cons 'key "W-p")
               (cons 'cmd (format #f "whelk --menu ~a/.local/bin/heks-session-menu"
                                  %home))
               (cons 'desc "Open the session menu"))
         (list (cons 'key "W-v")
               (cons 'cmd "whelk --clipboard")
               (cons 'desc "Browse clipboard history"))
         (list (cons 'key "W-S-n")
               (cons 'cmd "whelk --dnd")
               (cons 'desc "Toggle do-not-disturb notifications"))
         (list (cons 'key "W-l")
               (cons 'cmd "whelk --lock")
               (cons 'desc "Lock the session"))
         (list (cons 'key "W-S-c")
               (cons 'cmd (toon-spawn-command (toon-palettes-command)))
               (cons 'desc "Open the palette chooser"))
         (list (cons 'key "W-S-w")
               (cons 'cmd (toon-spawn-command (toon-walls-command)))
               (cons 'desc "Browse the wallpapers"))
         (list (cons 'key "W-S-b")
               ;; The absolute path, as Niri's binding uses: a keybinding's PATH
               ;; is not the renderer's, and the bare name found nothing.
               (cons 'cmd (format #f "~a random" (wallpaper-script-command)))
               (cons 'desc "Shuffle the wallpaper"))
         (list (cons 'key "W-S-/")
               (cons 'cmd (toon-spawn-command (toon-keys-command)))
               (cons 'desc "Open the full keybinding reference"))
         (list (cons 'key "W-a")
               (cons 'cmd "heks-capture choose")
               (cons 'desc "Capture: screenshot, GIF or video"))
         (list (cons 'key "W-s")
               (cons 'cmd "heks-capture shot region")
               (cons 'desc "Screenshot a region"))
         (list (cons 'key "W-S-s")
               (cons 'cmd "heks-capture shot output")
               (cons 'desc "Screenshot the active monitor"))
         ;; Editing and recording, the same verbs the tiling session uses: the
         ;; capture program is one program and these are its words, not LabWC's.
         (list (cons 'key "C-M-s")
               (cons 'cmd "heks-capture shot window")
               (cons 'desc "Screenshot the focused window"))
         (list (cons 'key "W-x")
               (cons 'cmd "heks-capture annotate")
               (cons 'desc "Annotate the newest screenshot"))
         (list (cons 'key "W-S-x")
               (cons 'cmd "heks-capture studio")
               (cons 'desc "Open the screenshot and GIF editor menu"))
         (list (cons 'key "W-S-g")
               (cons 'cmd "heks-capture gif region")
               (cons 'desc "Record the selected region as a GIF"))
         (list (cons 'key "W-S-r")
               (cons 'cmd "heks-capture video output")
               (cons 'desc "Record the screen as a video"))
         (list (cons 'key "W-q")
               (cons 'cmd "close")
               (cons 'desc "Close the focused window"))
         (list (cons 'key "A-F4")
               (cons 'cmd "close")
               (cons 'desc "Close the focused window"))
         (list (cons 'key "W-Left")
               (cons 'cmd "snap-left")
               (cons 'desc "Snap the window to the left edge"))
         (list (cons 'key "W-Right")
               (cons 'cmd "snap-right")
               (cons 'desc "Snap the window to the right edge"))
         (list (cons 'key "W-Up")
               (cons 'cmd "snap-up")
               (cons 'desc "Snap the window to the top edge"))
         (list (cons 'key "W-Down")
               (cons 'cmd "snap-down")
               (cons 'desc "Snap the window to the bottom edge"))
         (list (cons 'key "W-f")
               (cons 'cmd "maximize")
               (cons 'desc "Maximise the focused window"))
         (list (cons 'key "W-S-f")
               (cons 'cmd "fullscreen")
               (cons 'desc "Toggle fullscreen"))
         (list (cons 'key "W-r")
               (cons 'cmd "reconfigure")
               (cons 'desc "Re-read the LabWC configuration"))
         (list (cons 'key "W-S-q")
               (cons 'cmd "exit")
               (cons 'desc "Quit the session"))
         ;; The two restarts: each one is a program a reconfigure changes and a
         ;; running copy has already loaded.  No dock chord: this session starts
         ;; whelk alone, so there is no dock to restart.
         (list (cons 'key "W-C-w")
               (cons 'cmd (whelk-restart-command))
               (cons 'desc "Restart the desktop shell"))
         (list (cons 'key "W-C-e")
               (cons 'cmd (emacs-daemon-restart-command))
               (cons 'desc "Restart the Emacs daemon"))
         (list (cons 'key "XF86AudioRaiseVolume")
               (cons 'cmd "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
               (cons 'desc "Volume +5%"))
         (list (cons 'key "XF86AudioLowerVolume")
               (cons 'cmd "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
               (cons 'desc "Volume -5%"))
         (list (cons 'key "XF86AudioMute")
               (cons 'cmd "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
               (cons 'desc "Mute or unmute"))
         ;; The transport keys, as in Niri: a person pressing play on their
         ;; keyboard should not have to know which compositor is running.
         (list (cons 'key "XF86AudioPlay")
               (cons 'cmd "playerctl play-pause")
               (cons 'desc "Play or pause the player"))
         (list (cons 'key "XF86AudioStop")
               (cons 'cmd "playerctl stop")
               (cons 'desc "Stop the player"))
         (list (cons 'key "XF86AudioPrev")
               (cons 'cmd "playerctl previous")
               (cons 'desc "Previous track"))
         (list (cons 'key "XF86AudioNext")
               (cons 'cmd "playerctl next")
               (cons 'desc "Next track"))
         (list (cons 'key "XF86MonBrightnessUp")
               (cons 'cmd "brightnessctl set +5%")
               (cons 'desc "Brightness +5%"))
         (list (cons 'key "XF86MonBrightnessDown")
               (cons 'cmd "brightnessctl set 5%-")
               (cons 'desc "Brightness -5%")))
   ;; The numbered desktops.  A desktop a key cannot reach is a desktop that is
   ;; not there, and LabWC's own answer - scrolling on the background - is not a
   ;; thing anybody discovers.
   (append-map
    (lambda (index)
      (list (list (cons 'key (format #f "W-~a" index))
                  (cons 'cmd `(action (@ (name "GoToDesktop")
                                         (to ,(number->string index)))))
                  (cons 'desc (format #f "Go to desktop ~a" index)))
            (list (cons 'key (format #f "W-S-~a" index))
                  (cons 'cmd `(action (@ (name "SendToDesktop")
                                         (to ,(number->string index))
                                         (follow "yes"))))
                  (cons 'desc (format #f "Move the window to desktop ~a"
                                      index)))))
    (iota (length (labwc-desktops)) 1))))

;; The XML below is SXML, not a template: the serializer escapes every value, so
;; a font name with an ampersand, a command with a quote or a palette colour
;; cannot produce a document LabWC refuses.  The comments above the root element
;; are not SXML and are joined around it.
(define (sxml->string tree)
  "Serialize @var{tree} as XML text."
  (call-with-output-string
    (lambda (port)
      (sxml->xml tree port))))

;;; Actions that are not an Execute: the chord names a verb, and the table says
;; how the installed LabWC spells it.  The values are SXML nodes, so the printer
;; and the escaping belong to the serializer rather than to four conditionals.
(define labwc-action-table
  '(("snap-left" action (@ (name "SnapToEdge") (direction "left")))
    ("snap-right" action (@ (name "SnapToEdge") (direction "right")))
    ("snap-up" action (@ (name "SnapToEdge") (direction "up")))
    ("snap-down" action (@ (name "SnapToEdge") (direction "down")))
    ("maximize" action (@ (name "ToggleMaximize")))
    ("fullscreen" action (@ (name "ToggleFullscreen")))
    ("close" action (@ (name "Close")))
    ("exit" action (@ (name "Exit")))
    ("reconfigure" action (@ (name "Reconfigure")))))

(define (labwc-action binding)
  "Return @var{binding}'s action as SXML.

A command is an @code{Execute} unless the table has a verb for it, and a binding
may also carry the action itself - the numbered desktops are one action per
key, and a table of eight rows would be eight places to mistype a number."
  (let* ((cmd (cdr (assq 'cmd binding)))
         (known (and (string? cmd) (assoc cmd labwc-action-table))))
    (cond
      [known (cdr known)]
      [(list? cmd) cmd]
      [else `(action (@ (name "Execute")) (command ,cmd))])))

(define (bindings-xml)
  "Return the keyboard section of @file{rc.xml}, as SXML."
  `(keyboard
    ,@(map (lambda (binding)
             `(keybind (@ (key ,(cdr (assq 'key binding))))
                       ,(labwc-action binding)))
           (labwc-bindings))))

(define* (labwc-rc-xml #:key (palette (labwc-palette))
                       (sans-font (labwc-sans-font))
                       (mono-font (labwc-mono-font)))
  "Return the @file{rc.xml} a LabWC session reads.

Floating is not a setting here: LabWC is a stacking compositor, and a window that
opens at 900x600 stays at 900x600 until it is moved.  What the file does say is
the part a stacking desktop still has to be told - the theme, the fonts, the
snapping and the keys - so the session is the same desktop in a different shape
rather than a different desktop.  The tree is SXML, so the fonts and every
command are escaped by the serializer."
  (string-append
   (string-join
    (list "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
          "<!-- ====== Heks-Linux LabWC configuration ======"
          "     auto-generated by heks-linux, DO NOT EDIT!"
          "     Rendered from (heks-linux labwc); edit that module instead. -->")
    "\n")
   "\n"
   (sxml->string
    `(labwc_config
      (core
       (gap ,(labwc-gap))
       (adaptiveSync "no")
       (allowShade "no")
       (reuseOutputMode "yes")
       (snapping (range 10) (topMaximize "yes")))
      (theme
       (name "Clearlooks")
       (cornerRadius ,(labwc-corner-radius))
       (font (@ (place "ActiveWindow"))
             (name ,sans-font) (size 11) (weight "Bold"))
       (font (@ (place "InactiveWindow"))
             (name ,sans-font) (size 11))
       (font (@ (place "MenuHeader"))
             (name ,sans-font) (size 11))
       (font (@ (place "MenuItem"))
             (name ,sans-font) (size 11))
       (font (@ (place "OnScreenDisplay"))
             (name ,mono-font) (size 12)))
      (focus
       (followMouse "no")
       (focusNew "yes")
       (raiseOnFocus "yes"))
      (placement (policy "center"))
      (desktops
       (number ,(length (labwc-desktops)))
       (names ,@(map (lambda (name) `(name ,name)) (labwc-desktops))))
      (resistance
       (screenEdgeStrength 20)
       (windowEdgeStrength 20))
      ,(bindings-xml)
      (mouse
       (default)
       (context (@ (name "Titlebar"))
                (mousebind (@ (button "Left") (action "Press"))
                           (action (@ (name "Raise")))
                           (action (@ (name "Focus"))))
                (mousebind (@ (button "Left") (action "Drag"))
                           (action (@ (name "Move"))))
                (mousebind (@ (button "Left") (action "DoubleClick"))
                           (action (@ (name "ToggleMaximize")))))
       (context (@ (name "Frame"))
                (mousebind (@ (button "Left") (action "Drag"))
                           (action (@ (name "Resize")))))
       (context (@ (name "Root"))
                ;; A left click on the desktop does one thing, and LabWC already
                ;; does it: an open menu closes on any click outside itself.
                ;; There is no `CloseMenu' action to name - the list is LabWC's,
                ;; and a name it does not have is a line in its log and a binding
                ;; that does nothing.
                (mousebind (@ (button "Right") (action "Press"))
                           (action (@ (name "ShowMenu") (menu "root-menu"))))))))))

(define* (labwc-themerc #:key (palette (labwc-palette)))
  "Return the Openbox-style theme override for @var{palette}.

The keys are LabWC's `themerc-override' vocabulary: the active title bar takes the
palette's own ink, the inactive one its dimmed sibling, and the border is the
accent - the same three roles the Niri rules and whelk's bar are given, so a
window on a light palette is not the one piece of the desktop still dressed for a
dark one."
  (let ((background (get-color palette 'background))
        (background-light (get-color palette 'background-l))
        (text (get-color palette 'text))
        (text-light (get-color palette 'text-l))
        (primary (get-color palette 'primary)))
    (string-join
     (list "# LabWC theme -- generated by heks-linux from the active palette;"
           "# edit (heks-linux labwc) instead, and run `maak install-labwc'."
           ""
           (format #f "window.active.title.bg.color: ~a" background)
           (format #f "window.active.label.text.color: ~a" text)
           (format #f "window.active.border.color: ~a" primary)
           (format #f "window.inactive.title.bg.color: ~a" background-light)
           (format #f "window.inactive.label.text.color: ~a" text-light)
           (format #f "window.inactive.border.color: ~a" background-light)
           "window.label.text.justify: center"
           "border.width: 1"
           "padding.width: 6"
           "padding.height: 6"
           ""
           (format #f "menu.items.bg.color: ~a" background)
           (format #f "menu.items.text.color: ~a" text)
           (format #f "menu.items.active.bg.color: ~a" primary)
           (format #f "menu.items.active.text.color: ~a" background)
           "menu.items.padding.x: 8"
           "menu.items.padding.y: 4"
           ""
           (format #f "osd.bg.color: ~a" background)
           (format #f "osd.label.text.color: ~a" text)
           "osd.border.color: #00000000"
           ""
           (format #f "window.active.button.unpressed.image.color: ~a" text)
           (format #f "window.inactive.button.unpressed.image.color: ~a"
                   text-light))
     "\n")))

(define (labwc-autostart)
  "Return the @file{autostart} script: the desktop around the compositor.

The list is @code{(heks-linux session)}'s, so LabWC starts the same shell,
editor daemon, container service, password manager and agent as Niri - and not
the dock: whelk's XP preset is the taskbar here, and one bar with the windows on
it is the whole point of the arrangement.  Everything runs in the background
because LabWC runs the script again on a reconfigure, and the script waits so the
session has one autostart process for as long as it lives."
  (string-join
   (append (list "#!/usr/bin/env bash"
                 "# ====== Heks-Linux LabWC session autostart ======"
                 "# auto-generated by heks-linux, DO NOT EDIT!"
                 ""
                 "set -u"
                 "")
           (map (lambda (command) (format #f "~a &" command))
                (session-startup-programs #:dock? #f))
           (list "wait"))
   "\n"))

(define (labwc-environment)
  "Return the @file{environment} file: what a session announces about itself.

LabWC reads one @code{KEY=value} per line and exports it before the first client
starts.  The desktop is named here so a program that asks - a browser's
@code{user.js}, a GTK app, an installer - gets an answer rather than an empty
string, and @code{WHELK_PRESET} is the one variable that decides which bar this
session wears: whelk reads it at start, so the floating session gets the XP
taskbar without a second settings file."
  (string-join
   (append
    (list "# Heks-Linux LabWC session environment -- generated, do not edit."
          "XDG_CURRENT_DESKTOP=heks:labwc"
          "XDG_SESSION_DESKTOP=heks-labwc"
          (format #f "XCURSOR_THEME=~a" (get-cursor-theme (labwc-palette)))
          (format #f "XCURSOR_SIZE=~a" (get-cursor-size (labwc-palette)))
          "QT_QPA_PLATFORM=wayland"
          "MOZ_ENABLE_WAYLAND=1")
    (if (string-null? (labwc-whelk-preset))
      '()
      (list (format #f "WHELK_PRESET=~a" (labwc-whelk-preset))))
    (map (lambda (variable)
           (format #f "~a=~a" (car variable) (cdr variable)))
         (session-environment)))
   "\n"))

(define (labwc-menu-xml)
  "Return the root menu @file{menu.xml}, the right-click menu on the desktop.

The menu is SXML too: a label with an ampersand or a command with a quote is
escaped where it is written, not by every caller."
  (string-append
   (string-join
    (list "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
          "<!-- ====== Heks-Linux LabWC menu ====== -->"
          "<!-- auto-generated by heks-linux, DO NOT EDIT! -->")
    "\n")
   "\n"
   (sxml->string
    '(openbox_menu
      (menu (@ (id "root-menu") (label "Heks"))
            (item (@ (label "Terminal"))
                  (action (@ (name "Execute")) (command "kitty")))
            (item (@ (label "Emacs"))
                  (action (@ (name "Execute")) (command "emacsclient -c")))
            (item (@ (label "Browser"))
                  (action (@ (name "Execute")) (command "google-chrome")))
            (item (@ (label "Files"))
                  (action (@ (name "Execute")) (command "nautilus -w")))
            (separator)
            (item (@ (label "Launcher"))
                  (action (@ (name "Execute")) (command "whelk --launcher")))
            (item (@ (label "Keyboard reference"))
                  (action (@ (name "Execute")) (command "heks-toon")))
            (separator)
            (item (@ (label "Re-read the configuration"))
                  (action (@ (name "Reconfigure"))))
            (item (@ (label "Log out"))
                  (action (@ (name "Exit")))))))
   "\n"))

(define (install-labwc-config)
  "Write the LabWC session into the user's configuration.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/labwc-settings.scm} first, so a machine can pin
a gap, a corner radius or the palette the session wears without touching the
module.  The autostart script is written executable; LabWC runs it with the
session's own shell."
  (log-info s "Installing LabWC configuration")
  (load-local-overrides '(heks-linux labwc) 'labwc-settings)
  (install-config-file! #:name (labwc-config-filename)
                        #:dir (labwc-config-dir)
                        #:contents (labwc-rc-xml))
  (install-config-file! #:name (labwc-theme-filename)
                        #:dir (labwc-config-dir)
                        #:contents (labwc-themerc))
  (install-config-file! #:name (labwc-menu-filename)
                        #:dir (labwc-config-dir)
                        #:contents (labwc-menu-xml))
  (install-config-file! #:name (labwc-environment-filename)
                        #:dir (labwc-config-dir)
                        #:contents (labwc-environment))
  (install-config-file! #:name (labwc-autostart-filename)
                        #:dir (labwc-config-dir)
                        #:contents (labwc-autostart)
                        #:perms 493)
  (log-success s "Installed LabWC configuration"))

;;; labwc.scm ends here
