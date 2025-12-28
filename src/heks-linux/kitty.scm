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
  #:export (kitty-config serialize-kitty-config install-kitty-config))

(define (kitty-config)
  `("# ====== Heks-Linux Kitty configuration ======\n"
    "# auto-generated file, DO NOT EDIT!\n\n"
    "# --- General ---\n"
    (allow_remote_control . yes)
    (listen_on . "unix:/tmp/kitty")
    "# --- Window Layout ---\n"
    (window_padding_width . 14)
    (hide_window_decorations . yes)
    (background_opacity . "0.8")
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
    (foreground unquote (get-color (heks-linux-palette)
                           'text))
    (background unquote (get-color (heks-linux-palette)
                           'background))
    ))

(define (install-kitty-config)
  (with-output-to-file (format #f "~a/.config/kitty/kitty.conf"
                               (getenv "HOME"))
    (lambda ()
      (display (mk-kv-conf-lines (kitty-config)
                                 #:template "~a ~a\n")))))

