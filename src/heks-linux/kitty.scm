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
;; Renders @file{~/.config/kitty/kitty.conf}.
;;
;; kitty's configuration language is terse but has sharp edges: key bindings are
;; expressed as @code{map <mods>+<key> <action>}, where modifiers are spelled out
;; in full (@code{ctrl}, @code{alt}, @code{shift}, @code{super}) and joined with a
;; @code{+}, while the action may or may not take arguments.  The module keeps
;; the ergonomic short forms used everywhere else in this repository (@code{C},
;; @code{M}, @code{S}, @code{s}) in @code{kitty-bindings} and translates them in
;; @code{translate-kitty-mods}, so the binding table reads the same way as the
;; Niri and Alacritty ones.
;;
;; The generated file uses the same Emacs-flavoured clipboard bindings as the
;; other terminals (@kbd{Ctrl+Y} paste, @kbd{Alt+W} copy) so muscle memory is
;; portable across them.
;;
;; Transparency is delegated to the compositor: kitty declares
;; @code{background_opacity} and leaves @code{background_blur} off, because Niri
;; already applies a blur effect to the kitty window (see @code{niri-blur-rules}).
;;
;; Two kitty settings exist mainly to serve other Heks Linux features:
;; @code{allow_remote_control} plus @code{listen_on} let external tools - most
;; notably the Emacs bridges and the RMPC launcher - drive a running kitty.

;;; Code:

(define-module (heks-linux kitty)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (kitty-config kitty-bindings translate-kitty-mods
                         serialize-kitty-binding
                         install-kitty-config kitty-config-filename
                         kitty-config-dir))

(define s
  (scriba-auto-logger))

(define (translate-kitty-mods mods)
  "Translate the project's short modifier syntax into kitty's spelling.

@code{C} becomes @code{ctrl}, @code{M} becomes @code{alt}, @code{S} becomes
@code{shift} and @code{s} becomes @code{super}; unknown parts are passed through
unchanged so that literal key names survive.

For example, the mods @code{C-S} become @code{ctrl+shift}."
  (let* ((parts (string-split mods #\-))
         (translated-parts (map (lambda (p)
                                  (cond
                                    ((string=? p "C")
                                     "ctrl")
                                    ((string=? p "M")
                                     "alt")
                                    ((string=? p "S")
                                     "shift")
                                    ((string=? p "s")
                                     "super")
                                    (else p))) parts)))
    (string-join translated-parts "+")))

(define* (serialize-kitty-binding #:key k mods action)
  "Render a single kitty @code{map} line.

@var{mods} uses the short modifier syntax translated by
@code{translate-kitty-mods}, @var{k} is the key and @var{action} is either a
symbol (rendered bare, e.g. @code{paste_from_clipboard}) or a full action string
with arguments (e.g. @code{change_font_size all +2.0}).

For example, the mods @code{C} with the key @code{y} and the action
@code{paste_from_clipboard} renders the standard clipboard-paste mapping."
  (format #f "map ~a+~a ~a\n"
          (translate-kitty-mods mods) k action))

(define (kitty-bindings)
  "Return the list of rendered kitty key-binding lines.

The set is intentionally small and Emacs-flavoured: clipboard access, font
resizing, paging and scrollback navigation.  The font-size and scrollback
bindings use kitty's own @code{kitty_mod} (ctrl+shift) spellings - @code{equal},
@code{plus}, @code{minus}, @code{home} and @code{end} - because kitty silently
ignores a @code{map} line whose key name it does not recognise.  Everything else
is left to kitty's defaults so that upstream additions keep working."
  (list (serialize-kitty-binding #:mods "C"
                                 #:k "y"
                                 #:action 'paste_from_clipboard)
        (serialize-kitty-binding #:mods "M"
                                 #:k "w"
                                 #:action 'copy_to_clipboard)
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "equal"
                                 #:action "change_font_size all +2.0")
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "plus"
                                 #:action "change_font_size all +2.0")
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "minus"
                                 #:action "change_font_size all -2.0")
        (serialize-kitty-binding #:mods "C"
                                 #:k "v"
                                 #:action 'scroll_page_down)
        (serialize-kitty-binding #:mods "M"
                                 #:k "v"
                                 #:action 'scroll_page_up)
        (serialize-kitty-binding #:mods "M"
                                 #:k "s"
                                 #:action 'show_scrollback)
        (serialize-kitty-binding #:mods "M"
                                 #:k "r"
                                 #:action 'show_scrollback)
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "home"
                                 #:action 'scroll_home)
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "end"
                                 #:action 'scroll_end)))

(define (kitty-config)
  "Return the kitty configuration as a mixed list of comment strings and pairs.

The result is fed to @code{mk-kv-conf-lines} with the @code{spaced-conf-pair}
template, giving kitty's @code{key value} syntax.  Colours come from the current
palette, the terminal font comes from @code{heks-linux-mono-font}, and the
@code{map} lines produced by @code{kitty-bindings} are appended at the end.

@example
(mk-kv-conf-lines (kitty-config) #:template spaced-conf-pair)
@end example"
  `("# ====== Heks-Linux Kitty configuration ======
"
    "# auto-generated file, DO NOT EDIT!\n\n"
    "# --- General ---\n"
    (allow_remote_control . yes)
    (listen_on . "unix:/tmp/kitty")
    (shell_integration . enabled)
    (confirm_os_window_close . 0)
    "# --- Window Layout ---\n"
    (window_padding_width . 14)
    (hide_window_decorations . yes)
    (background_opacity . "0.88")
    (background_blur . 0) ;; let WM take care of this if wanted
    "# --- Scrolling ---\n"
    (scrollback_lines . 100000)
    (scrollback_pager . "less")
    "# --- Font ---\n"
    (font_family unquote
                 (heks-linux-mono-font))
    (bold_font . auto)
    (italic_font . auto)
    (bold_italic_font . auto)
    (font_size . "12.0")
    "# --- Shell ---\n"
    (shell . bash)
    "# --- Colors ---\n"
    (foreground unquote
                (get-color (heks-linux-palette)
                           'text))
    (background unquote
                (get-color (heks-linux-palette)
                           'background))
    "# --- Key bindings ---\n"
    (unquote-splicing (kitty-bindings))))

;; kitty only reads @file{kitty.conf} from its configuration directory.
(define kitty-config-filename
  (make-parameter "kitty.conf"))

;; kitty's configuration directory; defaults to @file{~/.config/kitty}.
(define kitty-config-dir
  (make-parameter (format #f "~a/.config/kitty"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-kitty-config)
  "Write the kitty configuration to @code{kitty-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/kitty-settings.scm} first, then the
configuration and the binding table are serialized into one file."
  (log-info s "Installing Kitty configuration")
  (load-local-overrides '(heks-linux kitty)
                        'kitty-settings)
  (install-config-file! #:name (kitty-config-filename)
                        #:dir (kitty-config-dir)
                        #:contents (mk-kv-conf-lines (kitty-config)
                                                     #:template
                                                     spaced-conf-pair))
  (log-success s "Installed Kitty configuration"))
