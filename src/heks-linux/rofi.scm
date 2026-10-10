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
                                rofi-config-dir
                                rofi-power-menu-filename
                                rofi-power-menu-dir
                                rofi-power-menu-entries
                                make-rofi-power-menu-script))

(define s
  (scriba-auto-logger))

(define rofi-icon-theme
  (make-parameter (get-icon-theme (heks-linux-palette))))

(define* (rofi-configuration)
  (format #f
   "configuration {
    font: \"~a 14\";
    show-icons: true;
    icon-theme: \"~a\";
    display-drun: \"$ \";
    drun-display-format: \"{name}   <span weight='light' size='small'><i>{comment}</i></span>\";
    disable-history: false;
    fullscreen: false;
    hide-scrollbar: false;
    sidebar-mode: false;
    modi: \"drun,window,power:~a/.local/bin/~a\";
}

@theme \"./sss-theme.rasi\""
   (heks-linux-sans-font)
   (rofi-icon-theme)
   (or (getenv "HOME") "/tmp")
   (rofi-power-menu-filename)))

(define* (rofi-theme)
  `(("*" (foreground unquote
                     (get-color (heks-linux-palette)
                                'text))
     (background-color . "transparent")
     (highlight . "bold")
     (font unquote
           (format #f "\"~a 14\""
                   (heks-linux-sans-font))))

    ("window" (location . "center")
     (anchor . "center")
     (transparency . "\"real\"")
     (width . "50%")
     (padding . "20px")
     ;; Spotlight-like: no hard border, soft translucent rounded panel.
     (border . "0px")
     (border-color unquote
                   (get-color (heks-linux-palette)
                              'primary))
     (border-radius . "18px")
     (background-color unquote
                       (hex-to-rgba (get-color (heks-linux-palette)
                                               'background)
                                    #:alpha 0.92))
     (children . "[ mainbox ]"))

    ("mainbox" (spacing . "12px")
     (children . "[ inputbar, message, listview ]"))

    ("message" (border . "0px")
     (padding . "6px"))

    ("inputbar" (spacing . "8px")
     (padding . "14px 18px")
     (border-radius . "12px")
     (background-color unquote
                       (hex-to-rgba (get-color (heks-linux-palette)
                                               'background-l)
                                    #:alpha 0.5))
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'text))
     (children . "[ prompt, entry, button-close ]"))

    ("button-close"
     (action . "\"kb-cancel\"")
     (str . "\" × \"")
     (expand . "false")
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'text))
     (cursor . "pointer"))

    ("prompt" (text-color unquote
                          (get-color (heks-linux-palette)
                                     'primary)))

    ("entry" (placeholder . "\"Search...\"")
     (placeholder-color unquote
                        (hex-to-rgba (get-color (heks-linux-palette)
                                                'text)
                                     #:alpha 0.5))
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'text)))

    ("listview" (scrollbar . "false")
     (cycle . "true")
     (dynamic . "true")
     (spacing . "4px")
     (lines . "16"))

    ("element" (padding . "8px 12px")
     (spacing . "12px")
     (border-radius . "8px")
     (background-color . "transparent"))

    ("element-text" (text-color unquote
                                (get-color (heks-linux-palette)
                                           'text))
     (background-color . "transparent")
     (vertical-align . "0.5"))

    ("element-icon" (size . "32px")
     (background-color . "transparent")
     (vertical-align . "0.5"))

    ("element selected" (background-color unquote
                                          (get-color (heks-linux-palette)
                                                     'primary))
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'background)))))

(define rofi-config-filename
  (make-parameter "config.rasi"))

(define rofi-theme-filename
  (make-parameter "sss-theme.rasi"))

(define rofi-config-dir
  (make-parameter (format #f "~a/.config/rofi"
                          (or (getenv "HOME") "/tmp"))))

;; ===========================================
;; Rofi Power Menu (script mode)
;; ===========================================

(define (rofi-power-menu-entries)
  "Ordered list of Rofi power-menu entries, each as @code{(label icon command)}."
  (list (list "Lock" "system-lock-screen"
              "swaylock -f")
        (list "Log Out" "system-log-out"
              "loginctl terminate-session \"$XDG_SESSION_ID\"")
        (list "Suspend" "system-suspend"
              "systemctl suspend")
        (list "Hibernate" "system-hibernate"
              "systemctl hibernate")
        (list "Reboot" "system-reboot"
              "systemctl reboot")
        (list "Shut Down" "system-shutdown"
              "systemctl poweroff")))

(define* (make-rofi-power-menu-script)
  "Generate the Bash script implementing the Rofi @code{power} script mode.

Rofi calls it with @code{ROFI_RETV=0} to list the entries and with
@code{ROFI_RETV=1} (the chosen entry as @code{$1}) to execute its action."
  (format #f
          "#!/usr/bin/env bash

# ====== Heks-Linux Rofi power menu ======
#
# auto-generated file, DO NOT EDIT!
#
# Rofi script mode: no argument lists the entries, the selected
# entry is passed as $1 to run its action.

case \"${ROFI_RETV:-0}\" in
  0)
~a    ;;
  1)
    case \"$1\" in
~a    esac
    ;;
esac
"
          (string-join (map (lambda (e)
                              (format #f "    printf '~a\\0icon\\x1f~a\\n'\n"
                                      (list-ref e 0)
                                      (list-ref e 1)))
                            (rofi-power-menu-entries)) "")
          (string-join (map (lambda (e)
                              (format #f "      \"~a\") ~a ;;\n"
                                      (list-ref e 0)
                                      (list-ref e 2)))
                            (rofi-power-menu-entries)) "")))

(define rofi-power-menu-filename
  (make-parameter "heks-rofi-power-menu"))

(define rofi-power-menu-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define* (install-rofi-config)
  (log-info s "Installing Rofi configuration")
  (load-local-overrides '(heks-linux rofi)
                        'rofi-settings)
  (install-config-file! #:name (rofi-config-filename)
                        #:dir (rofi-config-dir)
                        #:contents (rofi-configuration))
  (install-config-file! #:name (rofi-theme-filename)
                        #:dir (rofi-config-dir)
                        #:contents (mk-css-conf-lines (rofi-theme)))
  (install-config-file! #:name (rofi-power-menu-filename)
                        #:dir (rofi-power-menu-dir)
                        #:contents (make-rofi-power-menu-script)
                        #:perms 493)
  (log-success s "Installed Rofi configuration"))
