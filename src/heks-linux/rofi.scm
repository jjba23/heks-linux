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
  #:use-module (ice-9 string-fun)
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
                                make-rofi-power-menu-script
                                rofi-theme-menu-filename
                                rofi-theme-menu-dir
                                make-rofi-theme-menu-script))

(define s
  (scriba-auto-logger))

(define rofi-icon-theme
  (make-parameter (get-icon-theme (heks-linux-palette))))

(define* (rofi-configuration)
  "Render the Rofi @file{config.rasi} file.

The launcher is registered with four modes: @code{drun} (applications),
@code{window} (the Cmd-Tab style switcher), @code{power} (session actions)
and @code{theme} (the palette picker).  The two script modes live in
@file{~/.local/bin} next to this configuration."
  (let ((bin-dir (format #f "~a/.local/bin"
                         (or (getenv "HOME") "/tmp"))))
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
    modi: \"drun,window,power:~a/~a,theme:~a/~a\";
}

@theme \"./sss-theme.rasi\""
     (heks-linux-sans-font)
     (rofi-icon-theme)
     bin-dir
     (rofi-power-menu-filename)
     bin-dir
     (rofi-theme-menu-filename))))

(define* (rofi-theme)
  "Return the Rofi theme as a list of CSS rulesets.
Every colour is looked up in the current palette, so the launcher follows the
theme.  The result is rendered with @code{mk-css-conf-lines}."
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
                                    #:alpha
                                    (get-rofi-opacity (heks-linux-palette))))
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

;; ===========================================
;; Rofi Theme (palette) Picker (script mode)
;; ===========================================

(define rofi-theme-menu-filename
  (make-parameter "heks-rofi-theme-menu"))

(define rofi-theme-menu-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define (heks-clone-dir-absolute)
  "Expand a leading @file{~/} in the configured clone dir so the generated
shell scripts can @code{cd} into it without quoting problems."
  (string-replace-substring (heks-linux-clone-dir)
                            "~/" (format #f "~a/"
                                         (or (getenv "HOME") "/tmp"))))

(define* (make-rofi-theme-menu-script)
  "Generate the Bash script implementing the Rofi @code{theme} script mode.

Choosing an entry rewrites @code{~/.config/heks-linux/local-settings.scm}
(keeping a @file{.bak} of the previous file) and then runs
@code{maak install-theme} to re-render every palette-dependent dotfile."
  (format #f
          "#!/usr/bin/env bash

# ====== Heks-Linux Rofi theme (palette) picker ======
#
# auto-generated file, DO NOT EDIT!
#
# Rofi script mode: no argument prints the palette list, the accepted
# entry is passed as $1 to apply it.

CLONE_DIR=\"~a\"
CURRENT=\"~a\"
LOCAL_SETTINGS=\"${XDG_CONFIG_HOME:-$HOME/.config}/heks-linux/local-settings.scm\"
LOG=\"${TMPDIR:-/tmp}/heks-theme.log\"

apply_theme() {
    mkdir -p \"$(dirname \"$LOCAL_SETTINGS\")\"
    if [ -f \"$LOCAL_SETTINGS\" ]; then
        cp -f \"$LOCAL_SETTINGS\" \"$LOCAL_SETTINGS.bak\"
    fi
    printf '(heks-linux-palette (quote %s))\\n(heks-linux-emacs-theme (quote %s))\\n' \"$1\" \"$1\" > \"$LOCAL_SETTINGS\"

    if (cd \"$CLONE_DIR\" && maak install-theme) > \"$LOG\" 2>&1; then
        fyi -a \"Heks Linux\" \"Theme applied: $1\" \"Emacs picks it up on the next start.\" || true
    else
        fyi -u critical -a \"Heks Linux\" \"Theme failed: $1\" \"See $LOG for details.\" || true
    fi
}

case \"${ROFI_RETV:-0}\" in
  0)
    printf '%s\\0icon\\x1f%s\\n' \"Current: $CURRENT\" 'emblem-default'
~a    ;;
  1)
    case \"$1\" in
      'Current: '*) exit 0 ;;
      *) apply_theme \"$1\" ;;
    esac
    ;;
esac
"
          (heks-clone-dir-absolute)
          (heks-linux-palette)
          (string-join (map (lambda (p)
                              (format #f
                                      "    printf '%s\\0icon\\x1f%s\\n' '~a' 'preferences-desktop-theme'\n"
                                      p))
                            (palette-names)) "")))

(define* (install-rofi-config)
  "Write the launcher config and theme, plus the power and theme-picker scripts.
Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/rofi-settings.scm} first.  The two generated
scripts are what make @code{rofi -show power} and @code{rofi -show theme} work."
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
  (install-config-file! #:name (rofi-theme-menu-filename)
                        #:dir (rofi-theme-menu-dir)
                        #:contents (make-rofi-theme-menu-script)
                        #:perms 493)
  (log-success s "Installed Rofi configuration"))
