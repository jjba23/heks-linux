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
;; Renders @file{~/.config/alacritty/alacritty.toml}, the primary terminal
;; configuration (bound to @kbd{Mod+T} and @kbd{Mod+Return}).
;;
;; This module is the clearest illustration of the project's "configuration as
;; data" philosophy: each TOML section is an association list, each section is
;; serialized by @code{serialize-alacritty-setting}, and the whole file is
;; assembled by @code{alacritty-config}.  Because the intermediate representation
;; is data, the file can be rendered and diffed from a REPL without launching a
;; terminal.
;;
;; Two conventions are worth knowing when editing it:
;;
;; - Values that are already TOML literals (inline tables such as
;;   @code{{ x = 16, y = 16 }}, booleans, numbers) must be passed through
;;   untouched; @code{serialize-alacritty-setting} recognises inline tables by
;;   their leading brace and quotes everything else that is a string.  The
;;   @code{font.normal} entry is written pre-quoted for exactly this reason.
;; - Short modifier names (@code{C}, @code{M}, @code{S}, @code{s}) are translated
;;   by @code{translate-alacritty-mods} into Alacritty's @code{|}-separated
;;   spelling, keeping the binding table readable and consistent with the Niri
;;   and kitty modules.
;;
;; Blur is intentionally left off and delegated to the compositor: Niri already
;; blurs the Alacritty window through @code{niri-blur-rules}, so enabling it here
;; as well would double-apply the effect.

;;; Code:

(define-module (heks-linux alacritty)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (alacritty-general alacritty-window
                              alacritty-scrolling
                              alacritty-font
                              alacritty-colors-primary
                              alacritty-terminal
                              serialize-alacritty-setting
                              translate-alacritty-mods
                              serialize-alacritty-binding
                              alacritty-bindings
                              alacritty-config
                              alacritty-config-dir
                              alacritty-config-filename
                              serialize-alacritty-config
                              install-alacritty-config))

(define s
  (scriba-auto-logger))

