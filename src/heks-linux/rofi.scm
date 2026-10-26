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
  #:use-module (heks-linux bridges)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux wallpaper)
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

;; The launcher's rim: one pixel of the palette's secondary text colour.  It is
;; the same trick the mako banners use - @code{mako-border-size} is the same one
;; pixel and @code{mako-border-alpha}'s @code{26} is this alpha as a two-digit
;; hex suffix - so a notification and the launcher share one edge language.
;; Mako takes @code{#RRGGBBAA} and rofi takes @code{rgba()}, which is why the
;; value is spelled twice; keep the two in step.
(define rofi-border-size "1px")
(define rofi-border-alpha 0.15)

(define* (rofi-configuration)
  "Render the Rofi @file{config.rasi} file.

The launcher is registered with four modes: @code{drun} (applications),
@code{window} (the Cmd-Tab style switcher), @code{power} (session actions)
and @code{theme} (the palette picker).  The two script modes live in
@file{~/.local/bin} next to this configuration.

The mouse is a first-class way to pick an entry, not a second one.  Rofi's
default is that a click only moves the selection and a second click (or Return)
accepts it, which on a launcher reads as a double click that sometimes works.
The three options below are Rofi's own recipe for the other behaviour - the
selection follows the pointer, and one click accepts - so a launcher can be used
with one hand on the mouse and no Return at all."
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
    hover-select: true;
    me-select-entry: \"\";
    me-accept-entry: \"MousePrimary\";
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
     ;; Spotlight-like: a soft translucent rounded panel, edged with a hairline
     ;; instead of framed with a border.  The rim is what separates the panel
     ;; from a wallpaper of the same tone; at full opacity it would read as a
     ;; frame, which is exactly what this palette system avoids.
     (border unquote rofi-border-size)
     (border-color unquote
                   (hex-to-rgba (get-color (heks-linux-palette)
                                           'text-l)
                                #:alpha rofi-border-alpha))
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
     (padding . "14px 18px 14px 12px")
     (border-radius . "12px")
     (background-color unquote
                       (hex-to-rgba (get-color (heks-linux-palette)
                                               'background-l)
                                    #:alpha 0.42))
     (text-color unquote
                 (get-color (heks-linux-palette)
                            'text))
     ;; The red dot of a macOS window, before the prompt: close, and nothing
     ;; else.  The yellow and green dots went away - clearing the line and
     ;; cycling modes are one keystroke each (C-u, Shift+Tab), and a window with
     ;; one button in it says "this closes" rather than offering a row of
     ;; controls nobody clicks.
     (children . "[ button-light-close, prompt, entry ]"))

    ("button-light-close" unquote
     `((action . "\"kb-cancel\"")
       (content . "\"●\"")
       (expand . "false")
       (font . ,(format #f "\"~a 17\"" (heks-linux-sans-font)))
       (text-color . "#ff5f57")
       (padding . "0px 2px")
       (vertical-align . 0.5)
       (cursor . "pointer")))

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
     ;; Fewer rows than before, because each row is taller: the icon grew, and a
     ;; launcher that runs past the bottom of the screen is a list, not a search
     ;; field.
     (lines . "14"))

    ("element" (padding . "6px 12px")
     (spacing . "12px")
     (border-radius . "8px")
     (background-color . "transparent"))

    ("element-text" (text-color unquote
                                (get-color (heks-linux-palette)
                                           'text))
     (background-color . "transparent")
     (vertical-align . "0.5"))

    ;; The icons are what a launcher is scanned for - a grid of logos is read
    ;; before a column of names - so they are a size up from the 32px this used
    ;; to be, and named in pixels rather than in ems so they do not move when the
    ;; font does.
    ("element-icon" (size . "40px")
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

(define (absolute-home-path path)
  "Expand a leading @file{~/} in @var{path} to the home directory.

The generated script embeds these paths inside double quotes, where a shell does
not expand a tilde, so they have to be absolute before they get there."
  (if (string-prefix? "~/" path)
      (format #f "~a/~a" (or (getenv "HOME") "/tmp") (substring path 2))
      path))

(define (emacs-bridge-absolute)
  "Return the absolute path of the Emacs bridge file heks-emacs re-reads."
  (format #f "~a/~a"
          (absolute-home-path (emacs-bridge-dir))
          (emacs-bridge-filename)))

(define (wallpaper-engine-absolute)
  "Return the absolute path of the wallpaper engine the picker calls."
  (format #f "~a/~a"
          (absolute-home-path (wallpaper-script-dir))
          (wallpaper-script-filename)))

(define (palette-emacs-theme-name palette)
  "Return @var{palette}'s Emacs theme as a bare symbol name.

Palettes declare their Emacs theme as the quoted symbol the bridge hands to
@code{load-theme}, so the leading quote has to come off before the name can be
written into a shell command."
  (let ((theme (get-emacs-theme palette)))
    (if (and (string? theme)
             (positive? (string-length theme))
             (char=? (string-ref theme 0) #\'))
        (substring theme 1)
        (if (symbol? theme) (symbol->string theme) theme))))

(define (palette-swatch-colors palette)
  "Return the four colours a palette's swatch is painted with, as a list.

The order is what the generated script draws, top left to bottom right:
background, primary, background-l, text.  Between them they say whether the
palette is dark, what it accents with, and how loud its text is."
  (list (get-color palette 'background)
        (get-color palette 'primary)
        (get-color palette 'background-l)
        (get-color palette 'text)))

(define (palette-swatch-signature)
  "Return a short fingerprint of the whole swatch table.

The picker caches one PNG per palette, and a palette whose colours change must
not keep showing the old swatch.  Baking a signature into the generated script
means a regenerated script - which a palette change always produces - wipes the
cache exactly once."
  (number->string (modulo (apply +
                                 (map char->integer
                                      (string->list
                                       (string-join (map (lambda (p)
                                                           (string-append
                                                            (symbol->string p)
                                                            (string-join
                                                             (palette-swatch-colors p)
                                                             "")))
                                                         (palette-names))
                                                    ""))))
                          100003)
                  16))

(define (palette-swatch-rows)
  "Render the generated shell @code{case} that maps a palette to its colours."
  (string-join (map (lambda (p)
                      (format #f "\t~a) printf '%s %s %s %s' ~a ;;"
                              p
                              (string-join (map (lambda (c)
                                                  (format #f "'~a'" c))
                                                (palette-swatch-colors p))
                                           " ")))
                    (palette-names))
               "\n"))

(define (palette-emacs-theme-rows)
  "Render the generated shell @code{case} that maps a palette to its Emacs theme."
  (string-join (map (lambda (p)
                      (format #f "\t~a) printf '%s' '~a' ;;"
                              p
                              (palette-emacs-theme-name p)))
                    (palette-names))
               "\n"))

(define (palette-name-lines)
  "Render the palette names as the arguments of one POSIX @code{printf} call.

The picker reads them back one per line, which keeps the shell from having to
know how many palettes the registry holds."
  (format #f "\tprintf '%s\\n' \\\n\t\t~a"
          (string-join (map (lambda (p)
                              (format #f "\"~a\"" p))
                            (palette-names))
                       " \\\n\t\t")))

(define* (make-rofi-theme-menu-script)
  "Generate the Bash script implementing the Rofi @code{theme} script mode.

Choosing an entry rewrites @code{~/.config/heks-linux/local-settings.scm}
(keeping a @file{.bak} of the previous file), runs @code{maak install-theme} to
re-render every palette-dependent dotfile, and then loads the matching Emacs
theme into the running daemon.

Three details make this feel like a switch rather than a rebuild.  Each palette
is previewed with a swatch built from its own colours, so choosing a theme is a
visual decision instead of a guess at a name.  The Emacs theme comes from a
generated table rather than from the palette name, because several palettes wear
a theme called something else - @code{heavy-metal} wears
@code{ef-tritanopia-dark}, for instance.  And the swatches are cached under
@file{$XDG_CACHE_HOME}, fingerprinted by the palette table, so the first open
builds them once and every later open is instant."
  (format #f
          "#!/usr/bin/env bash

# ====== Heks-Linux Rofi theme (palette) picker ======
#
# auto-generated file, DO NOT EDIT!
#
# Rofi script mode: no argument prints the palettes, the accepted entry is
# passed as $1 and applied to the whole desktop.

set -u

CLONE_DIR=\"~a\"
CURRENT=\"~a\"
LOCAL_SETTINGS=\"${XDG_CONFIG_HOME:-$HOME/.config}/heks-linux/local-settings.scm\"
LOG=\"${TMPDIR:-/tmp}/heks-theme.log\"
PROGRESS=\"${XDG_RUNTIME_DIR:-/tmp}/heks-theme-progress\"
BRIDGE=\"~a\"
WALLPAPER=\"~a\"
SWATCH_DIR=\"${XDG_CACHE_HOME:-$HOME/.cache}/heks-linux/palette-swatches\"
SWATCH_SIG=\"~a\"

if command -v magick >/dev/null 2>&1; then
    MAGICK=magick
elif command -v convert >/dev/null 2>&1; then
    MAGICK=convert
else
    MAGICK=
fi

# Every palette this build knows about, one per line.
palette_list() {
~a
}

# Whether a name is one of them.  The page checks its cards against the same
# table, but a picker can be called by anything - a stale bookmark, a hand-typed
# name - and a name that is not a palette would be written into the user's
# settings and then break every config that reads them.
palette_known() {
    local name
    while IFS= read -r name; do
        [ \"$name\" = \"$1\" ] && return 0
    done < <(palette_list)
    return 1
}

# The four colours a palette's swatch is drawn from: background, primary,
# background-l and text.
palette_colors() {
    case \"$1\" in
~a
        *) printf '%s %s %s %s' '#000000' '#ffffff' '#111111' '#ffffff' ;;
    esac
}
# The Emacs theme a palette wears.  Not a rename: several palettes wear a theme
# whose name says something else entirely.
palette_emacs_theme() {
    case \"$1\" in
~a
        *) printf '%s' \"$1\" ;;
    esac
}

# One 96x96 four-quadrant card per palette, drawn with ImageMagick and cached.
# Rofi scales it into the row's icon slot, so the picker shows the palette
# rather than describing it.
make_swatch() {
    local out=\"$SWATCH_DIR/$1.png\" bg primary bgl text
    read -r bg primary bgl text <<<\"$(palette_colors \"$1\")\" || return 1
    \"$MAGICK\" -size 96x96 \"xc:$bg\" \\
        -fill \"$primary\" -draw 'rectangle 48,0 95,47' \\
        -fill \"$bgl\" -draw 'rectangle 0,48 47,95' \\
        -fill \"$text\" -draw 'rectangle 48,48 95,95' \\
        \"$out\" 2>/dev/null || return 1
}

build_swatches() {
    [ -n \"$MAGICK\" ] || return 0
    mkdir -p \"$SWATCH_DIR\" || return 0
    if [ \"$(cat \"$SWATCH_DIR/.signature\" 2>/dev/null)\" != \"$SWATCH_SIG\" ]; then
        rm -f \"$SWATCH_DIR\"/*.png
        printf '%s' \"$SWATCH_SIG\" > \"$SWATCH_DIR/.signature\"
    fi
    local name
    while IFS= read -r name; do
        if [ ! -f \"$SWATCH_DIR/$name.png\" ]; then
            make_swatch \"$name\" &
        fi
    done < <(palette_list)
    wait
}

# Set one form in the override file, in place.  awk does the rewriting rather
# than sed because the form name arrives as data and building a regular
# expression out of it is where this kind of script usually breaks.
set_setting() {
    local name=\"$1\" value=\"$2\"
    if [ ! -f \"$LOCAL_SETTINGS\" ]; then
        printf '(%s (quote %s))\\n' \"$name\" \"$value\" > \"$LOCAL_SETTINGS\"
        return 0
    fi
    awk -v name=\"$name\" -v value=\"$value\" '
        { line = $0; sub(/^[ \\t]+/, \"\", line) }
        !done && index(line, \"(\" name) == 1 {
            rest = substr(line, length(name) + 2, 1)
            if (rest == \" \" || rest == \")\") {
                print \"(\" name \" (quote \" value \"))\"
                done = 1
                next
            }
        }
        { print }
        END { if (!done) print \"(\" name \" (quote \" value \"))\" }
    ' \"$LOCAL_SETTINGS\" > \"$LOCAL_SETTINGS.new\" &&
        mv \"$LOCAL_SETTINGS.new\" \"$LOCAL_SETTINGS\"
}

progress() {
    # Stage, the moment the switch started and the palette: one line the gallery
    # page reads to say what is happening and how long it has been happening.
    # The start time is kept rather than the time of the stage, so the page can
    # count the whole wait instead of restarting at every step.
    printf '%s %s %s\\n' \"$1\" \"${SWITCH_START:-$(date +%s)}\" \\
        \"${SWITCH_TARGET:-}\" > \"$PROGRESS\" 2>/dev/null || true
}

# One notification is opened at the start and edited as the work happens, so a
# switch that takes a few seconds says what it is doing instead of going quiet
# until it is over.  fyi prints the id (-p) so the same notification can be
# replaced (-r); a server that cannot do that simply gets two.
notify_start() {
    # fyi prints the id as id=33, not as a bare number, so the prefix comes off
    # before the id is any use to -r.
    NOTIFICATION=$(fyi -p -t 0 -a \"Heks Linux\" \"Applying palette: $1\" \\
        \"Reconfiguring the desktop...\" 2>/dev/null || true)
    NOTIFICATION=${NOTIFICATION#id=}
}

notify_done() {
    if [ -n \"${NOTIFICATION:-}\" ]; then
        fyi -r \"$NOTIFICATION\" -t 4000 -a \"Heks Linux\" \"$1\" \"$2\" || true
    else
        fyi -a \"Heks Linux\" \"$1\" \"$2\" || true
    fi
}

notify_failed() {
    if [ -n \"${NOTIFICATION:-}\" ]; then
        fyi -r \"$NOTIFICATION\" -u critical -a \"Heks Linux\" \"$1\" \"$2\" || true
    else
        fyi -u critical -a \"Heks Linux\" \"$1\" \"$2\" || true
    fi
}

# Rewrite the palette in the user's own override file.  Only the two forms that
# name the theme are touched: a machine that has, say, its own fonts or its own
# clone dir in that file keeps them, which is the whole point of a file the user
# owns.  The stages are written out as the work happens so the gallery page can
# show a switch in progress instead of a frozen window.
apply_theme() {
    local name=\"$1\" emacs
    SWITCH_TARGET=\"$name\"
    SWITCH_START=$(date +%s)
    # Refuse a name that is not in the table before anything is written: the
    # settings file is the one thing here whose corruption outlives the run.
    if ! palette_known \"$name\"; then
        progress failed
        notify_failed \"Unknown palette: $name\" \"Nothing was changed.\"
        return 1
    fi
    emacs=$(palette_emacs_theme \"$name\")
    notify_start \"$name\"

    progress settings
    mkdir -p \"$(dirname \"$LOCAL_SETTINGS\")\"
    if [ -f \"$LOCAL_SETTINGS\" ]; then
        cp -f \"$LOCAL_SETTINGS\" \"$LOCAL_SETTINGS.bak\"
    fi
    set_setting heks-linux-palette \"$name\"
    set_setting heks-linux-emacs-theme \"$emacs\"

    progress rendering
    if (cd \"$CLONE_DIR\" && maak install-theme) > \"$LOG\" 2>&1; then
        # The wallpaper set follows the palette, so the wall follows it too: the
        # engine picks from the new set rather than leaving yesterday's colours
        # on the screen behind today's chrome.
        progress wallpaper
        \"$WALLPAPER\" random >>\"$LOG\" 2>&1 || true
        # Emacs keeps its theme in its own memory.  It is asked to re-read the
        # bridge heks-linux just wrote rather than told which theme to load: the
        # theme's name is heks-emacs's business, and this script has no business
        # knowing it.
        progress emacs
        if command -v emacsclient >/dev/null 2>&1; then
            emacsclient --eval \"(progn (load \\\"$BRIDGE\\\" t) (when (boundp 'heks-emacs-theme) (load-theme heks-emacs-theme t)))\" \\
                >/dev/null 2>&1 || true
        fi
        progress done
        notify_done \"Palette applied: $name\" \\
            \"The desktop, the bar, the wallpaper and Emacs all switched.\"
    else
        progress failed
        notify_failed \"Palette failed: $name\" \"See $LOG for details.\"
    fi
}

case \"${ROFI_RETV:-0}\" in
    0)
        build_swatches
        while IFS= read -r name; do
            label=\"$name\"
            icon=\"$SWATCH_DIR/$name.png\"
            [ -f \"$icon\" ] || icon='preferences-desktop-theme'
            if [ \"$name\" = \"$CURRENT\" ]; then label=\"$name  (current)\"; fi
            printf '%s\\0display\\x1f%s\\0icon\\x1f%s\\n' \\
                \"$name\" \"$label\" \"$icon\"
        done < <(palette_list)
        ;;
    1)
        case \"$1\" in
            '') exit 0 ;;
            *) apply_theme \"$1\" ;;
        esac
        ;;
esac
"
          (heks-clone-dir-absolute)
          (heks-linux-palette)
          (emacs-bridge-absolute)
          (wallpaper-engine-absolute)
          (palette-swatch-signature)
          (palette-name-lines)
          (palette-swatch-rows)
          (palette-emacs-theme-rows)))

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
