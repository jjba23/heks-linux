;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders @file{~/.config/kitty/kitty.conf}, the configuration for Kitty, the
;; terminal the sessions launch.
;;
;; The file is one setting per line, @code{key value} or @code{map CHORD ACTION},
;; so unlike WezTerm it needs no embedded language: the settings and the colours
;; are plain association lists rendered by @code{mk-kv-conf-lines}, and the key
;; bindings are rendered one @code{map} line each.  The parts a user changes are
;; data; there is no policy block to re-read.
;;
;; == The keyboard, or what a terminal without a guard may claim ==
;;
;; WezTerm could ask each pane which process was in front of it, so it could
;; claim the Emacs chords and hand them back while Emacs or a pager owned the
;; keyboard.  Kitty has no such question: @code{--when-focus-on} matches an OS
;; window, not the program running inside the terminal.  A chord Kitty claims is
;; therefore a chord Emacs and readline never see again.
;;
;; So this configuration makes the other choice, and it is the one that keeps
;; Emacs whole: it claims no chord that Emacs, readline or a pager uses.  Every
;; bare @kbd{C-a}, @kbd{C-e}, @kbd{C-k}, @kbd{C-y}, @kbd{M-w}, @kbd{C-v},
;; @kbd{M-v}, @kbd{C-x} and @kbd{C-c} reaches the application untouched.  Kitty's
;; own defaults already live on @code{ctrl+shift} (@code{kitty_mod}), which no
;; Emacs user presses as a bare chord, so they are left alone too.
;;
;; The terminal commands are gathered behind one modal prefix shaped like
;; Emacs's @kbd{C-x}: @code{ctrl+shift+x} opens the @code{emacs} keyboard mode,
;; and the second keys are the Emacs ones - @kbd{t} for a tab, @kbd{2} and
;; @kbd{3} for the two splits, @kbd{o} for another window, @kbd{0} and @kbd{1}
;; to close windows, @kbd{k} for a tab as Emacs's @kbd{C-x k} kills a buffer.
;; The prefix sits one modifier up from @kbd{C-x} for the reason above: Emacs
;; inside Kitty keeps its own @kbd{C-x}.  @kbd{[} and @kbd{]} page the scrollback
;; in the mode, and @kbd{=}, @kbd{-} and @kbd{C-0} scale the font, as
;; @code{text-scale-adjust} does.
;;
;; The layer is one-shot, as Emacs's @kbd{C-x} prefix is: a bound key runs its
;; action and ends the layer (@code{--on-action=end}), an unknown second key is
;; passed to the application and ends it
;; (@code{--on-unknown=passthrough_and_end}), and an abandoned prefix gives up on
;; its own after @code{kitty-emacs-mode-timeout} seconds.  A half-typed chord can
;; therefore neither swallow the next key nor hang.
;;
;; The prompt jumps Kitty ships on @code{ctrl+shift+x} (the next shell prompt)
;; move to the mode's price: redefining one default is what opening the layer
;; there costs, and the prompt jump it replaces needs shell integration this
;; desktop does not mark prompts for.
;;
;; == Settings ==
;;
;; The font comes from @code{heks-linux-mono-font} and the colours from the
;; palette's @code{text}, @code{background} and @code{primary} entries, so
;; switching the palette repaints the terminal with everything else.  The
;; selection band is mixed from the text colour rather than borrowed from
;; @code{background-l}, which is an elevation tone too close to the background to
;; read as a selection; its ink is chosen by contrast measurement.  Kitty resolves glyph fallbacks through fontconfig, so
;; no fallback list is spelled here: @file{fontconfig.scm} is the one place that
;; decides them.  The background opacity follows the palette's
;; @code{terminal-opacity}, the same fraction the other surfaces use for their
;; glass.

;;; Code:

(define-module (heks-linux kitty)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (kitty-config-dir
            kitty-config-filename
            kitty-font-size
            kitty-window-padding
            kitty-scrollback-lines
            kitty-shell
            kitty-window-opacity
            kitty-tab-bar?
            kitty-emacs-mode
            kitty-emacs-prefix
            kitty-emacs-mode-timeout
            kitty-banner
            kitty-settings
            kitty-colors
            kitty-emacs-keys
            kitty-key-lines
            kitty-config
            install-kitty-config))