(define alacritty-general
  `((live_config_reload . true) (ipc_socket . true)))

(define alacritty-window
  `((padding . "{ x = 16, y = 16}") (decorations unquote
                                                 (if (heks-linux-client-side-decorations?)
                                                     'Full
                                                     'None))
    (opacity . 0.82)
    (blur . false) ;; let WM take care of this if wanted
    ))

(define alacritty-scrolling
  `((history . 100000)))

(define* (alacritty-font)
  "Return the Alacritty @code{[font]} section.
The family comes from @code{heks-linux-mono-font} so the terminal stays in step
with the rest of the environment."
  `((normal unquote
            (format #f "{ family = \"~a\", style = \"Regular\" }"
                    (heks-linux-mono-font)))
    (size . 12)))

(define* (alacritty-colors-primary #:key palette)
  "Return the Alacritty @code{[colors.primary]} section.
@var{palette} selects the colours; the foreground and background keys come from
its @code{text} and @code{background} values."
  `((foreground unquote
                (get-color (heks-linux-palette)
                           'text))
    (background unquote
                (get-color (heks-linux-palette)
                           'background))))

(define alacritty-terminal
  `((shell . bash)))

(define (serialize-alacritty-setting s)
  "Render one Alacritty setting as a TOML @code{key = value} line.

@var{s} is a @code{(key . value)} pair.  Booleans render as TOML @code{true} /
@code{false} (both @code{#t} and the @code{true} symbol are accepted, because
the settings tables mix the two), strings and symbols are quoted, numbers pass
through, and values that already look like TOML (they start with a brace, e.g.
an inline table) are emitted verbatim.

@example
(serialize-alacritty-setting '(live_config_reload . #t))
@result{} live_config_reload = true
@end example"
  (let* ((val (cond
                ((or (eq? #t
                          (cdr s))
                     (eq? 'true
                          (cdr s)))
                 "true")
                ((or (eq? #f
                          (cdr s))
                     (eq? 'false
                          (cdr s)))
                 "false")
                ((and (string? (cdr s))
                      (string-prefix? "{"
                                      (cdr s)))
                 (cdr s))
                ((string? (cdr s))
                 (format #f "\"~a\""
                         (cdr s)))
                ((symbol? (cdr s))
                 (format #f "\"~a\""
                         (cdr s)))
                (else (cdr s)))))
    (format #f "~a = ~a"
            (car s) val)))

(define (translate-alacritty-mods mods)
  "Translate the project's short modifier syntax into Alacritty's spelling.

Alacritty separates modifiers with a vertical bar rather than a plus sign.
Unknown parts are passed through unchanged.

For example, @code{C-S} becomes @code{Control|Shift}."
  (let* ((parts (string-split mods #\-))
         (translated-parts (map (lambda (p)
                                  (cond
                                    ((string=? p "C")
                                     "Control")
                                    ((string=? p "M")
                                     "Alt")
                                    ((string=? p "S")
                                     "Shift")
                                    ((string=? p "s")
                                     "Super")
                                    (else p))) parts)))
    (string-join translated-parts "|")))

(define* (serialize-alacritty-binding #:key k mods action)
  "Render a single Alacritty key binding as an inline TOML table.

For example, with the modifier @code{C}, the key @code{Y} and the action
@code{Paste} it produces the inline table matching that chord to the paste
action."
  (format #f "{ key = \"~a\", mods = \"~a\", action = \"~a\"}" k
          (translate-alacritty-mods mods) action))

(define alacritty-bindings
  (list (serialize-alacritty-binding #:mods "C"
                                     #:k "Y"
                                     #:action 'Paste)
        (serialize-alacritty-binding #:mods "M"
                                     #:k "W"
                                     #:action 'Copy)
        (serialize-alacritty-binding #:mods "C"
                                     #:k "+"
                                     #:action 'IncreaseFontSize)
        (serialize-alacritty-binding #:mods "C-S"
                                     #:k "+"
                                     #:action 'IncreaseFontSize)
        (serialize-alacritty-binding #:mods "C"
                                     #:k "-"
                                     #:action 'DecreaseFontSize)
        (serialize-alacritty-binding #:mods "C-S"
                                     #:k "-"
                                     #:action 'DecreaseFontSize)
        (serialize-alacritty-binding #:mods "C"
                                     #:k "V"
                                     #:action 'ScrollPageDown)
        (serialize-alacritty-binding #:mods "M"
                                     #:k "V"
                                     #:action 'ScrollPageUp)
        (serialize-alacritty-binding #:mods "M"
                                     #:k "S"
                                     #:action 'SearchForward)
        (serialize-alacritty-binding #:mods "M"
                                     #:k "R"
                                     #:action 'SearchBackward)
        (serialize-alacritty-binding #:mods "S"
                                     #:k "Home"
                                     #:action 'ScrollToTop)
        (serialize-alacritty-binding #:mods "S"
                                     #:k "End"
                                     #:action 'ScrollToBottom)))

(define* (alacritty-config)
  "Return the complete Alacritty configuration as a list of text lines.

Sections are emitted in order (general, window, scrolling, font, terminal,
colours, keyboard) with headers, and the key bindings are joined into a single
TOML array.  Passing the result to @code{string-join} with a newline produces the
file that is written to disk; @code{serialize-alacritty-config} does exactly
that by joining on a newline character."
  (append '("# ====== Heks-Linux Alacritty configuration ======" "#"
            "# auto-generated file, DO NOT EDIT!")
          (list "" "[general]")
          (map serialize-alacritty-setting alacritty-general)
          (list "" "[window]")
          (map serialize-alacritty-setting alacritty-window)
          (list "" "[scrolling]")
          (map serialize-alacritty-setting alacritty-scrolling)
          (list "" "[font]")
          (map serialize-alacritty-setting
               (alacritty-font))
          (list "" "[terminal]")
          (map serialize-alacritty-setting alacritty-terminal)
          (list "" "[colors.primary]")
          (map serialize-alacritty-setting
               (alacritty-colors-primary))
          (list ""
                "[keyboard]"
                "bindings = ["
                (string-join alacritty-bindings ",\n")
                "]"
                "")))

(define* (serialize-alacritty-config #:key config)
  "Join a configuration line list, such as @code{(alacritty-config)}, into one
string with newlines between the lines.

@example
(serialize-alacritty-config #:config (alacritty-config))
@end example"
  (string-join config "\n"))

;; Alacritty ships TOML now, so the file is @file{alacritty.toml}.
(define alacritty-config-filename
  (make-parameter "alacritty.toml"))

;; Alacritty's configuration directory; defaults to @file{~/.config/alacritty}.
(define alacritty-config-dir
  (make-parameter (format #f "~a/.config/alacritty"
                          (or (getenv "HOME") "/tmp"))))

(define (install-alacritty-config)
  "Write the Alacritty configuration to @code{alacritty-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/alacritty-settings.scm} first.  Alacritty
hot-reloads the file (@code{live_config_reload}), so no restart is needed."
  (log-info s "Installing Alacritty configuration")
  (load-local-overrides '(heks-linux alacritty)
                        'alacritty-settings)
  (install-config-file! #:name (alacritty-config-filename)
                        #:dir (alacritty-config-dir)
                        #:contents (string-join (alacritty-config) "\n"))
  (log-success s "Installed Alacritty configuration"))
