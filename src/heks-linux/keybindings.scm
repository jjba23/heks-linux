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
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (ice-9 format)
  #:export (keybindings-pages
            keybindings-html
            keybindings-launcher-script
            keybindings-niri-chord
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
     ("s-S-w" "Pick a wallpaper from the collection")
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
     ("s-S-/" "Niri's own hotkey overlay" "fallback"))))

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

(define (keybindings-emacs-page)
  "Return the Emacs page of the reference."
  (list "emacs"
        "Emacs"
        "Stock Emacs keys, so the muscle memory transfers."
        emacs-key-sections))

;; ===========================================
;; Rofi
;; ===========================================

(define rofi-key-sections
  `(("The four modes"
     ("s-SPC" "Applications")
     ("s-/" "Applications" "same as s-SPC")
     ("s-TAB" "Open windows")
     ("s-p" "Power menu")
     ("s-S-c" "Themes and palettes"))
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
        "One launcher, four modes: applications, windows, power, and themes."
        rofi-key-sections))

;; ===========================================
;; The bar and its notifications
;; ===========================================

(define bar-key-sections
  `(("Waybar"
     ("?" "Open this keyboard reference" "right click opens the Heks Linux project page")
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

(define (keybindings-escape text)
  "Escape @var{text} for inclusion in an HTML document."
  (with-output-to-string
      (lambda ()
        (string-for-each
         (lambda (ch)
           (display
            (case ch
              ((#\&) "&amp;")
              ((#\<) "&lt;")
              ((#\>) "&gt;")
              ((#\") "&quot;")
              (else (string ch)))))
         text))))

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
  (format #f "<kbd>~a</kbd>" (keybindings-escape chord)))

(define (keybindings-row row)
  "Render one @code{(chord label [note])} row."
  (format #f "<div class=\"row\"><span class=\"keys\">~a</span><span class=\"label\">~a~a</span></div>"
          (keybindings-keycaps (car row))
          (keybindings-escape (cadr row))
          (if (and (>= (length row) 3) (not (string-null? (caddr row))))
              (format #f "<span class=\"note\">~a</span>"
                      (keybindings-escape (caddr row)))
              "")))

(define (keybindings-group section)
  "Render one titled group of rows."
  (format #f "<section class=\"group\"><h2>~a</h2><div class=\"rows\">~a</div></section>"
          (keybindings-escape (car section))
          (string-join (map keybindings-row (cdr section)) "")))

(define (keybindings-page-html page)
  "Render one page: a lede and its grouped rows."
  (let ((id (list-ref page 0))
        (tagline (list-ref page 2))
        (sections (list-ref page 3)))
    (format #f "<article class=\"page\" id=\"page-~a\"><p class=\"lede\">~a</p>~a</article>"
            id
            (keybindings-escape tagline)
            (string-join (map keybindings-group sections) ""))))

(define (keybindings-tab page)
  "Render the sidebar tab for @var{page}."
  (format #f "<button class=\"tab\" type=\"button\" data-page=\"~a\" aria-selected=\"false\">~a<span class=\"count\">~a</span></button>"
          (list-ref page 0)
          (keybindings-escape (list-ref page 1))
          (keybinding-row-count page)))

(define (keybindings-css palette)
  "Return the stylesheet, painted from @var{palette}."
  (let ((dark? (is-dark-palette palette))
        (bg (get-color palette 'background))
        (bg-l (get-color palette 'background-l))
        (text (get-color palette 'text))
        (text-l (get-color palette 'text-l))
        (primary (get-color palette 'primary))
        (sans (heks-linux-sans-font))
        (mono (heks-linux-mono-font)))
    (format #f
            "* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  background: ~a;
  color: ~a;
  font-family: '~a', system-ui, -apple-system, sans-serif;
  -webkit-font-smoothing: antialiased;
  color-scheme: ~a;
}
.app { display: flex; height: 100vh; }
aside {
  flex: 0 0 248px;
  width: 248px;
  padding: 22px 14px;
  background: ~a;
  border-right: 1px solid ~a;
  overflow-y: auto;
}
.brand {
  margin: 0 10px 4px;
  font-size: 10.5px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: ~a;
}
h1 { margin: 0 10px 18px; font-size: 19px; font-weight: 650; letter-spacing: -0.01em; }
nav { display: flex; flex-direction: column; gap: 2px; }
.tab {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  padding: 9px 12px;
  border: 0;
  border-radius: 9px;
  background: transparent;
  color: ~a;
  font: inherit;
  font-size: 13.5px;
  text-align: left;
  cursor: pointer;
  transition: background 0.15s ease, color 0.15s ease;
}
.tab:hover { background: ~a; }
.tab[aria-selected='true'] { background: ~a; color: #ffffff; }
.tab .count { font-size: 11.5px; opacity: 0.55; font-variant-numeric: tabular-nums; }
.tab[aria-selected='true'] .count { opacity: 0.8; }
main { display: flex; flex: 1; flex-direction: column; min-width: 0; }
.toolbar { padding: 18px 28px 8px; }
#search {
  width: 100%;
  padding: 11px 14px;
  border: 1px solid ~a;
  border-radius: 10px;
  background: ~a;
  color: ~a;
  font: inherit;
  font-size: 13.5px;
  outline: none;
}
#search:focus { border-color: ~a; box-shadow: 0 0 0 3px ~a; }
.scroller { flex: 1; padding: 8px 28px 36px; overflow-y: auto; scroll-behavior: smooth; }
.page { display: none; }
.page.active { display: block; }
.lede { max-width: 62ch; margin: 6px 0 22px; color: ~a; font-size: 13.5px; line-height: 1.55; }
.group { margin: 0 0 26px; }
.group h2 {
  margin: 0 0 8px 12px;
  font-size: 10.5px;
  font-weight: 650;
  letter-spacing: 0.13em;
  text-transform: uppercase;
  color: ~a;
}
.rows { display: flex; flex-direction: column; gap: 2px; }
.row {
  display: grid;
  grid-template-columns: minmax(150px, 260px) 1fr;
  gap: 18px;
  align-items: start;
  padding: 9px 12px;
  border-radius: 9px;
  transition: background 0.12s ease;
}
.row:hover { background: ~a; }
.keys { display: flex; flex-wrap: wrap; gap: 5px; }
kbd {
  padding: 3px 7px;
  border: 1px solid ~a;
  border-bottom-color: ~a;
  border-radius: 6px;
  background: ~a;
  box-shadow: 0 1px 0 ~a;
  font-family: '~a', ui-monospace, monospace;
  font-size: 11.5px;
  line-height: 1.25;
  white-space: nowrap;
}
.label { font-size: 13.5px; line-height: 1.45; }
.note { display: block; margin-top: 2px; color: ~a; font-size: 12.5px; }
#empty { display: none; padding: 10px 12px; color: ~a; font-size: 13.5px; }
footer {
  display: flex;
  gap: 18px;
  padding: 10px 28px 14px;
  border-top: 1px solid ~a;
  color: ~a;
  font-size: 11.5px;
}
footer kbd { font-size: 10.5px; padding: 2px 6px; }
::-webkit-scrollbar { width: 11px; }
::-webkit-scrollbar-thumb { border: 3px solid transparent; border-radius: 999px; background-clip: content-box; background-color: ~a; }
::-webkit-scrollbar-track { background: transparent; }
"
            bg
            text
            sans
            (if dark? "dark" "light")
            bg-l
            (hex-to-rgba text #:alpha 0.10)
            text-l
            text
            (hex-to-rgba text #:alpha 0.06)
            primary
            (hex-to-rgba primary #:alpha 0.10)
            bg-l
            text
            primary
            (hex-to-rgba primary #:alpha 0.20)
            text-l
            text-l
            (hex-to-rgba text #:alpha 0.04)
            (hex-to-rgba text #:alpha 0.12)
            (hex-to-rgba text #:alpha 0.22)
            bg
            (hex-to-rgba text #:alpha 0.12)
            mono
            text-l
            text-l
            (hex-to-rgba text #:alpha 0.10)
            text-l
            (hex-to-rgba text #:alpha 0.28))))

(define keybindings-script
  "  const tabs = Array.from(document.querySelectorAll('.tab'));
  const pages = Array.from(document.querySelectorAll('.page'));
  const scroller = document.querySelector('.scroller');
  const search = document.getElementById('search');
  const empty = document.getElementById('empty');

  function select(id) {
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

  tabs.forEach(tab => tab.addEventListener('click', () => select(tab.dataset.page)));
  search.addEventListener('input', filter);

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (document.activeElement === search && search.value) {
        search.value = '';
        filter();
      } else {
        window.close();
      }
    } else if (event.key === '/' && document.activeElement !== search) {
      event.preventDefault();
      search.focus();
    }
  });

  select(tabs[0].dataset.page);")

(define (keybindings-html)
  "Return the whole keyboard reference as one self-contained HTML document.

The document carries its own stylesheet and script, so it opens from a
@code{file://} URL with no server and no network access."
  (let ((pages (keybindings-pages)))
    (string-append "<!DOCTYPE html>\n"
                   "<html lang=\"en\">\n<head>\n"
                   "<meta charset=\"utf-8\">\n"
                   "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
                   "<title>Heks Linux · Keyboard shortcuts</title>\n"
                   "<style>\n" (keybindings-css (heks-linux-palette))
                   "</style>\n"
                   "</head>\n<body>\n"
                   "<div class=\"app\">\n"
                   "<aside>\n"
                   "<p class=\"brand\">Heks GNU/Linux</p>\n"
                   "<h1>Keyboard shortcuts</h1>\n"
                   "<nav>\n"
                   (string-join (map keybindings-tab pages) "\n")
                   "\n</nav>\n</aside>\n"
                   "<main>\n"
                   "<div class=\"toolbar\">\n"
                   "<input id=\"search\" type=\"search\" aria-label=\"Search keyboard shortcuts\" placeholder=\"Search every shortcut…\" autocomplete=\"off\" spellcheck=\"false\">\n"
                   "</div>\n"
                   "<div class=\"scroller\">\n"
                   (string-join (map keybindings-page-html pages) "\n")
                   "\n<p id=\"empty\">Nothing matches that search.</p>\n"
                   "</div>\n"
                   "<footer><span><kbd>/</kbd> search</span><span><kbd>Esc</kbd> close</span>"
                   "<span>Heks renders this page from the same palette as the desktop.</span></footer>\n"
                   "</main>\n</div>\n"
                   "<script>\n" keybindings-script "\n</script>\n"
                   "</body>\n</html>\n")))

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
    exec google-chrome --app=\"$URL\" --window-size=1180,820
elif command -v chromium >/dev/null 2>&1; then
    exec chromium --app=\"$URL\" --window-size=1180,820
elif command -v chromium-browser >/dev/null 2>&1; then
    exec chromium-browser --app=\"$URL\" --window-size=1180,820
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
