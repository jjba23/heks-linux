;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Renders @file{heks-rofi-theme-menu}, the program that switches the desktop's
;; palette.
;;
;; A palette switch is more than a colour: it rewrites the override file two
;; settings live in, re-renders every surface that embeds a colour, puts the new
;; palette's wallpaper on the screen and asks the running Emacs to load the theme
;; the palette wears.  Doing that by hand is four commands and a shell session;
;; this script is the four commands, with the bookkeeping in between, so that the
;; bar's palette glyph and heks-toon's palette view run the same switch.
;;
;; It is a *generated* Bash script for one reason: its two callers are programs,
;; not people.  heks-toon runs it with @code{ROFI_RETV=1} and the palette's name
;; when a card is chosen, and whelk reads @code{ROFI_RETV=0} from it to draw the
;; swatch list, which is the menu script protocol whelk reads - and the reason
;; the file is still called @code{heks-rofi-theme-menu}: heks-toon names it in
;; its own settings, so renaming it is a change to another project's default
;; rather than to this one.
;;
;; What this module refuses to do: it does not know which surfaces depend on the
;; palette (that list is @code{theme-surfaces} in @code{maak.scm}), and it does
;; not decide which Emacs theme a palette wears (the registry does, because
;; several palettes wear a theme called something else).

;;; Code:

(define-module (heks-linux palette-picker)
  #:declarative? #t
  #:use-module (heks-linux bridges)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux wallpaper)
  #:use-module (ice-9 string-fun)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-palette-picker-config
            make-theme-picker-script
            palette-picker-command
            theme-picker-filename
            theme-picker-dir
            palette-swatch-colors
            palette-swatch-signature))

(define s
  (scriba-auto-logger))

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
(define* (make-theme-picker-script)
  "Generate the Bash script that switches the palette.

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

# ====== Heks-Linux palette picker ======
#
# auto-generated file, DO NOT EDIT!
#
# whelk's menu protocol: no argument prints the palettes, the accepted entry is
# accepted entry is passed as $1 and applied to the whole desktop.

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
# The launcher scales it into the row's icon slot, so the picker shows the
# palette rather than describing it.
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
    # Four at a time.  A fresh cache used to start one ImageMagick per palette
    # at once, and that fan-out competing for the first paint is a stall the
    # launcher wears for having opened its own palette mode.
    local name running=0
    while IFS= read -r name; do
        if [ ! -f \"$SWATCH_DIR/$name.png\" ]; then
            make_swatch \"$name\" &
            running=$((running + 1))
            if [ \"$running\" -ge 4 ]; then
                wait
                running=0
            fi
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
    ' \"$LOCAL_SETTINGS\" > \"$LOCAL_SETTINGS.new\" || {
        rm -f \"$LOCAL_SETTINGS.new\"
        return 1
    }
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
    NOTIFICATION=$(fyi -p -i applications-graphics-symbolic -t 0 -a \"Heks Linux\" \"Applying palette: $1\" \\
        \"Reconfiguring the desktop...\" 2>/dev/null || true)
    NOTIFICATION=${NOTIFICATION#id=}
}

notify_done() {
    if [ -n \"${NOTIFICATION:-}\" ]; then
        fyi -r \"$NOTIFICATION\" -i applications-graphics-symbolic -t 4000 -a \"Heks Linux\" \"$1\" \"$2\" || true
    else
        fyi -i applications-graphics-symbolic -a \"Heks Linux\" \"$1\" \"$2\" || true
    fi
}

notify_failed() {
    if [ -n \"${NOTIFICATION:-}\" ]; then
        fyi -r \"$NOTIFICATION\" -i dialog-error-symbolic -u critical -a \"Heks Linux\" \"$1\" \"$2\" || true
    else
        fyi -u critical -i dialog-error-symbolic -a \"Heks Linux\" \"$1\" \"$2\" || true
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

;; The name heks-toon 0.3.6 runs, and the one every machine that has switched a
;; palette already has on disk: see this module's commentary for why it is not
;; renamed.
(define theme-picker-filename
  (make-parameter "heks-rofi-theme-menu"))

(define theme-picker-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define (palette-picker-command)
  "Return the command that opens the palette picker from a keybinding or a bar."
  (format #f "whelk --menu ~a/~a"
          (theme-picker-dir)
          (theme-picker-filename)))

(define* (install-palette-picker-config)
  "Write the palette picker script to @code{theme-picker-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/palette-picker-settings.scm} first, so a
machine that keeps its palettes somewhere else - or its Emacs bridge under
another name - can say so without forking the module."
  (log-info s "Installing the palette picker")
  (load-local-overrides '(heks-linux palette-picker)
                        'palette-picker-settings)
  (install-config-file! #:name (theme-picker-filename)
                        #:dir (theme-picker-dir)
                        #:contents (make-theme-picker-script)
                        #:perms 493)
  (log-success s "Installed the palette picker"))
