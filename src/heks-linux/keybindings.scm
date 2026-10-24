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
;; The keyboard reference behind the @kbd{?} button on the Waybar.
;;
;; Niri has a hotkey overlay of its own, but it can only show Niri's own
;; bindings, in Niri's own wording, on one flat page.  This module answers a
;; different question - "what do I press in this app?" - and so it renders a
;; small, self-contained HTML document with one @emph{page per application}:
;; Niri, WezTerm, Emacs, Rofi, and the bar itself.  Pages scroll, a search box
;; filters every visible row, and the whole document is painted from the
;; current palette, so the reference matches the session it describes.
;;
;; Every chord is written in Emacs notation, the notation the rest of this
;; project already speaks: @kbd{C} for Control, @kbd{M} for Alt, @kbd{S} for
;; Shift, @kbd{s} for Super, and a dash between the modifiers and the key.  So
;; @kbd{s-S-q} is Super+Shift+Q, and a sequence such as @kbd{C-x C-f} means the
;; two chords in order.  The keys themselves stay lower case so that a chord
;; that needs Shift is never confused with the shifted character.
;;
;; The Niri page is the only one that could silently drift: the curated chords
;; below are checked against @code{(niri-bindings)} by the spec, which fails
;; when a binding is added, removed or renamed in @code{(heks-linux niri)}.
;; The other pages document software Heks configures but does not define, so
;; their chords are curated here and follow the rendered configurations.
;;
;; @code{?} on the bar runs the generated @command{heks-keybindings} script,
;; which opens the document in a browser app window (so it reads like a native
;; cheat sheet) and falls back to @command{xdg-open}.

;;; Code:

(define-module (heks-linux keybindings)
  #:declarative? #t
  #:use-module (heks-linux glass)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:export (keybindings-pages
            keybindings-html
            keybindings-launcher-script
            keybindings-niri-chord
            heks-emacs-key-sections
            heks-emacs-reference-file
            install-keybindings-config
            keybindings-dir
            keybindings-filename
            keybindings-launcher-dir
            keybindings-launcher-filename
            keybindings-command))

(define s
  (scriba-auto-logger))

;; ===========================================
;; Where the reference lives
;; ===========================================

(define keybindings-dir
  (make-parameter (format #f "~a/.config/heks-linux/keybindings"
                          (or (getenv "HOME") "/tmp"))))

(define keybindings-filename
  (make-parameter "index.html"))

(define keybindings-launcher-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

(define keybindings-launcher-filename
  (make-parameter "heks-keybindings"))

;; The command the bar runs.  Kept as a parameter so the Waybar module and the
;; installed script cannot disagree about the name.
(define keybindings-command
  (make-parameter "heks-keybindings"))

;; ===========================================
;; Niri: checked against the real bindings
;; ===========================================

;; Niri speaks in @code{mod} names; the reference speaks Emacs.
(define niri-mod-labels
  '(("s" . "s")
    ("s-S" . "s-S")
    ("s-C" . "s-C")
    ("M" . "M")
    ("C-M" . "C-M")
    ("C-M-S" . "C-M-S")))

;; Published key names in the Emacs vocabulary, or as a person would read them.
(define niri-bind-labels
  '(("RET" . "RET")
    ("ESC" . "ESC")
    ("DEL" . "DEL")
    ("space" . "SPC")
    ("Tab" . "TAB")
    ("Page_Down" . "PgDn")
    ("Page_Up" . "PgUp")
    ("Left" . "←")
    ("Right" . "→")
    ("Up" . "↑")
    ("Down" . "↓")
    ("XF86AudioRaiseVolume" . "Volume Up")
    ("XF86AudioLowerVolume" . "Volume Down")
    ("XF86AudioMute" . "Mute")
    ("XF86AudioPlay" . "Play/Pause")
    ("XF86AudioStop" . "Stop")
    ("XF86AudioPrev" . "Previous track")
    ("XF86AudioNext" . "Next track")
    ("XF86MonBrightnessUp" . "Brightness Up")
    ("XF86MonBrightnessDown" . "Brightness Down")))

(define (niri-key-label bind)
  "Translate one Niri key name to its Emacs-notation label.
Single letters are lowered, because in Emacs notation the case of a character
already means Shift, and this reference spells Shift out as @code{S} instead."
  (or (assoc-ref niri-bind-labels bind)
      (if (and (= (string-length bind) 1)
               (char-alphabetic? (string-ref bind 0)))
          (string-downcase bind)
          bind)))

