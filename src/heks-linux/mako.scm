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
;; Renders @file{~/.config/mako/config}, the notification daemon configuration.
;;
;; The module is deliberately organised around a @emph{list of pairs}, not a
;; template string: each line is a @code{(key . value)} pair and the whole list
;; is flattened by @code{mk-kv-conf-lines}.  That is what allows the spec to
;; assert on rendered behaviour without starting mako.
;;
;; Two macOS-inspired choices are baked in: banners carry a soft 16px corner
;; radius and a one-pixel hairline edge @emph{instead of} a hard frame, and a
;; @code{do-not-disturb} mode is declared so that
;; @code{makoctl mode -t do-not-disturb} toggles it.  In that mode notifications
;; are still recorded in the history buffer, they are simply never drawn -
;; so nothing is lost when you dismiss the world for an hour.
;;
;; The DND state is also surfaced on the Waybar (see @code{waybar-mako-dnd}) and
;; bound to @kbd{Mod+Shift+N} in @code{(heks-linux niri)}.

;;; Code:

(define-module (heks-linux mako)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (mako-config install-mako-config mako-config-filename
                        mako-config-dir))

(define s
  (scriba-auto-logger))

;; The banner hairline: one pixel of the palette's secondary text colour at
;; roughly 15% opacity.  That is the macOS notification trick - a rim that reads
;; as an edge in a dark palette and as a soft shadow in a light one, without
;; ever turning into a visible frame.
(define mako-border-size 1)
(define mako-border-alpha "26")

(define* (mako-border-color palette)
  "Return the 8-digit hex colour of the banner hairline for @var{palette}.
Mako accepts @code{#RRGGBBAA}, so the alpha is appended to the palette's
@code{text-l} colour rather than blended here."
  (string-append (get-color palette 'text-l) mako-border-alpha))

(define* (mako-config #:key palette sans-font)
  "Return the mako configuration as a list ready for @code{mk-kv-conf-lines}.

@var{palette} supplies the background, accent and text colours; @var{sans-font}
is rendered as @code{<family> <size in points>}.  The returned list mixes
@code{(key . value)} pairs with raw strings, because the trailing
@code{[mode=do-not-disturb]} section is not a key/value pair.

@example
(mk-kv-conf-lines (mako-config #:palette 'nord))
@end example"
  (let* ((format-color (lambda (key)
                         (string-upcase (format #f "~abb"
                                                (get-color palette key)))))
         (bg-color (format-color 'background))
         (primary-color (format-color 'primary))
         (text-color (format-color 'text)))
    (append `((sort . "-time") (max-history . 7)
      (max-visible . 5)

      ;; Geometry & Layout
      (anchor . "top-right")
      (width . 380)
      (margin . "8")
      (padding . "14")
      (layer . "top")

      ;; Visual Styling
      ;; soft, subtly edged, generously rounded banners.
      (background-color unquote bg-color)
      (border-color unquote (mako-border-color palette))
      (border-size unquote mako-border-size)
      (border-radius . 16)
      (progress-color unquote primary-color)

      ;; Typography & Content Formatting
      (text-color unquote text-color)
      (font unquote
            (format #f "~a 11" sans-font))
      (text-alignment . "left")
      (markup . 1)
      (format . "<b>%s</b>\\n%b")

      ;; Icons
      (icons . 1)
      (max-icon-size . 48)

      ;; Actions & Timeouts
      (on-button-left . dismiss)
      (on-button-right . invoke-default-action)
      (default-timeout . 10000)
      (ignore-timeout . 1))
     ;; Do-not-disturb mode. Toggled from the session with
     ;; `makoctl mode -t do-not-disturb`; while active, notifications are
     ;; still kept in the history buffer but never drawn on screen.
     (list "\n[mode=do-not-disturb]\ninvisible=1\n"))))

;; mako has no file extension convention: the file is plainly @file{config}.
(define mako-config-filename
  (make-parameter "config"))

;; Directory receiving the rendered configuration; defaults to
;; @file{~/.config/mako}.
(define mako-config-dir
  (make-parameter (format #f "~a/.config/mako"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-mako-config)
  "Write the mako configuration to @code{mako-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/mako-settings.scm} first.  Restart mako (or
run @code{makoctl reload}) afterwards for the change to take effect."
  (log-info s "Installing Mako configuration")
  (load-local-overrides '(heks-linux mako)
                        'mako-settings)
  (install-config-file! #:name (mako-config-filename)
                        #:dir (mako-config-dir)
                        #:contents (mk-kv-conf-lines (mako-config #:palette (heks-linux-palette)
                                                                  #:sans-font (heks-linux-sans-font))))
  (log-success s "Installed Mako configuration"))
