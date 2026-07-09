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

(define-module (heks-linux rofi)
  #:declarative? #t
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-rofi-config rofi-theme
                                rofi-icon-theme
                                rofi-configuration
                                rofi-config-filename
                                rofi-theme-filename
                                rofi-config-dir))

(define s
  (scriba-auto-logger))

(define rofi-icon-theme
  (make-parameter "Adwaita"))

(define* (rofi-configuration)
  (format #f "configuration {
    font: \"~a 14\";
    show-icons: true;
    icon-theme:	\"~a\";
    display-drun: \"run: \";
    disable-history: false;
    fullscreen: false;
    hide-scrollbar: false;
    sidebar-mode: false;
}

@theme \"./sss-theme.rasi\""
          (heks-linux-sans-font)
          (rofi-icon-theme)))

(define* (rofi-theme)
  `(("*" (foreground unquote
                     (get-color (heks-linux-palette)
                                'text))
     (backlight unquote
                (hex-to-rgba (get-color (heks-linux-palette)
                                        'background)
                             #:alpha 0.7))
     (background-color . "transparent")
     (highlight . "underline bold #ffffff")
     (font unquote
           (format #f "\"~a 14\""
                   (heks-linux-sans-font))))
    ("window" (location . "center")
     (anchor . "center")
     (transparency . "\"real\"")
     (padding . "10px")
     (border . "0px")
     (border-radius . "12px")
     (spacing . "0")
     (background-color . "transparent")
     (orientation . "horizontal")
     (children . "[ mainbox ]"))
    ("message" (font unquote
                     (format #f "\"~a 14\""
                             (heks-linux-sans-font)))
     (border . "0px 2px 2px 2px")
     (color unquote
            (get-color (heks-linux-palette)
                       'text))
     (padding . "5px"))
    ("mainbox" (spacing . "0")
     (children . "[ inputbar, message, listview ]"))
    ("entry,prompt,case-indicator" (text-font . "inherit")
     (text-color . "inherit"))
    ("prompt" (margin . "0px 0.3em 0em 0em"))
    ("element" (padding . "3px")
     (vertical-align . "0.5")
     (border-radius . "2px")
     (background-color . "transparent")
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'text))
     (font . "inherit"))
    ("listview" (padding . "8px")
     (margin-top . "6px")
     (border-radius . "16px")
     (background-color unquote
                       (hex-to-rgba (get-color (heks-linux-palette)
                                               'background)
                                    #:alpha 0.7))
     (dynamic . "false")
     (lines . "20"))
    ("element-text" (text-color unquote
                                (get-color (heks-linux-palette)
                                           'text)))
    ("element selected" (highlight . none)
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'background))
     (background-color unquote
                       (hex-to-rgba (get-color (heks-linux-palette)
                                               'primary)
                                    #:alpha 0.7))
     (border-radius . "4px"))
    ("element-icon" (size . "1.1em"))
    ("inputbar" (color unquote
                       (get-color (heks-linux-palette)
                                  'text))
     (padding . "11px")
     (margin-bottom . "6px")
     (border-radius . "16px")
     (background-color unquote
                       (hex-to-rgba (get-color (heks-linux-palette)
                                               'background-l)
                                    #:alpha 0.9)))))

(define rofi-config-filename
  (make-parameter "config.rasi"))

(define rofi-theme-filename
  (make-parameter "sss-theme.rasi"))

(define rofi-config-dir
  (make-parameter (format #f "~a/.config/rofi"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-rofi-config)
  (log-info s "Installing Rofi configuration")
  (load-local-overrides '(heks-linux rofi) 'rofi-settings)
  (install-config-file! #:name (rofi-config-filename)
                        #:dir (rofi-config-dir)
                        #:contents (rofi-configuration))
  (install-config-file! #:name (rofi-theme-filename)
                        #:dir (rofi-config-dir)
                        #:contents (mk-css-conf-lines (rofi-theme)))
  (log-success s "Installed Rofi configuration"))