(define (keybindings-niri-chord binding)
  "Return the Emacs-notation chord for one Niri @var{binding}.

@var{binding} is an entry of @code{(niri-bindings)}.  The modifier is
translated to Emacs notation and a binding without a second key (the
function-row media keys) becomes a single keycap.

@example
(keybindings-niri-chord '((mod . \"s-S\") (bind . \"Q\") ...))
@result{} \"s-S-q\"
@end example"
  (let ((mod (assoc-ref binding 'mod))
        (bind (assoc-ref binding 'bind)))
    (if bind
        (format #f "~a-~a"
                (or (assoc-ref niri-mod-labels mod) mod)
                (niri-key-label bind))
        ;; The function-row keys are bound without a second key, so the
        ;; binding's @code{mod} is the key itself.
        (or (assoc-ref niri-bind-labels mod) mod))))

;; Curated for reading, not generated, so the wording can be friendly while the
;; chords stay exactly the ones (heks-linux niri) writes.  Each section is a
;; title followed by rows of (chord label [note]).
(define niri-key-sections
  `(("Applications & launcher"
     ("s-t" "Open the terminal")
     ("s-RET" "Open the terminal" "same as s-t")
     ("s-e" "Open Emacs")
     ("s-S-t" "New Eshell window in Emacs")
     ("s-S-e" "Emacs in the terminal")
     ("s-i" "Open the browser")
     ("s-S-i" "Open Nyxt")
     ("s-b" "Open Files")
     ("s-m" "Play music in the terminal (RMPC)")
     ("s-SPC" "Open the launcher")
     ("s-/" "Open the launcher" "same as s-SPC")
     ("s-TAB" "Switch between open windows")
     ("s-p" "Power menu")
     ("s-S-c" "Change the theme and palette")
     ("s-v" "Clipboard history")
     ("s-S-b" "Shuffle the wallpaper")
     ("s-S-w" "Browse the wallpapers with a preview")
     ("s-S-d" "Restart the dock"))
    ("Windows"
     ("s-o" "Overview of every workspace")
     ("s-q" "Close the focused window")
     ("s-k" "Close the focused window" "same as s-q")
     ("s-f" "Make the column fill the width")
     ("s-S-f" "Fullscreen")
     ("s-S-SPC" "Float or tile the window")
     ("s-c" "Centre the column")
     ("s-," "Pull the next window into this column")
     ("s-." "Move this window into its own column")
     ("s-r" "Cycle through column widths")
     ("s--" "Narrow the column")
     ("s-=" "Widen the column")
     ("s-S--" "Make the window shorter")
     ("s-S-=" "Make the window taller")
     ("s-ESC" "Let the focused app capture every key"))
    ("Move around"
     ("s-←" "Focus the column to the left")
     ("s-→" "Focus the column to the right")
     ("s-↑" "Focus the window above")
     ("s-↓" "Focus the window below")
     ("s-PgUp" "Previous workspace")
     ("s-PgDn" "Next workspace")
     ("C-M-←" "Focus the monitor to the left")
     ("C-M-→" "Focus the monitor to the right")
     ("C-M-↑" "Focus the monitor above")
     ("C-M-↓" "Focus the monitor below"))
    ("Move windows"
     ("s-S-←" "Move the column left")
     ("s-S-→" "Move the column right")
     ("s-S-↑" "Move the window up")
     ("s-S-↓" "Move the window down")
     ("s-S-PgUp" "Move to the previous workspace")
     ("s-S-PgDn" "Move to the next workspace")
     ("C-M-S-←" "Move to the monitor on the left")
     ("C-M-S-→" "Move to the monitor on the right")
     ("C-M-S-↑" "Move to the monitor above")
     ("C-M-S-↓" "Move to the monitor below"))
    ("Capture the screen"
     ("s-s" "Screenshot: drag a region")
     ("s-S-s" "Screenshot: whole screen")
     ("C-M-s" "Screenshot: focused window")
     ("s-S-g" "Start or stop a GIF recording"))
    ("Session & hardware"
     ("s-l" "Lock the session")
     ("s-S-q" "Log out of the session")
     ("C-M-DEL" "Force-quit the focused app")
     ("s-C-e" "Restart the Emacs server")
     ("s-S-n" "Do not disturb")
     ("Volume Up" "Louder")
     ("Volume Down" "Quieter")
     ("Mute" "Mute or unmute the sound")
     ("Brightness Up" "Brighter")
     ("Brightness Down" "Dimmer")
     ("Play/Pause" "Play or pause the music")
     ("Stop" "Stop the music")
     ("Previous track" "Previous track")
     ("Next track" "Next track"))
    ("Help"
     ("s-?" "Niri's own hotkey overlay")
     ("s-S-/" "This reference, in its own window" "the page you are reading"))))

(define (keybindings-niri-page)
  "Return the Niri page of the reference."
  (list "niri"
        "Niri"
        "The compositor. s is this desktop's Command key."
        niri-key-sections))

;; ===========================================
;; WezTerm
;; ===========================================

(define wezterm-key-sections
  `(("Tabs"
     ("C-x t" "New tab")
     ("C-x 0" "Close the tab")
     ("C-x o" "Next tab")
     ("C-x b" "Pick a tab by name")
     ("C-x ←" "Previous tab")
     ("C-x →" "Next tab")
     ("S-←" "Previous tab")
     ("S-→" "Next tab")
     ("S-↑" "Previous tab" "the vertical arrows are aliases")
     ("S-↓" "Next tab" "the vertical arrows are aliases")
     ("C-TAB" "Next tab")
     ("C-S-TAB" "Previous tab"))
    ("Panes"
     ("C-x 2" "Split below")
     ("C-x 3" "Split to the right")
     ("C-x 1" "Zoom the pane")
     ("C-x g" "Cancel a C-x chord"))
    ("Copy, paste & search"
     ("M-w" "Copy the selection")
     ("C-y" "Paste")
     ("C-Insert" "Copy to the primary selection")
     ("M-s" "Search the scrollback"))
    ("Scrollback"
     ("C-v" "Page down")
     ("M-v" "Page up")
     ("S-PgDn" "Page down")
     ("S-PgUp" "Page up")
     ("S-Home" "Jump to the top")
     ("S-End" "Jump to the bottom"))
    ("Font & window"
     ("C-=" "Bigger font")
     ("C--" "Smaller font")
     ("C-0" "Reset the font size")
     ("M-RET" "Toggle fullscreen"))
    ("When a chord does nothing here"
     ("C-c" "Always reaches the program" "it is the interrupt signal; the terminal never takes it")
     ("C-x" "Always reaches the program" "while Emacs or a pager owns the keyboard"))))

(define (keybindings-wezterm-page)
  "Return the WezTerm page of the reference."
  (list "wezterm"
        "WezTerm"
        "The terminal, wearing Emacs keys. Every chord is handed back to Emacs, a pager, or any full-screen program that owns the keyboard."
        wezterm-key-sections))

;; ===========================================
;; Emacs
;; ===========================================

(define emacs-key-sections
  `(("Files & buffers"
     ("C-x C-f" "Open a file")
     ("C-x C-s" "Save the buffer")
     ("C-x C-w" "Save as")
     ("C-x b" "Switch buffer")
     ("C-x k" "Close the buffer")
     ("C-x C-c" "Quit Emacs"))
    ("Windows"
     ("C-x 2" "Split below")
     ("C-x 3" "Split to the right")
     ("C-x 0" "Close this window")
     ("C-x 1" "Keep only this window")
     ("C-x o" "Move to the other window"))
    ("Moving and editing"
     ("C-s" "Search forward")
     ("C-r" "Search backward")
     ("M-%" "Replace across the buffer")
     ("C-g" "Cancel whatever is happening")
     ("C-SPC" "Start a selection")
     ("M-w" "Copy")
     ("C-w" "Cut")
     ("C-y" "Paste")
     ("C-/" "Undo")
     ("C-a" "Beginning of line")
     ("C-e" "End of line")
     ("M-<" "Beginning of buffer")
     ("M->" "End of buffer"))
    ("Commands & the rest"
     ("M-x" "Run any command by name")
     ("C-x d" "Open a directory (Dired)")
     ("C-x g" "Open Magit")
     ("C-c a" "Org agenda")
     ("C-c c" "Org capture"))))

;; --- heks-emacs, if it is here ---

;; heks-emacs is a separate project with its own release cycle.  The reference
;; reads the file *it* publishes - `maak keys` writes docs/keybindings.org from
;; the configuration itself, and fails when the two disagree - and never calls
;; into it.  So a machine without the checkout gets the curated page and nothing
;; else, and a machine with it gets every key the configuration actually defines.
(define (heks-emacs-reference-file)
  "Return the path of heks-emacs's published keybinding reference, or @code{#f}.

The clone directory is a setting, so the reference follows it wherever the user
keeps it, and a missing file is not an error: it is the ordinary state of a
machine that does not use heks-emacs."
  (let* ((home (or (getenv "HOME") "/tmp"))
         (dir (heks-linux-emacs-clone-dir))
         (expanded (if (string-prefix? "~/" dir)
                       (string-append home (substring dir 1))
                       dir))
         (file (format #f "~a/docs/keybindings.org" expanded)))
    (and (file-exists? file) file)))

(define (keybindings-unquote-cell cell)
  "Strip the org emphasis from one table @var{cell} and trim it."
  (let* ((text (string-trim-both cell))
         (length* (string-length text)))
    (if (and (> length* 1)
             (char=? (string-ref text 0) #\~)
             (char=? (string-ref text (1- length*)) #\~))
        (substring text 1 (1- length*))
        text)))

(define (keybindings-table-cells line)
  "Return the non-empty cells of one org table @var{line}."
  (filter (lambda (cell) (not (string-null? cell)))
          (map string-trim-both (string-split line #\|))))

(define (heks-emacs-topic-title line)
  "Return the section title for one heks-emacs topic header @var{line}.

A header reads @code{** ~C-c !~ diagnostics: Flymake}; the chord becomes the
first half of the title so the section is scannable in the same column as the
keys under it."
  (let* ((rest (substring line 3))
         (close (and (> (string-length rest) 1)
                     (string-index rest #\~ 1))))
    (if close
        (format #f "~a — ~a"
                (substring rest 1 close)
                (string-trim-both (substring rest (1+ close))))
        (string-trim rest))))

(define (heks-emacs-key-sections)
  "Return heks-emacs's keys as sections, ready for the Emacs page.

Each section is a title followed by rows of @code{(chord label command)}: the key
as heks-emacs writes it, the configuration's own words for it, and the command
behind it as a note.  Only the table under @file{The keys, by topic} is read; the
alphabet above it is prose about letters, not keys.

The document is folded rather than walked with a cursor, so a malformed file
degrades into fewer sections instead of an exception in the middle of a render.

@example
(heks-emacs-key-sections)
@result{}
(((\"C-c ! — diagnostics: Flymake\"
   (\"C-c ! N\" \"the previous diagnostic\" \"flymake-goto-prev-error\"))))
@end example"
  (let ((file (heks-emacs-reference-file)))
    (if (not file)
        '()
        (let* ((lines (call-with-input-file file
                        (lambda (port)
                          (string-split (get-string-all port) #\newline))))
               (watch (drop-while (lambda (line)
                                    (not (string-prefix? "* The keys" line)))
                                  lines))
               (folded (fold (lambda (line sections)
                               (cond
                                 ((string-prefix? "** ~" line)
                                  (cons (cons (heks-emacs-topic-title line) '())
                                        sections))
                                 ((and (pair? sections) (string-prefix? "| ~" line))
                                  (let ((cells (keybindings-table-cells line)))
                                    (if (>= (length cells) 3)
                                        (cons (cons (caar sections)
                                                    (cons (list (keybindings-unquote-cell
                                                                 (list-ref cells 0))
                                                                (list-ref cells 2)
                                                                (keybindings-unquote-cell
                                                                 (list-ref cells 1)))
                                                          (cdar sections)))
                                              (cdr sections))
                                        sections)))
                                 (else sections)))
                             '()
                             (if watch watch '()))))
          (map (lambda (section)
                 (cons (car section) (reverse (cdr section))))
               (reverse (filter (lambda (section) (pair? (cdr section)))
                                folded)))))))

(define (keybindings-emacs-page)
  "Return the Emacs page of the reference.

The curated half is stock Emacs, so the page is useful on a machine that has
never seen heks-emacs.  The generated half is whatever that checkout defines,
appended as one section per topic."
  (let ((extra (heks-emacs-key-sections)))
    (list "emacs"
          "Emacs"
          (if (null? extra)
              "Stock Emacs keys, so the muscle memory transfers."
              "Stock Emacs keys, then every topic your heks-emacs checkout defines - read from the reference it publishes.")
          (append emacs-key-sections extra))))

;; ===========================================
;; Rofi
;; ===========================================

(define rofi-key-sections
  `(("The modes"
     ("s-SPC" "Applications")
     ("s-/" "Applications" "same as s-SPC")
     ("s-TAB" "Open windows")
     ("s-p" "Power menu")
     ("s-S-c" "Themes and palettes"))
    ("The palette chooser"
     ("s-S-c" "Open it, or click the palette glyph on the bar" "every palette is a card painted in its own colours")
     ("Click" "Apply that palette" "the desktop, the bar and Emacs all switch")
     ("Typing" "Filter the palettes")
     ("ESC" "Leave the palette alone")
     ("Rofi fallback" "rofi -show theme" "the swatch list, for a machine without a browser"))
    ("The wallpaper gallery"
     ("s-S-w" "Open the collection as a page with a large preview" "the palette's set first, the whole collection after it")
     ("Typing" "Filter by name or folder")
     ("↑ ↓ ← →" "Move the selection; the preview follows it")
     ("RET" "Put the selected wallpaper on the screen")
     ("ESC" "Close the gallery")
     ("s-S-b" "Shuffle without opening anything"))
    ("Moving around"
     ("Type" "Filter the list")
     ("↑" "Move up")
     ("↓" "Move down")
     ("PgUp" "Jump back through the results")
     ("PgDn" "Jump forward through the results")
     ("C-TAB" "Next mode")
     ("C-S-TAB" "Previous mode"))
    ("Choosing"
     ("RET" "Run the selected entry")
     ("ESC" "Close Rofi"))
    ("Clipboard"
     ("s-v" "Search your clipboard history"))))

(define (keybindings-rofi-page)
  "Return the Rofi page of the reference."
  (list "rofi"
        "Rofi"
        "One launcher — applications, windows, power, and themes — plus the palette picker and the wallpaper gallery."
        rofi-key-sections))

;; ===========================================
;; The bar and its notifications
;; ===========================================

(define bar-key-sections
  `(("Waybar"
     ("?" "Open this keyboard reference" "right click opens the Heks Linux project page")
     ("◐" "Current palette: click to switch" "the bar shows the palette in its own accent colour")
     ("▣" "Browse the wallpapers" "opens the gallery: a wall of thumbnails with a large preview")
     ("DND" "Toggle do-not-disturb")
     ("♫" "Play or pause the music" "the title shows what is playing")
     ("🔊" "Open the volume mixer")
     ("🕒" "Open the calendar")
     ("⏻" "Session menu: suspend, hibernate, log out, restart, shut down"))
    ("Mako notifications"
     ("Left click" "Dismiss the banner")
     ("Right click" "Run the notification's default action")
     ("s-S-n" "Do not disturb" "banners stop appearing but nothing is lost; the history keeps them"))))

(define (keybindings-bar-page)
  "Return the bar-and-notifications page of the reference."
  (list "bar"
        "Bar & notifications"
        "What every click on the bar, and on a banner, does."
        bar-key-sections))

;; ===========================================
;; Pages
;; ===========================================

(define (keybindings-pages)
  "Return the pages of the reference, in the order the sidebar lists them.

Each page is @code{(id title tagline sections)}; each section is a title
followed by rows of @code{(chord label [note])}.  Chords use Emacs notation
(@code{s-S-q}, @code{C-x C-f}), and one chord is always rendered as one keycap."
  (list (keybindings-niri-page)
        (keybindings-wezterm-page)
        (keybindings-emacs-page)
        (keybindings-rofi-page)
        (keybindings-bar-page)))

;; ===========================================
;; Rendering
;; ===========================================

(define (keybinding-row-count page)
  "Number of rows on @var{page}."
  (apply + (map (lambda (section)
                  (length (cdr section)))
                (list-ref page 3))))

(define (keybindings-keycaps chord)
  "Render @var{chord} as a single keycap chip.

Emacs notation already says where the keys divide (@code{s-S-q} is one chord,
@code{C-x C-f} is two in sequence), so splitting it again would only make the
column harder to scan."
  `(kbd ,chord))

(define (keybindings-row row)
  "Render one @code{(chord label [note])} row as SXML."
  `(div (@ (class "row"))
        (span (@ (class "keys")) ,(keybindings-keycaps (car row)))
        (span (@ (class "label"))
              ,(cadr row)
              ,@(if (and (>= (length row) 3) (not (string-null? (caddr row))))
                    `((span (@ (class "note")) ,(caddr row)))
                    '()))))

(define (keybindings-group section index)
  "Render one titled group of rows, numbered with @var{index}.

The number is the closest thing this page has to a filing system: it is set in
the monospace face at the accent colour, so a page reads as a numbered specimen
sheet rather than a list of headings."
  `(section (@ (class "group"))
            (h2 (span (@ (class "index")) ,(format #f "~2,'0d" index))
                ,(car section))
            (div (@ (class "rows")) ,@(map keybindings-row (cdr section)))))

(define (keybindings-page-html page)
  "Render one page as SXML: a lede and its grouped rows."
  (let* ((id (list-ref page 0))
         (tagline (list-ref page 2))
         (sections (list-ref page 3))
         (numbered (map cons (iota (length sections)) sections)))
    `(article (@ (class "page") (id ,(format #f "page-~a" id)))
              (p (@ (class "lede")) ,tagline)
              ,@(map (lambda (pair)
                       (keybindings-group (cdr pair) (1+ (car pair))))
                     numbered))))

(define (keybindings-tab page)
  "Render the sidebar tab for @var{page} as SXML."
  `(button (@ (class "tab")
              (type "button")
              (data-page ,(list-ref page 0))
              (aria-selected "false"))
           ,(list-ref page 1)
           (span (@ (class "count")) ,(number->string
                                       (keybinding-row-count page)))))

(define keybindings-page-css
  "nav { display: flex; flex-direction: column; gap: 3px; }
.tab {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  padding: 9px 12px;
  border: 1px solid transparent;
  border-radius: 11px;
  background: transparent;
  color: @text-l@;
  font: inherit;
  font-size: 13.5px;
  text-align: left;
  cursor: pointer;
  transition: background 0.16s ease, color 0.16s ease, box-shadow 0.16s ease;
}
.tab:hover { background: @hover@; color: @text@; }
.tab[aria-selected='true'] {
  background-image: @selected-face@;
  color: @text@;
  box-shadow: inset 0 0 0 1px @primary-edge@, 0 6px 18px -14px @shadow@;
}
.tab .count {
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11.5px;
  font-variant-numeric: tabular-nums;
  opacity: 0.5;
}
.tab[aria-selected='true'] .count { color: @primary@; opacity: 1; }

.toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 20px 12px;
  border-bottom: 1px solid @hairline@;
}
#search {
  flex: 1;
  padding: 10px 14px 10px 34px;
  border: 1px solid @hairline@;
  border-radius: 11px;
  background-color: @field@;
  background-image: @field-magnifier@;
  background-repeat: no-repeat;
  background-position: 12px center;
  background-size: 13px 13px;
  color: @text@;
  font: inherit;
  font-size: 13px;
  outline: none;
  transition: border-color 0.16s ease, box-shadow 0.16s ease;
}
#search::placeholder { color: @text-l@; opacity: 0.75; }
#search:focus { border-color: @primary@; box-shadow: 0 0 0 3px @primary-ghost@; }
.toolbar .hint {
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  color: @text-l@;
  opacity: 0.7;
  white-space: nowrap;
}

.scroller { flex: 1; padding: 16px 20px 30px; overflow-y: auto; scroll-behavior: smooth; }
.page { display: none; }
.page.active { display: block; }
.lede {
  max-width: 68ch;
  margin: 0 2px 20px;
  color: @text-l@;
  font-size: 13.5px;
  line-height: 1.6;
}

.group {
  margin: 0 0 16px;
  padding: 4px 6px 8px;
  border: 1px solid @hairline-soft@;
  border-radius: 16px;
  background-image: @card-face@;
}
.group h2 {
  margin: 8px 10px 6px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: @text-l@;
}
.group h2 .index {
  margin-right: 9px;
  font-family: '@mono@', ui-monospace, monospace;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  color: @primary@;
  opacity: 0.85;
}
.rows { display: flex; flex-direction: column; }
.row {
  display: grid;
  grid-template-columns: minmax(172px, 292px) 1fr;
  gap: 18px;
  align-items: start;
  padding: 9px 10px;
  border-radius: 11px;
  transition: background 0.14s ease;
}
.row:hover { background: @hover@; }
.keys { display: flex; flex-wrap: wrap; gap: 6px; padding-top: 1px; }
.label { font-size: 13.5px; line-height: 1.45; }
.note {
  display: block;
  margin-top: 3px;
  color: @text-l@;
  font-size: 12.5px;
  line-height: 1.4;
}
.note::before {
  content: '» ';
  font-family: '@mono@', ui-monospace, monospace;
  color: @primary@;
  opacity: 0.8;
}
#empty { display: none; padding: 40px 8px; color: @text-l@; font-size: 13px; text-align: center; }
")

(define (keybindings-magnifier palette)
  "Return a magnifier glyph as a data URI, inked in @var{palette}'s text colour.

The search field draws its own icon so the page needs no icon font and no
request: a tiny SVG in the palette's colour, inlined into the stylesheet."
  (let ((ink (string-replace-substring (get-color palette 'text-l)
                                      "#" "%23")))
    (format #f
            "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' stroke='~a' stroke-width='1.6' stroke-linecap='round'><circle cx='6.6' cy='6.6' r='4.6'/><path d='M10.2 10.2 L14 14'/></svg>\")"
            ink)))

(define (keybindings-css palette)
  "Return the page's own stylesheet, painted for @var{palette}.

Only the two tokens the page invents are filled here - the card wash and the
search glyph.  Everything else in the template belongs to the shared shell and is
painted once, over the whole document, by @code{glass-document}."
  (fill-template keybindings-page-css
                 `(("@card-face@" . ,(format #f "linear-gradient(180deg, ~a 0%, transparent 100%)"
                                             (hex-to-rgba (get-color palette 'text)
                                                          #:alpha 0.035)))
                   ("@field-magnifier@" . ,(keybindings-magnifier palette)))))

(define keybindings-script
  "  const tabs = Array.from(document.querySelectorAll('.tab'));
  const pages = Array.from(document.querySelectorAll('.page'));
  const scroller = document.querySelector('.scroller');
  const search = document.getElementById('search');
  const empty = document.getElementById('empty');
  let current = tabs[0].dataset.page;

  function select(id) {
    current = id;
    tabs.forEach(t => t.setAttribute('aria-selected', String(t.dataset.page === id)));
    pages.forEach(p => p.classList.toggle('active', p.id === 'page-' + id));
    scroller.scrollTop = 0;
    filter();
  }

  function filter() {
    const query = search.value.trim().toLowerCase();
    pages.forEach(page => {
      let shown = 0;
      page.querySelectorAll('.row').forEach(row => {
        const hit = !query || row.textContent.toLowerCase().includes(query);
        row.style.display = hit ? '' : 'none';
        if (hit) { shown += 1; }
      });
      page.querySelectorAll('.group').forEach(group => {
        const any = Array.from(group.querySelectorAll('.row'))
          .some(row => row.style.display !== 'none');
        group.style.display = any ? '' : 'none';
      });
      if (page.classList.contains('active')) {
        empty.style.display = shown === 0 ? 'block' : 'none';
      }
    });
  }

  /* Filtering searches every page, so a match on another page is worth
     surfacing: the tab counts stay put and the first match is selected. */
  function jumpToFirstMatch() {
    if (!search.value.trim()) { return; }
    for (const page of pages) {
      const hit = Array.from(page.querySelectorAll('.row'))
        .find(row => row.style.display !== 'none');
      if (hit) {
        select(page.id.replace('page-', ''));
        return;
      }
    }
  }

  tabs.forEach(tab => tab.addEventListener('click', () => select(tab.dataset.page)));
  search.addEventListener('input', filter);
  search.addEventListener('keydown', event => {
    if (event.key === 'Enter') {
      event.preventDefault();
      jumpToFirstMatch();
    }
  });

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (document.activeElement === search && search.value) {
        search.value = '';
        filter();
      } else {
        window.close();
      }
      return;
    }
    if (event.key === '/' && document.activeElement !== search) {
      event.preventDefault();
      search.focus();
      return;
    }
    if (document.activeElement === search) { return; }
    if (event.key >= '1' && event.key <= '9') {
      const index = Number(event.key) - 1;
      if (index < tabs.length) {
        event.preventDefault();
        select(tabs[index].dataset.page);
      }
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'PageDown') {
      event.preventDefault();
      scroller.scrollBy({ top: event.key === 'ArrowDown' ? 64 : scroller.clientHeight * 0.9 });
      return;
    }
    if (event.key === 'ArrowUp' || event.key === 'PageUp') {
      event.preventDefault();
      scroller.scrollBy({ top: event.key === 'ArrowUp' ? -64 : -scroller.clientHeight * 0.9 });
    }
  });

  select(tabs[0].dataset.page);")


(define (keybindings-swatch label colour)
  "Render one palette colour as a labelled chip.

The footer carries a few of these: the reference is generated *from* the palette,
so it may as well show its work.  It is the nerdy half of the page's personality,
and the reason a reader can tell at a glance which theme they are looking at."
  `(span (@ (class "swatch"))
         (i (@ (style ,(format #f "background: ~a" colour))))
         (span ,label)))

(define (keybindings-html)
  "Return the whole keyboard reference as one self-contained HTML document.

The page is a tree of SXML, handed to the shared glass shell, which supplies the
document, the layers behind the panels and the stylesheet.  It carries its own
script, so it opens from a @code{file://} URL with no server and no requests."
  (let* ((pages (keybindings-pages))
         (palette (heks-linux-palette))
         (chords (apply + (map keybinding-row-count pages))))
    (glass-document
     "Heks Linux · Keyboard shortcuts"
     `((div (@ (class "app"))
            (aside ,glass-brand
                   (h1 "Keyboard shortcuts")
                   (p (@ (class "stat"))
                      (b ,(format #f "~2,'0d" (length pages)))
                      " pages · "
                      (b ,(number->string chords))
                      " chords")
                   (nav ,@(map keybindings-tab pages))
                   (div (@ (class "sidebar-foot"))
                        "/ search" (br)
                        "1–" ,(number->string (length pages)) " pages" (br)
                        "esc close"))
            (main (div (@ (class "toolbar"))
                       (input (@ (id "search")
                                 (type "search")
                                 (aria-label "Search keyboard shortcuts")
                                 (placeholder "Search every shortcut…")
                                 (autocomplete "off")
                                 (spellcheck "false")))
                       (span (@ (class "hint"))
                             "palette · " ,(symbol->string palette)))
                  (div (@ (class "scroller"))
                       ,@(map keybindings-page-html pages)
                       (p (@ (id "empty")) "Nothing matches that search."))
                  (footer (span (kbd "/") " search")
                          (span (kbd "1") "–" (kbd ,(number->string (length pages)))
                                " pages")
                          (span (kbd "Esc") " close")
                          (span (@ (class "grow")))
                          ,(glass-credits)
                          (span (@ (class "swatches"))
                                ,(keybindings-swatch "primary"
                                                     (get-color palette 'primary))
                                ,(keybindings-swatch "background"
                                                     (get-color palette 'background))
                                ,(keybindings-swatch "text"
                                                     (get-color palette 'text))))))
       (script (*RAW* ,keybindings-script)))
     #:css (keybindings-css palette)
     #:palette palette)))

;; ===========================================
;; Launcher
;; ===========================================

(define (keybindings-launcher-script)
  "Return the Bash script that opens the reference.

A Chromium-family browser can host the page as an app window, which gives the
reference its own frame instead of a tab; any other browser is opened through
@code{xdg-open}."
  (format #f
          "#!/usr/bin/env bash

# ====== Heks-Linux keyboard shortcuts ======
#
# auto-generated file, DO NOT EDIT!
#
# Opens the rendered keybinding reference.  A browser app window is
# preferred, so the reference reads like a native cheat sheet rather
# than a stray browser tab.

set -u

PAGE=\"~a/~a\"
URL=\"file://$PAGE\"

if [ ! -f \"$PAGE\" ]; then
    echo \"heks-keybindings: $PAGE is missing; run 'maak install-keybindings'\" >&2
    exit 1
fi

if command -v google-chrome >/dev/null 2>&1; then
    exec google-chrome --app=\"$URL\" --window-size=1260,880
elif command -v chromium >/dev/null 2>&1; then
    exec chromium --app=\"$URL\" --window-size=1260,880
elif command -v chromium-browser >/dev/null 2>&1; then
    exec chromium-browser --app=\"$URL\" --window-size=1260,880
elif command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open \"$URL\"
else
    echo \"heks-keybindings: no browser found to open $URL\" >&2
    exit 1
fi
"
          (keybindings-dir)
          (keybindings-filename)))

;; ===========================================
;; Installation
;; ===========================================

(define* (install-keybindings-config)
  "Write the keybinding reference and its launcher script.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/keybindings-settings.scm} first.  Nothing has
to be restarted: the script reads the HTML file every time it runs.  Run
@code{maak install-theme} after a palette change so the page is repainted."
  (log-info s "Installing keybinding reference")
  (load-local-overrides '(heks-linux keybindings)
                        'keybindings-settings)
  (install-config-file! #:name (keybindings-filename)
                        #:dir (keybindings-dir)
                        #:contents (keybindings-html))
  (install-config-file! #:name (keybindings-launcher-filename)
                        #:dir (keybindings-launcher-dir)
                        #:contents (keybindings-launcher-script)
                        #:perms 493)
  (log-success s "Installed keybinding reference"))
