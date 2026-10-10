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

(define-module (heks-linux gtk)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux dconf)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (gtk3-config gtk4-config
                        install-gtk3-config
                        install-gtk4-config
                        gtk-dconf-settings
                        install-gtk-dconf-config
                        gtk3-config-dir
                        gtk3-config-filename
                        gtk4-config-dir
                        gtk4-config-filename
                        gtk-dconf-script-dir
                        gtk-dconf-script-filename))

(define s
  (scriba-auto-logger))

(define* (gtk3-config #:key palette sans-font)
  "Return the GTK 3 @file{settings.ini} as a list of key/value pairs.
@var{palette} supplies the cursor, theme and icon names plus the decoration
layout; @var{sans-font} is the interface font.  The comments GTK ships next to
its own keys are reproduced alongside them."
  `((gtk-enable-event-sounds . 0) (gtk-enable-input-feedback-sounds . 0)
    (gtk-cursor-theme-name unquote
                           (get-cursor-theme palette))
    (gtk-cursor-theme-size unquote
                           (get-cursor-size palette))
    (gtk-theme-name unquote
                    (get-gtk-theme palette))
    (gtk-icon-theme-name unquote
                         (get-icon-theme palette))
    (gtk-font-name unquote
                   (format #f "'~a 11'" sans-font))
    ;; macOS-style window controls: close / minimize / zoom on the left.
    (gtk-decoration-layout unquote
                           "close,minimize,maximize:")
    (gtk-application-prefer-dark-theme unquote
                                       (if (is-dark-palette palette)
                                           'true
                                           'false))))

(define* (gtk4-config #:key palette sans-font)
  "Return the GTK 4 @file{settings.ini} as a list of key/value pairs.
The same shape and the same palette- and font-derived values as
@code{gtk3-config}."
  `((gtk-enable-event-sounds . 0) (gtk-enable-input-feedback-sounds . 0)
    (gtk-cursor-theme-name unquote
                           (get-cursor-theme palette))
    (gtk-cursor-theme-size unquote
                           (get-cursor-size palette))
    (gtk-theme-name unquote
                    (get-gtk-theme palette))
    (gtk-icon-theme-name unquote
                         (get-icon-theme palette))
    (gtk-font-name unquote
                   (format #f "'~a 11'" sans-font))
    ;; macOS-style window controls: close / minimize / zoom on the left.
    (gtk-decoration-layout unquote
                           "close,minimize,maximize:")
    (gtk-application-prefer-dark-theme unquote
                                       (if (is-dark-palette palette)
                                           'true
                                           'false))))

(define* (gtk-dconf-settings #:key palette sans-font mono-font)
  "Return the GTK-related dconf settings as a two-level tree.
Covers the window button layout, the key theme, the cursor and icon themes and
the dark-theme preference; @var{palette}, @var{sans-font} and @var{mono-font}
supply the values."
  `(("/org/gnome/desktop/wm/preferences"
     (button-layout . "'close,minimize,maximize:'"))
    ("/org/gnome/desktop/interface"
     ;; Base-name of the default keybinding theme used by GTK+.
     (gtk-key-theme . "'Emacs'")
     ;; Size of the cursor used as cursor theme.
     (cursor-size unquote
                  (format #f "~a"
                          (get-cursor-size palette)))
     ;; Cursor theme name. Used only by Xservers that support the Xcursor extension.
     (cursor-theme unquote
                   (format #f "'~a'"
                           (get-cursor-theme palette)))
     ;; Base-name of the default theme used by GTK+.
     (gtk-theme unquote
                (format #f "'~a'"
                        (get-gtk-theme palette)))
     ;; Icon theme to use for the panel, nautilus etc.
     (icon-theme unquote
                 (format #f "'~a'"
                         (get-icon-theme palette)))
     ;; Whether animations should be displayed. Note: This is a global key,
     ;; it changes the behavior of the window manager, the panel etc.
     (enable-animations . true)
     ;; The preferred accent color for the user interface. Valid values are
     ;; "blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "slate".
     (accent-color unquote
                   (get-gtk-accent-color palette))
     ;; The preferred color scheme for the user interface. Valid values are “default”, “prefer-dark”, “prefer-light”.
     (color-scheme unquote
                   (if (is-dark-palette palette) "'prefer-dark'"
                       "'prefer-light'"))
     ;; Name of the default font used by gtk+.
     (font-name unquote
                (format #f "'~a 11'" sans-font))
     ;; Name of the default font used for reading documents.
     (document-font-name unquote
                         (format #f "'~a 11'" sans-font))
     ;; Name of a mono-space (fixed-width) font for use in locations like
     ;; terminals.
     (monospace-font-name unquote
                          (format #f "'~a 11'" mono-font)))))

(define gtk3-config-dir
  (make-parameter (format #f "~a/.config/gtk-3.0"
                          (or (getenv "HOME") "/tmp"))))

(define gtk3-config-filename
  (make-parameter "settings.ini"))

(define gtk4-config-dir
  (make-parameter (format #f "~a/.config/gtk-4.0"
                          (or (getenv "HOME") "/tmp"))))

(define gtk4-config-filename
  (make-parameter "settings.ini"))

(define gtk-dconf-script-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define gtk-dconf-script-filename
  (make-parameter "write-gtk-dconf-settings"))

(define (install-gtk3-config)
  "Write GTK 3 @file{settings.ini} to @code{gtk3-config-dir}.
Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/gtk-settings.scm} first."
  (log-info s "Installing GTK 3 configuration")
  (load-local-overrides '(heks-linux gtk)
                        'gtk-settings)
  (install-config-file! #:name (gtk3-config-filename)
                        #:dir (gtk3-config-dir)
                        #:contents (string-append "[Settings]\n"
                                                  (mk-kv-conf-lines (gtk3-config
                                                                     #:palette
                                                                     (heks-linux-palette)
                                                                     #:sans-font
                                                                     (heks-linux-sans-font)))))
  (log-success s "Installed GTK 3 configuration"))

(define (install-gtk4-config)
  "Write GTK 4 @file{settings.ini} to @code{gtk4-config-dir}.
Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/gtk-settings.scm} first.  The GTK dconf writer
script is refreshed in the same call, because the two are always installed
together."
  (log-info s "Installing GTK 4 configuration")
  (load-local-overrides '(heks-linux gtk)
                        'gtk-settings)
  (install-config-file! #:name (gtk4-config-filename)
                        #:dir (gtk4-config-dir)
                        #:contents (string-append "[Settings]\n"
                                                  (mk-kv-conf-lines (gtk4-config
                                                                     #:palette
                                                                     (heks-linux-palette)
                                                                     #:sans-font
                                                                     (heks-linux-sans-font)))))
  (install-gtk-dconf-config)
  (log-success s "Installed GTK 4 configuration"))

(define (install-gtk-dconf-config)
  "Write the GTK dconf writer script to @code{gtk-dconf-script-dir} with mode
#o755.
Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/gtk-settings.scm} first."
  (log-info s "Installing GTK Dconf settings script")
  (load-local-overrides '(heks-linux gtk)
                        'gtk-settings)
  (install-config-file! #:name (gtk-dconf-script-filename)
                        #:dir (gtk-dconf-script-dir)
                        #:contents (string-join (append `("#!/usr/bin/env bash"
                                                          ""
                                                          "# ====== HEKS-LINUX dconf GTK writer ======"
                                                          "#"
                                                          "# auto-generated file, DO NOT EDIT!"
                                                          "")
                                                        (mk-nested-dconf-writer-commands
                                                         (gtk-dconf-settings
                                                                             #:palette
                                                                             (heks-linux-palette)
                                                                             #:sans-font
                                                                             (heks-linux-sans-font)
                                                                             #:mono-font
                                                                             (heks-linux-mono-font))))
                                                "\n")
                        #:perms 493)
  (log-success s "Installed GTK Dconf settings script"))
