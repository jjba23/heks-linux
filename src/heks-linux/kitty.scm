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

(define-module (heks-linux kitty)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (ice-9 string-fun)
  #:export (kitty-config kitty-bindings translate-kitty-mods
                         serialize-kitty-config install-kitty-config))

(define (translate-kitty-mods mods)
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
  (format #f "map ~a+~a ~a\n"
          (translate-kitty-mods mods) k action))

(define (kitty-bindings)
  (list (serialize-kitty-binding #:mods "C"
                                 #:k "y"
                                 #:action 'paste_from_clipboard)
        (serialize-kitty-binding #:mods "M"
                                 #:k "w"
                                 #:action 'copy_to_clipboard)
        (serialize-kitty-binding #:mods "C"
                                 #:k "+"
                                 #:action "change_font_size all +2.0")
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "+"
                                 #:action "change_font_size all +2.0")
        (serialize-kitty-binding #:mods "C"
                                 #:k "-"
                                 #:action "change_font_size all -2.0")
        (serialize-kitty-binding #:mods "C-S"
                                 #:k "-"
                                 #:action "change_font_size all -2.0")
        (serialize-kitty-binding #:mods "C"
                                 #:k "v"
                                 #:action 'scroll_page_down)
        (serialize-kitty-binding #:mods "M"
                                 #:k "v"
                                 #:action 'scroll_page_up)
        (serialize-kitty-binding #:mods "M"
                                 #:k "s"
                                 #:action 'search_scrollback)
        (serialize-kitty-binding #:mods "M"
                                 #:k "r"
                                 #:action 'search_scrollback)
        (serialize-kitty-binding #:mods "M"
                                 #:k "<"
                                 #:action 'scroll_home)
        (serialize-kitty-binding #:mods "M-S"
                                 #:k "<"
                                 #:action 'scroll_home)
        (serialize-kitty-binding #:mods "M"
                                 #:k ">"
                                 #:action 'scroll_end)
        (serialize-kitty-binding #:mods "M-S"
                                 #:k ">"
                                 #:action 'scroll_end)))

(define (kitty-config)
  `("# ====== Heks-Linux Kitty configuration ======
"
    "# auto-generated file, DO NOT EDIT!\n\n"
    "# --- General ---\n"
    (allow_remote_control . yes)
    (listen_on . "unix:/tmp/kitty")
    (shell_integration . enabled)
    "# --- Window Layout ---\n"
    (window_padding_width . 14)
    (hide_window_decorations . yes)
    (background_opacity . "0.9")
    (background_blur . 0)
    "# --- Scrolling ---\n"
    (scrollback_lines . 100000)
    "# --- Font ---\n"
    (font_family . "IBM Plex Mono")
    (bold_font . auto)
    (italic_font . auto)
    (bold_italic_font . auto)
    (font_size . "11.0")
    "# --- Shell ---\n"
    (shell . bash)
    "# --- Colors ---\n"
    (foreground unquote
                (get-color (heks-linux-palette)
                           'text))
    (background unquote
                (get-color (heks-linux-palette)
                           'background))))

(define (install-kitty-config)
  (with-output-to-file (format #f "~a/.config/kitty/kitty.conf"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-kv-conf-lines (append (kitty-config)
                                         (kitty-bindings))
                                 #:template "~a ~a\n")))))