(define s
  (scriba-auto-logger))

;; Kitty's configuration directory; defaults to @file{~/.config/kitty}.
(define kitty-config-dir
  (make-parameter (format #f "~a/.config/kitty"
                          (or (getenv "HOME") "/tmp"))))

;; Kitty reads @file{kitty.conf} from its configuration directory.
(define kitty-config-filename
  (make-parameter "kitty.conf"))

;; Terminal font size, in points.  The other terminals use 12 as well.
(define kitty-font-size
  (make-parameter 12))

;; Window padding, in pixels, applied on every side.  Kitty's
;; @code{window_padding_width} is symmetric, so the single number is the whole
;; setting.
(define kitty-window-padding
  (make-parameter 16))

;; Number of scrollback lines kept per window.
(define kitty-scrollback-lines
  (make-parameter 100000))

;; The shell a window opens, as the login shell's absolute path.  Kitty looks a
;; bare name up on the @code{PATH} it inherits, and a dock started from a
;; development profile hands its children a @code{bash} built without
;; programmable completion: the terminal opened from it cannot complete a word
;; and says @code{shopt: progcomp: invalid shell option name} on start.  An
;; absolute path is what no @code{PATH} can choose for the shell.  Left at
;; @code{#f} when the environment names no shell, so the setting is omitted and
;; Kitty's own login-shell default stands.
(define kitty-shell
  (make-parameter (getenv "SHELL")))

;; Optional background-opacity override.  When left at #f the value comes from
;; the palette's @code{terminal-opacity} key, so switching themes changes the
;; translucency too.
(define kitty-window-opacity
  (make-parameter #f))

;; Whether Kitty draws its tab bar.  Off by default, matching the other
;; sessions, where a row of chrome above a terminal is a row of chrome too many:
;; @code{tab_bar_style hidden} is emitted.  A machine that wants the strip back
;; sets this to #t in its profile or override and Kitty's own default style
;; returns.  The tab chords in the Emacs layer work either way.
(define kitty-tab-bar?
  (make-parameter #f))

;; Name of the modal keyboard layer the Emacs chords live in.
(define kitty-emacs-mode
  (make-parameter "emacs"))

;; The chord that opens the layer.  It is @kbd{C-x} one modifier up: Kitty
;; cannot hand a claimed chord back to Emacs, so the bare @kbd{C-x} is left to
;; the application and the terminal's half moves to @kbd{C-x} with Shift held.
(define kitty-emacs-prefix
  (make-parameter "ctrl+shift+x"))

;; How long the layer waits for its second key, in seconds.  Kitty has no
;; timeout by default; an abandoned prefix would keep the next key for itself.
(define kitty-emacs-mode-timeout
  (make-parameter 4))

;; --- Serialization ---

;; Width of the section banners of the generated file.
(define kitty-banner-width
  74)

(define* (kitty-banner #:key title)
  "Render a section banner for the generated file.

Keeping the width here rather than inside each heading is what makes the
sections line up, and it is checked by the unit tests.

@example
(kitty-banner #:title \"keyboard\")
@result{} # ===== keyboard =====================================================
@end example"
  (string-append "# ===== " title " "
                 (make-string (max 3
                                   (- kitty-banner-width 8
                                      (string-length title))) #\=)))

;; --- The settings, as data ---

(define* (kitty-settings)
  "Return the settings Kitty receives, as an association list.

The renderer turns this into @code{key value} lines.  Every value here is either
a parameter or derived from the palette and the font settings, so changing a
setting is enough to change the file.

@example
(assoc-ref (kitty-settings) 'scrollback_lines)
@result{} 100000
@end example"
  (append `((font_family unquote
                         (heks-linux-mono-font))
            (font_size unquote
                       (kitty-font-size))
            (window_padding_width unquote
                                  (kitty-window-padding))
            (background_opacity unquote
                                (or (kitty-window-opacity)
                                  (get-terminal-opacity
                                   (heks-linux-palette))))
            (scrollback_lines unquote
                              (kitty-scrollback-lines))
            ;; A block cursor is Emacs's box cursor, and it is the shape a
            ;; terminal user coming from Emacs expects.
            (cursor_shape . "block")
            ;; Emacs flashes or rings the visible bell; an audible terminal
            ;; bell would be a second, louder voice.
            (enable_audio_bell . "no")
            (confirm_os_window_close . 0))
          (if (kitty-shell)
            (list (cons 'shell (kitty-shell)))
            '())
          (if (kitty-tab-bar?)
            '()
            (list (cons 'tab_bar_style "hidden")))))

;; How far the selection band is mixed from the background toward the text
;; colour, as a 0-1 fraction.  The value is measured, not guessed: across the
;; shipped palettes it is the smallest weight that keeps the band at least a
;; contrast of 2 against the background, while the ink chosen below still clears
;; WCAG AA (4.5) on the band.  See the selection test in @file{kitty-spec.scm}.
(define kitty-selection-tint
  0.55)

(define (kitty-selection-background)
  "Return the colour Kitty paints a text selection in.

The palette's @code{background-l} is an elevation tone - a shade away from
@code{background} - and a band painted in it reads as a smudge rather than as a
selection.  The band is therefore mixed from @code{background} toward
@code{text}, the one colour every palette guarantees to contrast with its
background, so the selection is visible whatever palette is worn."
  (mix-colors (get-color (heks-linux-palette)
                         'background)
              (get-color (heks-linux-palette)
                         'text)
              #:weight kitty-selection-tint))

(define (kitty-selection-foreground)
  "Return the ink a selection band is drawn in.

The band is a mid-tone, so the palette's usual text colour may or may not be
legible on it.  @code{readable-ink} measures the candidates against the actual
band and falls back to black or white when neither clears the floor, which keeps
the selected text readable on any palette."
  (readable-ink (kitty-selection-background)
                (list (get-color (heks-linux-palette)
                                 'text)
                      (get-color (heks-linux-palette)
                                 'background))))

(define* (kitty-colors)
  "Return the @code{foreground}, @code{background} and selection colours.

The colours come from the palette's @code{text}, @code{background} and
@code{primary} entries, which every palette defines, so this follows the
selected palette without asking a palette for a key it does not carry.  The
cursor borrows @code{primary} so it matches the accent the rest of the desktop
uses, and the selection is a band mixed from the text colour with a measured ink
on it, because @code{background-l} was too close to the background to see."
  `((foreground unquote
                (get-color (heks-linux-palette)
                           'text))
    (background unquote
                (get-color (heks-linux-palette)
                           'background))
    (cursor unquote
            (get-color (heks-linux-palette)
                       'primary))
    (cursor_text_color unquote
                       (get-color (heks-linux-palette)
                                  'background))
    (selection_foreground unquote
                          (kitty-selection-foreground))
    (selection_background unquote
                          (kitty-selection-background))))

;; --- The keyboard, as data ---

(define* (kitty-emacs-keys)
  "Return the second keys of the Emacs layer, as @code{(KEY . ACTION)} pairs.

Every second key is one an Emacs user already has in their fingers, and every
action is the nearest tab or window equivalent:

- @kbd{t} opens a tab, as @kbd{C-x t} opens one in Emacs's tab bar.
- @kbd{2} splits below and @kbd{3} splits right, as @kbd{C-x 2} and @kbd{C-x 3}
  split the window.
- @kbd{o} moves to another window, as @code{other-window}.
- @kbd{0} closes this window and @kbd{1} closes the others, as
  @code{delete-window} and @code{delete-other-windows}.
- @kbd{b} moves to the next tab and @kbd{k} closes it, the nearest tab
  equivalents of @code{switch-to-buffer} and @code{kill-buffer}.
- @kbd{[} and @kbd{]} page the scrollback, as @kbd{C-x [} and @kbd{C-x ]} page
  through a buffer.
- @kbd{=} (and @kbd{Shift+=} where a @kbd{+} is typed), @kbd{-} and @kbd{C-0}
  grow, shrink and reset the font, as @code{text-scale-adjust} does."
  '(("t" . "new_tab")
    ("2" . "launch --location=hsplit")
    ("3" . "launch --location=vsplit")
    ("o" . "next_window")
    ("0" . "close_window")
    ("1" . "close_other_windows_in_tab")
    ("b" . "next_tab")
    ("k" . "close_tab")
    ("[" . "scroll_page_up")
    ("]" . "scroll_page_down")
    ("=" . "change_font_size all +2.0")
    ("shift+equal" . "change_font_size all +2.0")
    ("-" . "change_font_size all -2.0")
    ("ctrl+0" . "change_font_size all 0")))

(define (kitty-key-lines)
  "Return the rendered @code{map} lines of the Emacs layer.

The first line opens the mode and carries the three policies that make the layer
behave like Emacs's one-shot @kbd{C-x} prefix: a bound key ends the mode
(@code{--on-action=end}), an unknown key is passed through and ends it, and an
abandoned prefix ends on its own after @code{kitty-emacs-mode-timeout} seconds.
Kitty reads all three from the @code{--new-mode} mapping, not from the entries."
  (append (list (format #f
                        "map --new-mode ~a --on-unknown=passthrough_and_end --on-action=end --timeout ~a ~a"
                        (kitty-emacs-mode)
                        (kitty-emacs-mode-timeout)
                        (kitty-emacs-prefix)))
          (map (lambda (entry)
                 (format #f "map --mode ~a ~a ~a"
                         (kitty-emacs-mode)
                         (car entry)
                         (cdr entry)))
               (kitty-emacs-keys))))

;; --- The configuration ---

(define* (kitty-config)
  "Return the whole @file{kitty.conf} as the text Kitty loads.

Settings and colours are rendered by @code{mk-kv-conf-lines} with the house
@code{spaced-conf-pair} template, which is exactly Kitty's @code{key value}
syntax; the keyboard section is the @code{map} lines.  Kitty's own defaults for
the @code{kitty_mod} chords are deliberately not repeated: only what differs -
the Emacs layer - is written.

@example
(string-contains (kitty-config) \"map --mode emacs t new_tab\")
@end example"
  (with-output-to-string (lambda ()
                           (display (string-join
                                     (list "# ====== Heks-Linux Kitty configuration ======"
                                           "#"
                                           "# auto-generated file, DO NOT EDIT!"
                                           "# Generated by (heks-linux kitty); install it with"
                                           "# `maak install-kitty'.  Edit src/heks-linux/kitty.scm instead."
                                           "#"
                                           "# Kitty cannot hand a claimed chord back to the program in the"
                                           "# foreground, so no bare Emacs chord is claimed here.  The"
                                           "# terminal's commands live behind ctrl+shift+x, shaped like C-x."
                                           "")
                                     "\n"))
                           (display (kitty-banner #:title "settings"))
                           (newline)
                           (display (mk-kv-conf-lines (kitty-settings)
                                                      #:template spaced-conf-pair))
                           (display (kitty-banner #:title "colours"))
                           (newline)
                           (display (mk-kv-conf-lines (kitty-colors)
                                                      #:template spaced-conf-pair))
                           (display (kitty-banner #:title
                                                  "keyboard: the Emacs layer"))
                           (newline)
                           (display (mk-lines (kitty-key-lines))))))

(define (install-kitty-config)
  "Write the Kitty configuration to @code{kitty-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/kitty-settings.scm} first, so a machine can
change the font, the opacity or the Emacs layer without editing this module.
Kitty reloads its configuration on @kbd{C-S-F5} (or @code{ctrl+shift+f5}), so no
restart is needed."
  (log-info s "Installing Kitty configuration")
  (load-local-overrides '(heks-linux kitty)
                        'kitty-settings)
  (install-config-file! #:name (kitty-config-filename)
                        #:dir (kitty-config-dir)
                        #:contents (kitty-config))
  (log-success s "Installed Kitty configuration"))
