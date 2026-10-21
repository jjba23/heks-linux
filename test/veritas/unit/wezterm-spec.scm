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
;; Unit tests for (heks-linux wezterm).
;;
;; WezTerm is the one terminal in this project whose bindings are conditional:
;; the generated Lua asks each pane which process is in front of it, so the
;; tests are about the two halves of that promise.  The first half is that the
;; chords are registered at all (they are the Emacs ones), and the second is
;; that the configuration hands them back to the application - which is checked
;; by asserting on the runtime the installer emits, since the decision is made by
;; Lua at key-press time and not here.
;;
;; The assertions on the emitted text are deliberately narrow: a typo in an
;; action name makes WezTerm fail to load the whole file, and `wezterm
;; show-keys' is the only thing that can catch it, so what is checked here is the
;; shape of each binding and the presence of the guards around them.

;;; Code:

(define-module (veritas unit wezterm-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux wezterm)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:export (spec))

(define (render-wezterm-config)
  "Render the WezTerm configuration the way it is written to disk."
  (serialize-wezterm-config #:config (wezterm-config)))

(define (wezterm-conf-occurs? fragment)
  (not (eq? #f
            (string-contains (render-wezterm-config) fragment))))

(define (wezterm-section-banners)
  "Return the section banners of the generated file."
  (filter (lambda (line)
            (string-prefix? "-- ===== " line))
          (string-split (render-wezterm-config) #\newline)))

(define (wezterm-banners-aligned?)
  "Return @code{#t} when every section banner of the generated file is as wide
as the others."
  (let ((banners (wezterm-section-banners)))
    (and (not (null? banners))
         (apply =
                (map string-length banners)))))

(define (modifier-translation-suite)
  (suite "Modifier Translation"
         (test "Short Modifiers Use WezTerm Spelling"
               (assert-equal #:expect "CTRL|SHIFT"
                             #:got (translate-wezterm-mods "C-S")
                             #:name "Modifiers are joined with a vertical bar")
               (assert-equal #:expect "ALT|SUPER"
                             #:got (translate-wezterm-mods "M-s")
                             #:name "Alt and Super are spelled out")
               (assert-equal #:expect "CTRL|Custom"
                             #:got (translate-wezterm-mods "C-Custom")
                             #:name "Unknown modifiers pass through"))))

(define (lua-value-suite)
  (suite "Lua Value Serialization"
         (test "Scalars Render As Lua Literals"
               (assert-equal #:expect "true"
                             #:got (serialize-wezterm-value #t)
                             #:name "Booleans render unquoted")
               (assert-equal #:expect "false"
                             #:got (serialize-wezterm-value #f)
                             #:name "False renders unquoted")
               (assert-equal #:expect "12"
                             #:got (serialize-wezterm-value 12)
                             #:name "Numbers render unquoted")
               (assert-equal #:expect "'bash'"
                #:got (serialize-wezterm-value "bash")
                #:name "Strings are single-quoted so they need no escapes"))
         (test "Table Names Are Bracketed When Lua Needs It"
               (assert-equal #:expect "scrollback_lines"
                             #:got (serialize-wezterm-name "scrollback_lines")
                             #:name "A valid identifier is emitted bare")
               (assert-equal #:expect "['emacs-cx']"
                             #:got (serialize-wezterm-name "emacs-cx")
                             #:name "A name with a dash is bracketed"))
         (test "Tables Are Laid Out One Entry Per Line"
               (assert-equal #:expect "{
  foreground = '#ffffff',
  background = '#1d2021',
}"
                             #:got (serialize-wezterm-value '(("foreground" . "#ffffff")
                                                              ("background" . "#1d2021")))
                             #:name "An object becomes an indented table")
               (assert-equal #:expect "{\n  'bash',\n}"
                             #:got (serialize-wezterm-value '("bash"))
                             #:name "An array becomes an indented table")
               (assert-equal #:expect "{ left = 16, top = 4 }"
                             #:got (serialize-wezterm-value (wezterm-compact '
                                                                             ((left . 16)
                                                                              (top . 4))))
                             #:name "A compact table stays on one line"))
         (test "Literal Lua Passes Through"
               (assert-equal #:expect "act.TogglePaneZoomState"
                             #:got (serialize-wezterm-value (wezterm-raw-lua
                                                             "act.TogglePaneZoomState"))
                             #:name "A raw fragment is emitted verbatim")
               (assert-equal #:expect #t
                             #:got (wezterm-raw-lua? (wezterm-raw-lua "x"))
                             #:name "Raw fragments are recognisable"))))

(define (binding-serialization-suite)
  (suite "Binding Serialization"
         (test "Bindings Render As Inline Lua Tables"
               (assert-equal #:expect
                "{ key = 'y', mods = 'CTRL', action = act.PasteFrom 'Clipboard' }"
                #:got (serialize-wezterm-key #:key "y"
                                             #:mods "C"
                                             #:action
                                             "act.PasteFrom 'Clipboard'")
                #:name "A key assignment is one inline table")
               (assert-equal #:expect
                "{ key = 'PageUp', mods = 'SHIFT', action = act.ScrollByPage(-1) }"
                #:got (serialize-wezterm-key #:key "PageUp"
                                             #:mods "S"
                                             #:action "act.ScrollByPage(-1)")
                #:name "A named key keeps its WezTerm spelling"))
         (test "Prefix Entries Carry No Modifier"
               (assert-equal #:expect
                "{ key = '2', action = act.TogglePaneZoomState }"
                #:got (serialize-wezterm-prefix-entry #:key "2"
                       #:action "act.TogglePaneZoomState")
                #:name "The runtime adds the modifiers a prefix needs"))))

(define (guarded-binding-suite)
  (suite "Guarded Bindings"
         (test "The Emacs Chords Are Registered"
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'y', mods = 'CTRL', action = act.PasteFrom 'Clipboard' }")
                            #:name "Control+Y pastes")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'w', mods = 'ALT', action = act.CopyTo 'ClipboardAndPrimarySelection' }")
                            #:name "Alt+W copies")
               (assert-true (wezterm-conf-occurs?
                             "{ key = '=', mods = 'CTRL', action = act.IncreaseFontSize }")
                #:name "Control+= grows the font, as text-scale-increase does")
               (assert-true (wezterm-conf-occurs?
                             "{ key = '-', mods = 'CTRL', action = act.DecreaseFontSize }")
                #:name
                "Control+- shrinks the font, as text-scale-decrease does")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'LeftArrow', mods = 'SHIFT', action = act.ActivatePaneDirection 'Left' }")
                            #:name "Shift+arrow moves like windmove")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'PageUp', mods = 'SHIFT', action = act.ScrollByPage(-1) }")
                            #:name "Shift+PageUp pages the scrollback"))
         (test "The Emacs Page Keys Are Claimed"
               ;; The guard is what makes this possible: Alacritty and kitty
               ;; have to leave C-v / M-v alone, WezTerm can bind them and hand
               ;; them back while a pager or Emacs owns the keyboard.
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'v', mods = 'CTRL', action = act.ScrollByPage(1) }")
                            #:name "Control+V pages the scrollback forward")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'v', mods = 'ALT', action = act.ScrollByPage(-1) }")
                            #:name "Alt+V pages the scrollback back"))
         (test "The Bare Defaults Are Re-Registered Through The Guard"
               ;; WezTerm ships a few bindings on a bare modifier; a binding the
               ;; terminal owns never reaches the application, so each of them
               ;; appears a second time here, in the guarded array, with the same
               ;; action as its fallback.
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) }")
                            #:name "Control+Tab still switches tabs")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'Enter', mods = 'ALT', action = act.ToggleFullScreen }")
                            #:name "Alt+Enter still toggles full screen")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'Insert', mods = 'CTRL', action = act.CopyTo 'PrimarySelection' }")
                            #:name "Control+Insert still copies the selection")
               (assert-equal #:expect 6
                             #:got (length (wezterm-default-keys))
                             #:name "Every guarded default is registered exactly once"))
         (test "Every Chord Is Guarded"
               ;; A guarded chord is wrapped in a callback that first asks which
               ;; process owns the pane; an unguarded one would simply run its
               ;; action and the application would never see the key.
               (assert-true (wezterm-conf-occurs?
                             "action = wezterm.action_callback")
                            #:name "Chords are dispatched through a callback")
               (assert-true (wezterm-conf-occurs?
                             "get_foreground_process_name")
                #:name "The callback asks the pane which process is in front")
               (assert-true (wezterm-conf-occurs?
                             "window:perform_action(send_key(spec), pane)")
                            #:name "The chord is re-sent to the application")
               (assert-true (wezterm-conf-occurs?
                             "window:perform_action(spec.action, pane)")
                #:name "The terminal only acts when the keyboard is free"))))

(define (passthrough-suite)
  (suite "Passthrough"
         (test "Emacs And The Pager Own The Keyboard"
               (assert-true (wezterm-conf-occurs? "  'emacs',")
                            #:name
                            "Emacs is declared as an owning application")
               (assert-true (wezterm-conf-occurs? "  'less',")
                            #:name "less is declared as an owning application")
               (assert-equal #:expect #t
                             #:got (not (eq? #f
                                             (member "emacs"
                                                     (wezterm-yield-apps))))
                             #:name "Emacs is in the default application list")
               (assert-equal #:expect #t
                             #:got (not (eq? #f
                                             (member "less"
                                                     (wezterm-yield-apps))))
                             #:name "less is in the default application list"))
         (test "The Application List Is Matched On The Base Name"
               (assert-true (wezterm-conf-occurs?
                             "local base = basename(name):lower()")
                            #:name
                            "A full path such as /usr/bin/less still matches")
               (assert-true (wezterm-conf-occurs?
                             "return (path:gsub('^.*/', ''))")
                #:name "The directory part of the process name is dropped")
               (assert-true (wezterm-conf-occurs?
                             "yield_patterns[#yield_patterns + 1] = '^' .. app .. '[%-_.%d]*$'")
                            #:name
                            "A version suffix is allowed, so python3.13 matches python")
               (assert-true (wezterm-conf-occurs? "base:match(pattern)")
                            #:name
                            "The base name is matched against the compiled patterns"))))

(define (emacs-prefix-suite)
  (suite "Emacs Prefix"
         (test "Control+X Opens The Prefix Table"
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'x', mods = 'CTRL', action = act.ActivateKeyTable { name = 'emacs-cx'")
                            #:name "Control+X activates the table")
               (assert-true (wezterm-conf-occurs? "until_unknown = true")
                            #:name "An unknown second key leaves the table")
               (assert-true (wezterm-conf-occurs? (format #f
                                                   "timeout_milliseconds = ~a"
                                                   (wezterm-prefix-timeout)))
                            #:name "An abandoned prefix gives up on its own"))
         (test "Window Commands Keep Their Emacs Keys"
               (assert-true (wezterm-conf-occurs?
                             "{ key = '2', action = act.SplitVertical")
                            #:name "Control+X 2 splits below")
               (assert-true (wezterm-conf-occurs?
                             "{ key = '3', action = act.SplitHorizontal")
                            #:name "Control+X 3 splits right")
               (assert-true (wezterm-conf-occurs?
                             "{ key = '0', action = act.CloseCurrentPane")
                            #:name "Control+X 0 closes the pane")
               (assert-true (wezterm-conf-occurs?
                             "{ key = '1', action = act.TogglePaneZoomState }")
                            #:name "Control+X 1 leaves one pane")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'o', action = act.ActivatePaneDirection 'Next' }")
                            #:name "Control+X o moves to the next pane")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'b', action = act.PaneSelect }")
                            #:name "Control+X b picks a pane like a buffer")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'g', action = act.PopKeyTable }")
                            #:name "Control+X g quits the prefix")
               (assert-true (wezterm-conf-occurs?
                             "{ key = 'RightArrow', action = act.ActivateTabRelative(1) }")
                            #:name "Control+X <right> moves to the next tab"))
         (test "A Prefix Matches With Control Held Or Released"
               (assert-true (wezterm-conf-occurs?
                             "for _, mods in ipairs { 'NONE', 'CTRL' }")
                            #:name
                            "Each entry is expanded into both spellings"))))

(define (generated-file-suite)
  (suite "Generated File"
         (test "The File Is Self-Describing"
               (assert-true (wezterm-conf-occurs?
                             "-- ====== Heks-Linux WezTerm configuration ======")
                            #:name "The file carries a generated-file header")
               (assert-true (wezterm-conf-occurs? "DO NOT EDIT!")
                            #:name "The header says not to edit the file")
               (assert-true (wezterm-conf-occurs? "src/heks-linux/wezterm.scm")
                            #:name "The header names the source of truth")
               (assert-true (wezterm-conf-occurs?
                             "local config = wezterm.config_builder()")
                            #:name
                            "The configuration is built from the builder")
               (assert-true (wezterm-conf-occurs? "return config")
                            #:name "The file returns the configuration")
               (assert-true (wezterm-banners-aligned?)
                            #:name "Every section banner is the same width"))
         (test "Settings And Colours Follow The System"
               (assert-true (wezterm-conf-occurs? "scrollback_lines = 100000")
                            #:name "Scrollback matches the other terminals")
               (assert-true (wezterm-conf-occurs?
                             "window_background_opacity = 0.88")
                            #:name "Opacity is set")
               (assert-true (wezterm-conf-occurs?
                             "font = wezterm.font_with_fallback {")
                            #:name "The font is a fallback list")
               (assert-true (wezterm-conf-occurs?
                             "window_padding = { left = 16, right = 16, top = 16, bottom = 16 }")
                            #:name "Padding is applied on every side")
               (assert-true (wezterm-conf-occurs? "default_prog = { 'bash' }")
                            #:name
                            "The shell is bash, as in the other terminals")
               (assert-true (wezterm-conf-occurs? (format #f
                                                          "background = '~a'"
                                                          (get-color (heks-linux-palette)
                                                                     'background)))
                            #:name
                            "The background follows the selected palette")
               (assert-true (wezterm-conf-occurs? (format #f
                                                          "foreground = '~a'"
                                                          (get-color (heks-linux-palette)
                                                                     'text)))
                            #:name
                            "The foreground follows the selected palette"))
         (test "The Window Chrome Is Declared"
               ;; The title bar and the resize border come from the window
               ;; decorations; on Wayland, where the compositor draws neither and
               ;; this WezTerm build draws no bar of its own, the tab bar stays
               ;; visible and carries the buttons instead.
               (assert-true (wezterm-conf-occurs?
                             "window_decorations = 'TITLE | RESIZE'")
                            #:name "A title bar and a resize border are requested")
               (assert-true (wezterm-conf-occurs? "enable_tab_bar = true")
                            #:name "The tab bar is enabled")
               (assert-true (wezterm-conf-occurs? "use_fancy_tab_bar = true")
                            #:name "The tab bar is the one WezTerm paints itself")
               (assert-true (wezterm-conf-occurs?
                             "hide_tab_bar_if_only_one_tab = false")
                            #:name
                            "The bar - and with it the title - stays with one tab")
               (assert-true (wezterm-conf-occurs? "WAYLAND_DISPLAY")
                            #:name "The generated file asks whether it is on Wayland")
               (assert-true (wezterm-conf-occurs?
                             "config.window_decorations = 'INTEGRATED_BUTTONS | RESIZE'")
                            #:name
                            "On Wayland the buttons move into the tab bar"))
         (test "Meta And The Keyboard Protocol Are Configured"
               ;; Without this, Option on macOS composes a character (Option+v is
               ;; a square root sign) and Alt never arrives as Meta, so M-v could
               ;; not page anything.
               (assert-true (wezterm-conf-occurs?
                             "send_composed_key_when_left_alt_is_pressed = false")
                            #:name "Left Option sends Meta")
               (assert-true (wezterm-conf-occurs?
                             "send_composed_key_when_right_alt_is_pressed = false")
                            #:name "Right Option sends Meta")
               (assert-true (wezterm-conf-occurs? "enable_kitty_keyboard = true")
                            #:name
                            "The kitty keyboard protocol is left available to applications"))
         (test "Control+C Stays The Interrupt"
               (assert-equal #:expect #f
                             #:got (wezterm-conf-occurs? "{ key = 'c',")
                             #:name "Control+C is never taken by the terminal"))))

(define (spec)
  (veritas-run (modifier-translation-suite)
               (lua-value-suite)
               (binding-serialization-suite)
               (guarded-binding-suite)
               (passthrough-suite)
               (emacs-prefix-suite)
               (generated-file-suite)))
