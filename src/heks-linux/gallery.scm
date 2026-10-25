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
;; The wallpaper gallery: a window that shows the collection, large.
;;
;; Rofi makes a fine launcher and a poor picture browser.  It has no preview
;; pane - a dmenu row is a list row - so the best it can do for a wallpaper is a
;; thumbnail in a grid, and choosing a background from 200px squares is guess
;; work.  This module is the answer to that: a page in the same visual language
;; as the keybinding reference, served from a socket only this machine can
;; reach, showing the wallpapers as a filterable wall with a large preview of
;; whatever is selected.
;;
;; The shape is three pieces:
;;
;;   1. @code{gallery-images} walks the collection and puts the palette's own
;;      set first - the same order the rest of the wallpaper engine uses;
;;   2. @code{gallery-html} renders the page, painted from the palette, with no
;;      external asset and no network: every byte the browser needs is either in
;;      the document or served from this socket;
;;   3. @code{gallery-handler} answers the page: thumbnails (generated once with
;;      ImageMagick and cached), and the three calls that change the wallpaper.
;;
;; The server binds to 127.0.0.1 and accepts no path outside the collection, so
;; the only thing a page in the browser can ask it to do is set a wallpaper that
;; is already on disk.
;;
;;; Code:

(define-module (heks-linux gallery)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (web uri)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web server)
  #:use-module (heks-linux glass)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux wallpaper)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (gallery-port
            gallery-idle-seconds
            gallery-progress-file
            gallery-preview-width
            gallery-ready-file
            gallery-switch-stages
            gallery-palette-status
            gallery-progress-read
            gallery-launcher-filename
            palette-launcher-filename
            gallery-launcher-dir
            gallery-cache-dir
            gallery-command
            palette-command
            palette-card
            gallery-images
            gallery-html
            gallery-cell
            gallery-unresolved-tokens
            gallery-thumbnail
            gallery-handler
            run-gallery-server
            main
            mk-gallery-launcher-cmd
            install-gallery-config))

(define s
  (scriba-auto-logger))

;; --- Settings ---

;; The port the gallery answers on.  It is loopback only, and a fixed port per
;; user is what lets a second launch reuse the server the first one started
;; instead of leaving a second one behind.
(define gallery-port
  (make-parameter 48090))

;; How long the server waits for another request before it exits, in seconds.
;; The page asks it to close when the window goes away, so this is only the
;; backstop for a browser that crashes or a tab that is killed.
(define gallery-idle-seconds
  (make-parameter 120))

(define gallery-launcher-filename
  (make-parameter "heks-wallpaper-gallery"))

;; The same page, opened on its second tab.  Two scripts rather than one with an
;; argument, because each of them is a keybinding target and a keybinding should
;; not have to remember a flag.
(define palette-launcher-filename
  (make-parameter "heks-palette-gallery"))

(define gallery-launcher-dir
  (make-parameter (string-append (or (getenv "HOME") "/tmp")
                                 "/.local/bin")))

;; Thumbnails are generated on demand and cached here, keyed by the image's
;; modification time, so a wallpaper that is replaced gets a new thumbnail.
(define gallery-cache-dir
  (make-parameter
   (string-append (let ((xdg (getenv "XDG_CACHE_HOME")))
                    (if (and xdg (not (string=? xdg "")))
                        xdg
                        (string-append (or (getenv "HOME") "/tmp") "/.cache")))
                  "/heks-linux/gallery")))

;; The width the preview image is rendered at.  Wider than the pane on purpose:
;; the page can zoom to six times the fitted size, and a picture that goes soft
;; the moment it is inspected is no preview.
(define gallery-preview-width
  (make-parameter 2400))

;; Where the palette picker writes the stage it is currently in.  The picker and
;; this server have to agree on the path without sharing code, so it is written
;; down once here and once in the generated script - which is why the tests
;; compare the two.
(define gallery-progress-file
  (make-parameter
   (format #f "~a/heks-theme-progress"
           (or (getenv "XDG_RUNTIME_DIR") "/tmp"))))

;; The stages a switch passes through, in order.  A stage in this list that is
;; no longer moving means the picker died rather than finished.
(define gallery-switch-stages
  '("starting" "settings" "rendering" "wallpaper" "emacs"))

(define (gallery-launcher-path filename)
  "Return @var{filename} under the launcher directory, with the home directory
written as a tilde, ready for a Niri binding or a bar button."
  (let* ((dir (gallery-launcher-dir))
         (home (or (getenv "HOME") "/tmp"))
         (path (format #f "~a/~a" dir filename)))
    (if (string-prefix? home path)
        (string-append "~" (substring path (string-length home)))
        path)))

(define (gallery-command)
  "Return the wallpaper gallery launcher as a shell word.

The home directory is written as a tilde so the generated binding stays
portable between machines."
  (gallery-launcher-path (gallery-launcher-filename)))

(define (palette-command)
  "Return the palette chooser launcher as a shell word.

It is the same page as the gallery, opened on the palettes tab."
  (gallery-launcher-path (palette-launcher-filename)))

;; --- The collection ---

(define %gallery-image-extensions
  '(".jpg" ".jpeg" ".png" ".webp" ".gif" ".jxl"))

(define (gallery-image-path? path)
  "Whether @var{path} names an image the renderers can display."
  (any (lambda (extension)
         (string-suffix-ci? extension path))
       %gallery-image-extensions))

(define (gallery-walk-images dir)
  "Return every image below @var{dir}, sorted, skipping dot directories.

The collection is a git clone, so walking it means deciding what not to walk:
@file{.git} alone would add thousands of objects that are not pictures."
  (catch #t
    (lambda ()
      (append-map (lambda (name)
                    (let ((full (string-append dir "/" name)))
                      (cond
                        ((string-prefix? "." name) '())
                        ((eq? 'directory (stat:type (stat full)))
                         (gallery-walk-images full))
                        ((gallery-image-path? name) (list full))
                        (else '()))))
                  (scandir dir string<?)))
    (lambda _ '())))

(define* (gallery-images #:key (palette (heks-linux-palette)))
  "Return the collection as gallery entries, the palette's set first.

Each entry is an association list with @code{path}, @code{name},
@code{folder}, @code{palette?} and @code{current?}.  The palette's own set
leads because a wallpaper that matches the colours is the likeliest choice, and
an entry in it is marked rather than moved so the rest of the wall keeps its
folder order."
  (let* ((root (wallpaper-catalog-dir))
         (palette-set (parameterize ((heks-linux-palette palette))
                        (wallpapers)))
         (current (let ((file (string-append
                               (let ((xdg (getenv "XDG_STATE_HOME")))
                                 (if (and xdg (not (string=? xdg "")))
                                     xdg
                                     (string-append (or (getenv "HOME") "/tmp")
                                                    "/.local/state")))
                               "/heks-linux/wallpaper")))
                    (if (file-exists? file)
                        (string-trim-both
                         (call-with-input-file file
                           (lambda (port) (get-string-all port))))
                        "")))
         (all (gallery-walk-images root))
         (others (remove (lambda (path)
                           (member path palette-set))
                         all)))
    (map (lambda (path)
           `((path . ,path)
             (name . ,(basename path))
             (folder . ,(let ((dir (dirname path)))
                          (if (string-prefix? (string-append root "/") dir)
                              (substring dir (string-length root))
                              dir)))
             (palette? . ,(if (member path palette-set) #t #f))
             (current? . ,(string=? path current))))
         (append (filter file-exists? palette-set) others))))

;; --- Thumbnails ---

(define (gallery-thumbnail-path path width)
  "Return the cache file for @var{path} at @var{width}, without generating it."
  (let* ((stamp (catch #t
                  (lambda () (number->string (stat:mtime (stat path))))
                  (lambda _ "0")))
         (key (string-hash (string-append path stamp (number->string width)))))
    (format #f "~a/~a-~a-~a.jpg"
            (gallery-cache-dir)
            (path-basename-safe path)
            width
            key)))

(define (path-basename-safe path)
  "Return the base name of @var{path} with anything a file name cannot hold
replaced, so a cache entry is always a legal file name."
  (list->string (map (lambda (ch)
                       (if (or (char-alphabetic? ch)
                               (char-numeric? ch)
                               (memq ch '(#\- #\_ #\.)))
                           ch
                           #\_))
                     (string->list (basename path)))))

(define (gallery-thumbnail path width)
  "Return the cached thumbnail of @var{path} at @var{width} pixels.

The image is scaled to fit inside a @var{width} square, which keeps its aspect
ratio; the page decides how to frame it.  ImageMagick does the work once and
the file is reused until the source changes."
  (let ((out (gallery-thumbnail-path path width)))
    (unless (file-exists? out)
      (ensure-directory-tree! (gallery-cache-dir))
      (catch #t
        (lambda ()
          (system* "magick" path "-auto-orient"
                   "-thumbnail" (format #f "~ax~a" width width)
                   "-quality" "82" out))
        (lambda _ #f)))
    (and (file-exists? out) out)))

;; --- The page ---

;; The page's own rules.  The shell paints the frame, the glass, the brand, the
;; keycap and the footer; this is about the wall of pictures, the preview beside
;; it and the palette cards.
(define gallery-page-css
  "
.pane { display: none; flex: 1; min-height: 0; }
.pane.active { display: flex; }
.split { display: flex; flex: 1; min-height: 0; }

#wall {
  flex: 1;
  padding: 16px 18px 30px;
  overflow-y: auto;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(168px, 1fr));
  /* Rows are sized by their content, explicitly: without this the grid
     distributes the pane's height across the rows, because a cell clips its
     contents and a clipped grid item contributes no minimum height - the wall
     then renders as a list of slivers. */
  grid-auto-rows: max-content;
  gap: 13px;
  align-content: start;
}
.cell {
  position: relative;
  padding: 0;
  border: 1px solid @hairline-soft@;
  border-radius: 12px;
  background-color: @cell@;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
  overflow: hidden;
  transition: border-color 0.14s ease, transform 0.14s ease, box-shadow 0.14s ease;
}
/* The frame keeps a 16:10 window whatever the picture's own shape is.  The
   ratio is padding because a percentage padding resolves against the width,
   while an aspect-ratio on the image makes its contribution to the grid row
   indefinite. */
.frame { position: relative; padding-top: 62.5%; overflow: hidden; }
.frame img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; display: block; }
.cell .caption {
  display: block;
  padding: 7px 9px;
  font-size: 11.5px;
  line-height: 1.25;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  color: @text-l@;
}
.cell .badge {
  position: absolute;
  top: 7px;
  right: 7px;
  padding: 2px 7px;
  border-radius: 999px;
  font-family: @mono@, ui-monospace, monospace;
  font-size: 9.5px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  display: none;
}
.cell.in-palette .badge { display: block; background: @primary@; color: @on-primary@; }
.cell.is-current .badge { display: block; background: @text@; color: @background@; }
.cell:hover { transform: translateY(-1px); border-color: @hairline@; box-shadow: 0 12px 30px -22px @shadow@; }
.cell.selected { border-color: @primary@; box-shadow: 0 0 0 2px @primary-ghost@; }

#preview {
  flex: 0 0 42%;
  display: flex;
  flex-direction: column;
  gap: 11px;
  padding: 16px 18px 18px;
  border-left: 1px solid @hairline@;
  min-width: 0;
}
#preview h2 { margin: 0; font-size: 14px; font-weight: 650; overflow-wrap: anywhere; }
#preview p { margin: 0; font-size: 12px; color: @text-l@; overflow-wrap: anywhere; }
#preview .policy { display: flex; gap: 8px; }
#preview .policy button {
  padding: 9px 15px;
  border: 0;
  border-radius: 9px;
  background: @primary@;
  color: @on-primary@;
  font: inherit;
  font-size: 13px;
  font-weight: 650;
  cursor: pointer;
}
#preview .policy button.ghost {
  background: transparent;
  color: @text-l@;
  border: 1px solid @hairline@;
}
#preview .hint { font-size: 11px; color: @text-l@; }

/* The picture is framed by its own edges: max-width and max-height keep the
   whole wallpaper visible while the border hugs the image instead of a
   letterboxed box, which is what made a wide wallpaper look lost in a tall
   pane.  Zoom and pan ride on custom properties so every rule that moves the
   picture moves the same two numbers. */
#preview .stage {
  position: relative;
  flex: 1;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}
#preview .stage img {
  max-width: 100%;
  max-height: 100%;
  width: auto;
  height: auto;
  border-radius: 12px;
  background: @background@;
  border: 1px solid @hairline-soft@;
  transform: translate(var(--pan-x, 0px), var(--pan-y, 0px)) scale(var(--zoom, 1));
  transform-origin: center center;
  transition: transform 0.1s ease-out;
}
#preview .stage.is-zoomed { cursor: grab; }
#preview .stage.is-panning { cursor: grabbing; }
#preview .stage.is-panning img { transition: none; }

/* Zoom lives over the picture rather than beside it, so the wallpaper keeps the
   whole pane.  It fades back until the pane is touched: it is a tool, not a
   headline. */
#preview .zoom {
  position: absolute;
  top: 10px;
  right: 10px;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 3px;
  border-radius: 999px;
  border: 1px solid @hairline@;
  background-color: @glass-strong@;
  -webkit-backdrop-filter: blur(16px);
  backdrop-filter: blur(16px);
  opacity: 0.62;
  transition: opacity 0.15s ease;
}
#preview .stage:hover .zoom,
#preview .zoom:focus-within { opacity: 1; }
#preview .zoom button {
  padding: 5px 9px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: @text@;
  font: inherit;
  font-size: 13px;
  line-height: 1;
  cursor: pointer;
}
#preview .zoom button:hover { background: @hover@; }
/* The middle of the cluster is the state and the way back to it: at fit it says
   Fit, at 150% it says 150% and clicking it fits again. */
#preview .zoom .level {
  min-width: 44px;
  padding: 5px 6px;
  font-family: @mono@, ui-monospace, monospace;
  font-size: 10.5px;
  color: @text-l@;
}

/* The palettes: one card per palette, painted in that palette, so judging a
   theme is looking at it rather than reading its name. */
#palettes {
  flex: 1;
  padding: 16px 18px 30px;
  overflow-y: auto;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  grid-auto-rows: max-content;
  gap: 13px;
  align-content: start;
}
.palette-card {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 14px;
  border: 1px solid var(--card-edge);
  border-radius: 13px;
  background-color: var(--card-bg);
  color: var(--card-text);
  cursor: pointer;
  text-align: left;
  font: inherit;
  transition: transform 0.14s ease, box-shadow 0.14s ease;
}
.palette-card:hover { transform: translateY(-1px); box-shadow: 0 18px 40px -26px rgba(0, 0, 0, 0.9); }
.palette-card.is-current { box-shadow: 0 0 0 2px var(--card-primary); border-color: transparent; }
.palette-card .head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
}
.palette-card .name {
  font-family: @mono@, ui-monospace, monospace;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--card-text);
}
.palette-card .mark {
  font-family: @mono@, ui-monospace, monospace;
  font-size: 9.5px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--card-primary);
}
.palette-card .sample { font-size: 12.5px; line-height: 1.6; color: var(--card-text-l); }
.palette-card kbd {
  font-size: 11px;
  padding: 3px 7px;
  border-radius: 7px;
  border: 1px solid var(--card-edge);
  background-image: none;
  background-color: var(--card-primary);
  color: var(--card-on-primary);
  box-shadow: none;
  text-shadow: none;
}
.palette-card .bars { display: flex; gap: 4px; }
.palette-card .bars i {
  flex: 1;
  height: 6px;
  border-radius: 999px;
  border: 1px solid var(--card-edge);
}

#toast {
  position: fixed;
  /* Above .app, which is a stacking context of its own: a fixed element with no
     z-index paints underneath it and is never seen. */
  z-index: 10;
  bottom: 74px;
  left: 50%;
  transform: translateX(-50%) translateY(6px);
  padding: 9px 16px;
  border-radius: 999px;
  border: 1px solid @hairline@;
  background-color: @glass-strong@;
  -webkit-backdrop-filter: blur(20px);
  backdrop-filter: blur(20px);
  color: @text@;
  font-size: 12.5px;
  font-weight: 600;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.18s ease, transform 0.18s ease;
}
#toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

/* The switch notice: applying a palette rewrites the settings, re-renders every
   generated dotfile, changes the wallpaper and re-themes Emacs.  That is several
   seconds of the window looking frozen, so the page says which stage it is in
   and how long it has been there.  It sits below the toast: the toast is the
   answer, this is the working. */
#switch {
  position: fixed;
  /* Same reason as the toast, plus one of its own: this one has to be readable
     while the page under it is being repainted. */
  z-index: 10;
  left: 50%;
  bottom: 74px;
  width: 380px;
  transform: translateX(-50%) translateY(10px);
  padding: 13px 16px 14px;
  border-radius: 16px;
  border: 1px solid @hairline@;
  background-color: @glass-strong@;
  -webkit-backdrop-filter: blur(20px);
  backdrop-filter: blur(20px);
  box-shadow: 0 24px 60px -30px rgba(0, 0, 0, 0.9);
  color: @text@;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.2s ease, transform 0.2s ease;
}
#switch.show { opacity: 1; transform: translateX(-50%) translateY(0); }
#switch .line {
  display: flex;
  align-items: baseline;
  gap: 8px;
  font-size: 12.5px;
}
#switch .stage { font-weight: 600; }
#switch .name {
  font-family: @mono@, ui-monospace, monospace;
  font-size: 11.5px;
  color: @text-l@;
}
#switch .elapsed {
  margin-left: auto;
  font-family: @mono@, ui-monospace, monospace;
  font-size: 11px;
  color: @text-l@;
}
#switch .bar {
  margin-top: 10px;
  height: 4px;
  border-radius: 999px;
  background-color: @cell@;
  overflow: hidden;
}
#switch .bar i {
  display: block;
  height: 100%;
  width: 0;
  border-radius: inherit;
  background-color: @primary@;
  transition: width 0.45s ease;
}
#switch .note {
  margin: 8px 0 0;
  font-size: 11px;
  line-height: 1.5;
  color: @text-l@;
}
#switch.is-done .bar i { background-color: @primary@; }
#switch.is-failed .stage { color: #e5484d; }
#switch.is-failed .bar i { background-color: #e5484d; }

/* A card that is being applied: ringed, and no cursor invitation to click it
   again while the switch it started is still running. */
.palette-card.is-busy { box-shadow: 0 0 0 2px var(--card-primary); cursor: progress; }

#empty, #empty-palettes { display: none; padding: 40px 8px; color: @text-l@; font-size: 13px; text-align: center; }
")

(define gallery-script
  "  const tabs = Array.from(document.querySelectorAll('.tab'));
  const panes = Array.from(document.querySelectorAll('.pane'));
  const filter = document.getElementById('filter');
  const wall = document.getElementById('wall');
  const cells = Array.from(wall.querySelectorAll('.cell'));
  const palettes = Array.from(document.querySelectorAll('.palette-card'));
  const image = document.getElementById('preview-image');
  const name = document.getElementById('preview-name');
  const folder = document.getElementById('preview-folder');
  const emptyWall = document.getElementById('empty');
  const emptyPalettes = document.getElementById('empty-palettes');
  const toast = document.getElementById('toast');
  const preview = document.getElementById('preview');
  const stage = preview.querySelector('.stage');
  const zoomLevel = preview.querySelector('.level');
  const zoomIn = preview.querySelector('.zoom-in');
  const zoomOut = preview.querySelector('.zoom-out');
  const zoomFit = preview.querySelector('.zoom-fit');
  const switcher = document.getElementById('switch');
  const switchStage = switcher.querySelector('.stage');
  const switchName = switcher.querySelector('.name');
  const switchElapsed = switcher.querySelector('.elapsed');
  const switchFill = switcher.querySelector('.fill');
  const switchNote = switcher.querySelector('.note');
  let selected = null;
  let mode = 'wallpapers';
  let busy = false;
  let pending = null;
  let poll = null;
  /* Zoom is a multiplier on the fitted picture, so 1 is always the whole
     wallpaper.  Pan is in pixels, and is clamped to whatever the zoom has
     pushed outside the pane. */
  let zoom = 1;
  let panX = 0;
  let panY = 0;
  let drag = null;
  const ZOOM_MIN = 1;
  const ZOOM_MAX = 6;

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => toast.classList.remove('show'), 2400);
  }

  function select(cell, scroll) {
    if (!cell) { return; }
    cells.forEach(other => other.classList.toggle('selected', other === cell));
    selected = cell;
    image.src = '/preview?path=' + encodeURIComponent(cell.dataset.path);
    name.textContent = cell.dataset.name;
    folder.textContent = cell.dataset.folder;
    /* A new wallpaper arrives fitted: the point of the preview is to show all of
       it, and a zoom left over from the last picture would hide the edges of
       this one. */
    resetZoom();
    if (scroll) { cell.scrollIntoView({ block: 'nearest' }); }
  }

  function clampPan() {
    if (zoom <= 1) { panX = 0; panY = 0; return; }
    const rect = stage.getBoundingClientRect();
    const maxX = Math.max(0, (rect.width * (zoom - 1)) / 2);
    const maxY = Math.max(0, (rect.height * (zoom - 1)) / 2);
    panX = Math.max(-maxX, Math.min(maxX, panX));
    panY = Math.max(-maxY, Math.min(maxY, panY));
  }

  function drawZoom() {
    stage.style.setProperty('--zoom', zoom);
    stage.style.setProperty('--pan-x', panX + 'px');
    stage.style.setProperty('--pan-y', panY + 'px');
    stage.classList.toggle('is-zoomed', zoom > 1.001);
    zoomLevel.textContent = zoom > 1.001 ? Math.round(zoom * 100) + '%' : 'Fit';
  }

  function setZoom(next) {
    zoom = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, next));
    clampPan();
    drawZoom();
  }

  function zoomBy(factor) {
    if (!selected) { return; }
    setZoom(zoom * factor);
  }

  function resetZoom() {
    zoom = 1;
    panX = 0;
    panY = 0;
    drag = null;
    if (stage) { stage.classList.remove('is-panning'); }
    drawZoom();
  }

  function visible() {
    return cells.filter(cell => cell.style.display !== 'none');
  }

  function setMode(next) {
    mode = next;
    tabs.forEach(t => t.setAttribute('aria-selected', String(t.dataset.pane === next)));
    panes.forEach(p => p.classList.toggle('active', p.id === 'pane-' + next));
    filter.value = '';
    filter.placeholder = next === 'palettes'
      ? 'Filter palettes…'
      : 'Filter wallpapers by name or folder…';
    applyFilter();
    if (next === 'palettes') { history.replaceState(null, '', '#palettes'); pollStatus(true); }
    else { history.replaceState(null, '', location.pathname); }
  }

  function applyFilter() {
    const query = filter.value.trim().toLowerCase();
    if (mode === 'wallpapers') {
      let shown = 0;
      cells.forEach(cell => {
        const haystack = (cell.dataset.name + ' ' + cell.dataset.folder).toLowerCase();
        const hit = !query || haystack.includes(query);
        cell.style.display = hit ? '' : 'none';
        if (hit) { shown += 1; }
      });
      emptyWall.style.display = shown === 0 ? 'block' : 'none';
      if (selected && selected.style.display === 'none') {
        const next = visible()[0];
        if (next) { select(next, true); }
      }
    } else {
      let shown = 0;
      palettes.forEach(card => {
        const hit = !query || card.dataset.palette.includes(query);
        card.style.display = hit ? '' : 'none';
        if (hit) { shown += 1; }
      });
      emptyPalettes.style.display = shown === 0 ? 'block' : 'none';
    }
  }

  function applyWallpaper() {
    if (!selected) { return; }
    const path = selected.dataset.path;
    fetch('/set?path=' + encodeURIComponent(path))
      .then(response => response.json())
      .then(result => {
        if (!result.ok) { showToast(result.error || 'Could not set that wallpaper'); return; }
        cells.forEach(cell => {
          const current = cell.dataset.path === path;
          cell.classList.toggle('is-current', current);
          const badge = cell.querySelector('.badge');
          if (current) { badge.textContent = 'current'; }
          else if (cell.classList.contains('in-palette')) { badge.textContent = 'palette'; }
          else { badge.textContent = ''; }
        });
        showToast('Wallpaper set: ' + selected.dataset.name);
      })
      .catch(() => showToast('Could not reach the server'));
  }

  /* What each stage of a switch is called and how far through it is.  The stage
     names are the words the picker script writes into its progress file; the
     percentages are how long the stages actually take, not how many there are -
     re-rendering every generated surface is most of the wait. */
  const stages = {
    starting:  { label: 'Starting',           percent: 5,   note: 'Handing the switch to the palette picker' },
    settings:  { label: 'Writing settings',   percent: 16,  note: 'The palette and the Emacs theme, nothing else in your overrides' },
    rendering: { label: 'Re-rendering',       percent: 55,  note: 'Waybar, Rofi, Mako, WezTerm, Niri and the Emacs bridge' },
    wallpaper: { label: 'Changing wallpaper', percent: 82,  note: 'The new palette brings its own wall' },
    emacs:     { label: 'Re-theming Emacs',   percent: 93,  note: 'The running daemon re-reads the bridge' },
    done:      { label: 'Done',               percent: 100, note: 'Every surface switched' },
    failed:    { label: 'Failed',             percent: 100, note: 'The picker log says why' }
  };

  function drawSwitch(stage, palette, seconds) {
    const info = stages[stage] || stages.starting;
    const ending = stage === 'done' || stage === 'failed';
    switcher.dataset.stage = stage;
    switcher.classList.add('show');
    switcher.classList.toggle('is-done', stage === 'done');
    switcher.classList.toggle('is-failed', stage === 'failed');
    switchStage.textContent = info.label;
    switchNote.textContent = info.note;
    switchName.textContent = palette || '';
    switchFill.style.width = info.percent + '%';
    switchElapsed.textContent = Number(seconds) > 0
      ? Number(seconds).toFixed(ending ? 0 : 1) + 's'
      : '';
  }

  function hideSwitch(delay) {
    clearTimeout(hideSwitch.timer);
    hideSwitch.timer = setTimeout(() => switcher.classList.remove('show'), delay);
  }

  function endSwitch(stage, palette, seconds) {
    clearTimeout(poll);
    poll = null;
    busy = false;
    palettes.forEach(card => card.classList.remove('is-busy'));
    const name = palette || (pending && pending.dataset.palette) || '';
    if (stage === 'done') {
      palettes.forEach(card => card.classList.toggle('is-current', card.dataset.palette === name));
      drawSwitch('done', name, seconds);
      /* The page was painted in the old palette; the honest thing is to say
         so and offer the reload rather than pretend the cards now match. */
      showToast('Palette applied: ' + name + ' — reload to repaint this page');
      hideSwitch(3200);
    } else {
      drawSwitch('failed', name, seconds);
      hideSwitch(6000);
    }
    pending = null;
  }

  /* The server answers /palette at once and runs the picker in a thread, so the
     only way to know how it is doing is to ask.  A switch started from Rofi
     shows up here too: the progress file is the picker's, not the page's. */
  function pollStatus(quiet) {
    /* One chain of polls at a time: the tab can be clicked again while a switch
       is running, and two chains would fight over the same timer. */
    clearTimeout(poll);
    poll = null;
    fetch('/palette-status')
      .then(response => response.json())
      .then(status => {
        const stage = status.stage || 'idle';
        const seconds = Number(status.elapsed || 0);
        if (stage === 'idle') { return; }
        /* Quiet means on arrival: show a switch that is still running, but do
           not re-open the result of one that finished before the window was
           opened. */
        if (quiet && (stage === 'done' || stage === 'failed')) { return; }
        const running = status.running === 'true';
        if (running) { busy = true; }
        drawSwitch(stage, status.palette, seconds);
        if (running) { poll = setTimeout(() => pollStatus(false), 400); }
        else { endSwitch(stage, status.palette, seconds); }
      })
      .catch(() => { poll = setTimeout(() => pollStatus(quiet), 900); });
  }

  function applyPalette(card) {
    if (!card) { return; }
    if (busy) { showToast('A palette switch is already running'); return; }
    const wanted = card.dataset.palette;
    busy = true;
    pending = card;
    palettes.forEach(other => other.classList.toggle('is-busy', other === card));
    drawSwitch('starting', wanted, 0);
    fetch('/palette?name=' + encodeURIComponent(wanted))
      .then(response => response.json())
      .then(result => {
        if (!result.ok) {
          const message = result.error || 'Could not apply that palette';
          if (message.indexOf('already running') !== -1) {
            /* Someone else's switch is in flight - Rofi's, or a click that got
               here first.  Show that one instead of calling this one a
               failure. */
            busy = false;
            pending = null;
            palettes.forEach(other => other.classList.remove('is-busy'));
            showToast(message);
            pollStatus(false);
            return;
          }
          endSwitch('failed', wanted, 0);
          showToast(message);
          return;
        }
        poll = setTimeout(() => pollStatus(false), 300);
      })
      .catch(() => {
        endSwitch('failed', wanted, 0);
        showToast('Could not reach the server');
      });
  }

  cells.forEach(cell => {
    cell.addEventListener('click', () => select(cell, false));
    cell.addEventListener('dblclick', () => { select(cell, false); applyWallpaper(); });
  });

  /* The wheel zooms, because the wallpaper under the cursor is the thing being
     looked at, and the buttons cover the pointer-less case. */
  stage.addEventListener('wheel', event => {
    if (!selected) { return; }
    event.preventDefault();
    setZoom(zoom * Math.exp(-event.deltaY * 0.0016));
  }, { passive: false });

  /* Past the fit there is more picture than pane, so dragging moves it.  A press
     that stays inside the fitted picture is left alone: it is still a click. */
  stage.addEventListener('pointerdown', event => {
    if (zoom <= 1.001) { return; }
    drag = { x: event.clientX, y: event.clientY, panX: panX, panY: panY };
    stage.classList.add('is-panning');
    /* Capture keeps the pan going when the pointer leaves the pane.  A synthetic
       or already-released pointer has no capture to take, and that is not worth
       breaking the drag over. */
    try { stage.setPointerCapture(event.pointerId); } catch (error) { /* ignore */ }
  });
  stage.addEventListener('pointermove', event => {
    if (!drag) { return; }
    panX = drag.panX + (event.clientX - drag.x);
    panY = drag.panY + (event.clientY - drag.y);
    clampPan();
    drawZoom();
  });
  const endDrag = event => {
    if (!drag) { return; }
    drag = null;
    stage.classList.remove('is-panning');
    try {
      if (stage.hasPointerCapture && stage.hasPointerCapture(event.pointerId)) {
        stage.releasePointerCapture(event.pointerId);
      }
    } catch (error) { /* nothing to release */ }
  };
  stage.addEventListener('pointerup', endDrag);
  stage.addEventListener('pointercancel', endDrag);

  zoomIn.addEventListener('click', () => zoomBy(1.25));
  zoomOut.addEventListener('click', () => zoomBy(1 / 1.25));
  zoomFit.addEventListener('click', resetZoom);

  /* Double-click sets the wallpaper - on the wall and on the picture itself,
     because the picture is what you are looking at when you decide. */
  image.addEventListener('dblclick', () => { if (selected) { applyWallpaper(); } });

  palettes.forEach(card => {
    card.addEventListener('click', () => applyPalette(card));
  });

  tabs.forEach(tab => tab.addEventListener('click', () => setMode(tab.dataset.pane)));
  filter.addEventListener('input', applyFilter);
  document.getElementById('apply').addEventListener('click', applyWallpaper);
  document.getElementById('close').addEventListener('click', () => window.close());

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (filter.value) { filter.value = ''; applyFilter(); }
      else { window.close(); }
      return;
    }
    if (event.key === 'Enter' && document.activeElement !== filter) {
      event.preventDefault();
      if (mode === 'wallpapers') { applyWallpaper(); }
      return;
    }
    if (event.key === '/' && document.activeElement !== filter) {
      event.preventDefault();
      filter.focus();
      return;
    }
    if (mode !== 'wallpapers') { return; }
    /* Everything below is a shortcut, so the filter keeps its keystrokes. */
    if (document.activeElement === filter) { return; }
    if (event.key === '+' || event.key === '=') {
      event.preventDefault();
      zoomBy(1.25);
      return;
    }
    if (event.key === '-' || event.key === '_') {
      event.preventDefault();
      zoomBy(1 / 1.25);
      return;
    }
    if (event.key === '0') {
      event.preventDefault();
      resetZoom();
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight' ||
        event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
      const list = visible();
      if (!list.length) { return; }
      event.preventDefault();
      const index = list.indexOf(selected);
      const step = (event.key === 'ArrowDown' || event.key === 'ArrowRight') ? 1 : -1;
      select(list[(index + step + list.length) % list.length], true);
    }
  });

  window.addEventListener('pagehide', () => navigator.sendBeacon('/close'));

  const first = visible()[0];
  if (first) { select(first, false); }
  if (location.hash === '#palettes') { setMode('palettes'); }
  /* A palette can be switched from the Rofi picker too.  Asking once on arrival
     means a page opened during someone else's switch shows the same progress. */
  pollStatus(true);")

(define (gallery-unresolved-tokens document)
  "Return the @code{@token@}s left in @var{document}."
  (template-leftovers document))

(define (gallery-cell entry)
  "Render one wallpaper @var{entry} as a selectable cell of the wall.

The cell is a @code{div} rather than a @code{button}: a button lays its children
out in its own anonymous box, which squeezes the image the cell is built around.
The role and the tab stop keep it reachable for anything that expects a button.

The thumbnail URL is written with a plain @code{&}: the writer escapes attribute
values, and escaping it here as well would send @code{&amp;amp;} to the server."
  (let ((path (assoc-ref entry 'path)))
    `(div (@ (class ,(string-append "cell"
                                    (if (assoc-ref entry 'palette?) " in-palette" "")
                                    (if (assoc-ref entry 'current?) " is-current" "")))
              (role "button")
              (tabindex "0")
              (data-path ,path)
              (data-name ,(assoc-ref entry 'name))
              (data-folder ,(assoc-ref entry 'folder)))
          (div (@ (class "frame"))
               (img (@ (loading "lazy")
                       (src ,(format #f "/thumb?w=520&path=~a" (uri-encode path)))
                       (alt ""))))
          (span (@ (class "caption")) ,(assoc-ref entry 'name))
          (span (@ (class "badge"))
                ,(cond
                   ((assoc-ref entry 'current?) "current")
                   ((assoc-ref entry 'palette?) "palette")
                   (else ""))))))

(define (palette-card palette current?)
  "Render one @var{palette} as a card painted in that palette's own colours.

The card carries everything needed to judge a theme without applying it: the
background it would give you, the accent, the two text colours as a bar, a
sentence set in it, and a keycap - because a keycap is what this desktop is
mostly made of.  Its colours are handed to CSS as custom properties, so one rule
paints forty cards."
  (let ((background (get-color palette 'background))
        (background-l (get-color palette 'background-l))
        (text (get-color palette 'text))
        (text-l (get-color palette 'text-l))
        (primary (get-color palette 'primary))
        (dark? (is-dark-palette palette)))
    `(button (@ (class ,(string-append "palette-card"
                                       (if current? " is-current" "")))
                (type "button")
                (data-palette ,(symbol->string palette))
                (style ,(format #f "--card-bg: ~a; --card-text: ~a; --card-text-l: ~a; --card-primary: ~a; --card-on-primary: ~a; --card-edge: ~a"
                                background text text-l primary background
                                (hex-to-rgba text #:alpha 0.16))))
             (span (@ (class "head"))
                   (span (@ (class "name")) ,(symbol->string palette))
                   (span (@ (class "mark"))
                         ,(cond (current? "current")
                                (dark? "dark")
                                (else "light"))))
             (span (@ (class "sample"))
                   "The quick brown fox jumps over the lazy dog. "
                   (kbd "s-q"))
             (span (@ (class "bars"))
                   (i (@ (style ,(format #f "background: ~a" primary))))
                   (i (@ (style ,(format #f "background: ~a" text))))
                   (i (@ (style ,(format #f "background: ~a" background-l))))
                   (i (@ (style ,(format #f "background: ~a" text-l))))))))

(define* (gallery-html entries #:key (palette (heks-linux-palette)))
  "Render the gallery: one page, two tabs, painted from @var{palette}.

The wallpapers and the palettes are two views of the same question - how should
this desktop look - so they are one document with a sidebar, exactly like the
keyboard reference.  The second tab is reachable as @code{#palettes}, which is
what the palette launcher opens."
  (let* ((wall entries)
         (palettes (palette-names))
         (in-palette (length (filter (lambda (entry)
                                       (assoc-ref entry 'palette?))
                                     wall))))
    (glass-document
     "Heks Linux"
     `((div (@ (class "app"))
            (aside ,glass-brand
                   (p (@ (class "stat"))
                      (b ,(number->string (length wall))) " wallpapers · "
                      (b ,(number->string (length palettes))) " palettes")
                   (nav (@ (class "tabs"))
                        (button (@ (class "tab") (type "button")
                                   (data-pane "wallpapers") (aria-selected "true"))
                                "Wallpapers"
                                (span (@ (class "count"))
                                      ,(number->string (length wall))))
                        (button (@ (class "tab") (type "button")
                                   (data-pane "palettes") (aria-selected "false"))
                                "Palettes"
                                (span (@ (class "count"))
                                      ,(number->string (length palettes)))))
                   (div (@ (class "sidebar-foot"))
                        (b ,(number->string in-palette)) " in the palette set" (br)
                        "type filter" (br)
                        "esc close"))
            (main (div (@ (class "toolbar"))
                       (input (@ (class "search") (id "filter") (type "search")
                                 (placeholder "Filter wallpapers by name or folder…")
                                 (autocomplete "off") (spellcheck "false")
                                 (autofocus "")))
                       (span (@ (class "hint"))
                             "palette · " ,(symbol->string palette)))
                  (div (@ (class "pane active") (id "pane-wallpapers"))
                       (div (@ (class "split"))
                            (div (@ (id "wall"))
                                 ,@(map gallery-cell wall)
                                 (p (@ (id "empty")) "Nothing matches that filter."))
                            (aside (@ (id "preview"))
                                   (div (@ (class "stage"))
                                        (img (@ (id "preview-image") (alt "")
                                                (src "")))
                                        (div (@ (class "zoom"))
                                             (button (@ (class "zoom-out")
                                                         (type "button")
                                                         (title "Zoom out")
                                                         (aria-label "Zoom out"))
                                                     "−")
                                             (button (@ (class "zoom-fit level")
                                                         (type "button")
                                                         (title "Show the whole wallpaper")
                                                         (aria-label "Fit the whole wallpaper"))
                                                     "Fit")
                                             (button (@ (class "zoom-in")
                                                         (type "button")
                                                         (title "Zoom in")
                                                         (aria-label "Zoom in"))
                                                     "+")))
                                   (h2 (@ (id "preview-name")) "Pick a wallpaper")
                                   (p (@ (id "preview-folder")))
                                   (div (@ (class "policy"))
                                        (button (@ (id "apply") (type "button"))
                                                "Set as wallpaper")
                                        (button (@ (id "close") (type "button")
                                                   (class "ghost"))
                                                "Close"))
                                   (p (@ (class "hint"))
                                      "Double-click a wallpaper - here or on the wall - to set it"))))
                  (div (@ (class "pane") (id "pane-palettes"))
                       (div (@ (id "palettes"))
                            ,@(map (lambda (name)
                                     (palette-card name (eq? name palette)))
                                   palettes)
                            (p (@ (id "empty-palettes"))
                               "Nothing matches that filter.")))
                  (footer (span (kbd "/") " filter")
                          (span (kbd "Enter") " apply")
                          (span (kbd "+") (kbd "-") " zoom")
                          (span (kbd "0") " fit")
                          (span (kbd "Esc") " close")
                          (span (@ (class "grow")))
                          ,(glass-credits)
                          (span (@ (class "swatches"))
                                (span (@ (class "swatch"))
                                      (i (@ (style ,(format #f "background: ~a"
                                                            (get-color palette 'primary)))))
                                      (span "primary"))))))
       (div (@ (id "toast")))
       (div (@ (id "switch") (role "status") (aria-live "polite") (data-stage "idle"))
            (div (@ (class "line"))
                 (span (@ (class "stage")) "Starting")
                 (span (@ (class "name")))
                 (span (@ (class "elapsed"))))
            (div (@ (class "bar")) (i (@ (class "fill"))))
            (p (@ (class "note"))))
       (script (*RAW* ,gallery-script)))
     #:css (fill-template gallery-page-css
                           `(("@cell@" . ,(hex-to-rgba (get-color palette 'background-l)
                                                       #:alpha 0.5))))
     #:palette palette)))

;; --- The server ---

(define (gallery-query request)
  "Return the query string of @var{request} as an association list."
  (define (decode pair)
    (match (string-split pair #\=)
      ((key value) (cons (uri-decode key) (uri-decode value)))
      ((key) (cons (uri-decode key) ""))
      (_ (cons "" ""))))
  (let ((query (uri-query (request-uri request))))
    (if (or (not query) (string-null? query))
        '()
        (map decode (string-split query #\&)))))

(define (gallery-safe-path candidate)
  "Return @var{candidate} when it is an image inside the collection, else #f.

The page can ask this server for a file; it must not be able to ask for one
outside the wallpaper collection, and it must not be able to ask for anything
that is not a picture."
  (let ((root (wallpaper-catalog-dir)))
    (and (string? candidate)
         (not (string-null? candidate))
         (string-prefix? (string-append root "/") candidate)
         (not (string-contains candidate ".."))
         (gallery-image-path? candidate)
         (file-exists? candidate)
         candidate)))

(define (gallery-respond type body)
  "Return an HTTP response of @var{type} carrying @var{body}.

Every response closes its connection: the handler runs in a thread that owns one
connection, so a client that tries to reuse it would wait for a reader that is
not there.  The page opens a fresh connection per thumbnail, which is exactly
what the threaded loop is shaped for."
  (values `((content-type . (,type))
            (connection . (close)))
          (if (bytevector? body) body (string->utf8 body))))

(define (gallery-json-escape text)
  "Escape @var{text} for use inside a JSON string.

The server answers with flat objects of strings, so this is the whole of the
encoding it needs; using the HTML escaper here would have been wrong twice over
(a quote is legal in HTML text and illegal in JSON) - which is what the first
version of this function did."
  (with-output-to-string
      (lambda ()
        (string-for-each (lambda (ch)
                           (display (case ch
                                      ((#\") "\\\"")
                                      ((#\\) "\\\\")
                                      ((#\newline) "\\n")
                                      ((#\return) "\\r")
                                      ((#\tab) "\\t")
                                      (else (if (char<? ch #\space)
                                                (format #f "\\u~4,'0x"
                                                        (char->integer ch))
                                                (string ch))))))
                         text))))

(define (gallery-json ok payload)
  "Return a JSON response describing one gallery action.

@var{ok} is the outcome; @var{payload} is the association list of extra fields,
rendered as a flat object because that is all this page ever reads."
  (gallery-respond
   'application/json
   (format #f "{\"ok\":~a~a}"
           (if ok "true" "false")
           (string-join (map (lambda (pair)
                               (format #f ",\"~a\":\"~a\""
                                       (car pair)
                                       (gallery-json-escape (cdr pair))))
                             payload)
                        ""))))

(define (gallery-progress-read)
  "Return the palette switch in progress as an association list, or the empty
list when nothing has been written.

The picker writes one line - stage, epoch, palette - every time it moves on, so
the age of the switch is read from the file rather than remembered: the page can
open halfway through a switch that Rofi started and still show the truth."
  (let ((file (gallery-progress-file)))
    (if (not (file-exists? file))
        '()
        (catch #t
          (lambda ()
            (call-with-input-file file
              (lambda (port)
                (let ((line (get-line port)))
                  (if (eof-object? line)
                      '()
                      (match (string-split (string-trim-both line) #\space)
                        ((stage epoch palette)
                         `(("stage" . ,stage)
                           ("epoch" . ,epoch)
                           ("palette" . ,palette)))
                        (_ '())))))))
          (lambda _ '())))))

(define (gallery-progress-write! stage palette)
  "Seed the progress file with @var{stage} for @var{palette}.

The picker writes the same file as it works; this only fills the gap between the
click and the script's first line, where the page would otherwise still be
showing yesterday's last stage."
  (catch #t
    (lambda ()
      (with-output-to-file (gallery-progress-file)
        (lambda ()
          (format #t "~a ~a ~a~%" stage (current-time) palette))))
    (lambda _ #f)))

(define gallery-palette-lock
  (make-mutex))

;; True while this server has a switch running.  A plain variable, not a
;; parameter: parameters hold a value per thread, and every request here is
;; answered in its own thread, so a flag set in one would be invisible to the
;; next - which is the whole of what this flag is for.
(define gallery-palette-busy? #f)

(define (gallery-palette-running?)
  "Whether this server is running a palette switch right now."
  (with-mutex gallery-palette-lock
               gallery-palette-busy?))

(define (gallery-palette-status)
  "Return the state of the current palette switch as an association list.

@code{running} is true while a switch is moving: either this server is running
one, or the file is young enough that the picker started from Rofi is still
working.  The age limit is what stops a stale file from a previous session from
being reported as a switch that never ends."
  (let* ((info (gallery-progress-read))
         (raw (or (assoc-ref info "stage") "idle"))
         (epoch (and=> (assoc-ref info "epoch") string->number))
         (elapsed (if epoch (max 0 (- (current-time) epoch)) 0))
         (moving (and (member raw gallery-switch-stages) #t))
         (running (or (gallery-palette-running?)
                      (and moving (< elapsed 120))))
         ;; A stage nobody is working on is not a stage: a file left behind by a
         ;; picker that was killed mid-render would otherwise be reported as a
         ;; switch that never ends.
         (stage (if (or running (member raw '("done" "failed"))) raw "idle")))
    `(("stage" . ,stage)
      ("palette" . ,(or (assoc-ref info "palette") ""))
      ("elapsed" . ,(number->string elapsed))
      ("running" . ,(if running "true" "false")))))

(define (gallery-run-palette script name)
  "Apply @var{name} by running the palette picker @var{script} in apply mode.

Returns its exit status.  ROFI_RETV=1 is the script's documented \"an entry was
chosen\" branch, so the page and the Rofi picker share one implementation of
what applying a palette means."
  (catch #t
    (lambda ()
      (system* "env" "ROFI_RETV=1" script name))
    (lambda _ #f)))

(define (gallery-palette-apply script name)
  "Run the picker @var{script} for @var{name}, then clear the busy flag.

This runs in its own thread: a switch re-renders every generated dotfile, which
takes seconds, and a page that waits for that is a page that looks broken."
  (dynamic-wind
    (lambda () #t)
    (lambda () (gallery-run-palette script name))
    (lambda ()
      (with-mutex gallery-palette-lock
        (set! gallery-palette-busy? #f)
        ;; A switch that ended without saying how - the picker was killed, or
        ;; could not run at all - would otherwise leave its last stage sitting in
        ;; the file, looking busy for two minutes.
        (let ((stage (assoc-ref (gallery-progress-read) "stage")))
          (when (member stage gallery-switch-stages)
            (gallery-progress-write!
             "failed"
             (or (assoc-ref (gallery-progress-read) "palette") ""))))))))

(define (gallery-switch-in-flight?)
  "Whether a palette switch is running, whoever started it.

The flag only knows about switches this server runs; a picker started from Rofi
writes the same progress file, so the age of that file is the other half of the
answer."
  (or (gallery-palette-running?)
      (string=? (or (assoc-ref (gallery-palette-status) "running") "") "true")))

(define (gallery-start-palette script name)
  "Start applying @var{name} in a background thread and return at once.

Returns @code{#f} when a switch is already running: two picker scripts rewriting
the same settings file at the same time is a corruption waiting to happen - and
two `maak install-theme' runs interleaved is worse - so the page can say so
instead of queueing work it cannot see."
  (with-mutex gallery-palette-lock
    (if gallery-palette-busy?
        #f
        (begin
          (set! gallery-palette-busy? #t)
          (gallery-progress-write! "starting" name)
          (call-with-new-thread
           (lambda () (gallery-palette-apply script name)))
          #t))))

(define (gallery-run-engine . args)
  "Run the wallpaper engine with @var{args} and return its exit status."
  (catch #t
    (lambda ()
      (apply system* (format #f "~a/~a"
                             (wallpaper-script-dir)
                             (wallpaper-script-filename))
             args))
    (lambda _ #f)))

(define (gallery-ready-file)
  "Return the file that records the process id of the running server.

The launcher cannot simply ask the socket whether the gallery is up: the bash it
finds on the bar's @env{PATH} is Guix's @code{bash-minimal}, built without net
redirections, and a line in a log file outlives the server that wrote it.  A pid
the kernel can still be asked about is the honest answer, and it is the same
answer whoever started the server."
  (format #f "~a/heks-linux-gallery-~a.pid"
          (or (getenv "XDG_RUNTIME_DIR") "/tmp")
          (gallery-port)))

(define (gallery-announce-server!)
  "Record this process as the server answering on the gallery port."
  (catch #t
    (lambda ()
      (with-output-to-file (gallery-ready-file)
        (lambda () (format #t "~a~%" (getpid)))))
    (lambda _ #f)))

(define (gallery-retire-server!)
  "Withdraw the record of this process being the server, if it is ours.

Called on every way out of the serve loop, so a window that is closed does not
leave a pid behind that a later launcher would take for a running server."
  (catch #t
    (lambda ()
      (let ((file (gallery-ready-file)))
        (when (and (file-exists? file)
                   (string=? (string-trim-both
                              (call-with-input-file file get-string-all))
                             (number->string (getpid))))
          (delete-file file))))
    (lambda _ #f)))

(define (gallery-handler request)
  "Answer one gallery request.

Every request is a read except @code{/set} and @code{/action}, which are the
only ways a page can change the wallpaper, and both go through the engine - the
same program the timer and the keybindings use."
  (let* ((path (uri-path (request-uri request)))
         (query (gallery-query request)))
    (cond
      ((string=? path "/")
       (gallery-respond 'text/html
                        (gallery-html (gallery-images))))
      ((string=? path "/thumb")
       (let ((file (gallery-safe-path (assoc-ref query "path")))
             (width (or (string->number (or (assoc-ref query "w") "")) 520)))
         (if (and file (gallery-thumbnail file (min width 3200)))
             (gallery-respond 'image/jpeg
                              (call-with-input-file
                                  (gallery-thumbnail file (min width 3200))
                                get-bytevector-all))
             (gallery-respond 'text/plain "no thumbnail\n"))))
      ((string=? path "/preview")
       (let ((file (gallery-safe-path (assoc-ref query "path")))
             (width (gallery-preview-width)))
         (if (and file (gallery-thumbnail file width))
             (gallery-respond 'image/jpeg
                              (call-with-input-file (gallery-thumbnail file width)
                                get-bytevector-all))
             (gallery-respond 'text/plain "no preview\n"))))
      ((string=? path "/set")
       (let ((file (gallery-safe-path (assoc-ref query "path"))))
         (if (not file)
             (gallery-json #f '(("error" . "not a wallpaper in the collection")))
             (if (zero? (or (gallery-run-engine "set" file) 1))
                 (gallery-json #t `(("current" . ,(basename file))))
                 (gallery-json #f '(("error" . "the engine refused")))))))
      ((string=? path "/action")
       (let ((name (assoc-ref query "name")))
         (if (member name '("random" "next" "prev"))
             (if (zero? (or (gallery-run-engine name) 1))
                 (gallery-json #t `(("current" . ,name)))
                 (gallery-json #f '(("error" . "the engine refused"))))
             (gallery-json #f '(("error" . "unknown action"))))))
      ((string=? path "/palette")
       ;; Applying a palette goes through the picker script's own "apply this
       ;; palette" entry point (ROFI_RETV=1, the palette as the argument), which
       ;; already rewrites the two settings forms, runs the one-process
       ;; re-render and tells the running Emacs.  Reimplementing that here would
       ;; be a second copy of the most delicate code in the project.
       ;;
       ;; It is started in a thread and answered at once: the alternative is a
       ;; request that hangs for however long `maak install-theme' takes, which
       ;; the browser shows as a spinner and the user reads as a freeze.
       (let ((wanted (assoc-ref query "name"))
             (script (format #f "~a/~a"
                             (rofi-theme-menu-dir)
                             (rofi-theme-menu-filename))))
         (cond
           ((not (member (string->symbol (or wanted "")) (palette-names)))
            (gallery-json #f '(("error" . "unknown palette"))))
           ((not (file-exists? script))
            (gallery-json #f '(("error" . "the palette picker is not installed"))))
           ((gallery-switch-in-flight?)
            (gallery-json #f '(("error" . "a palette switch is already running"))))
           ((gallery-start-palette script wanted)
            (gallery-json #t `(("current" . ,wanted))))
           (else
            (gallery-json #f '(("error" . "a palette switch is already running")))))))
      ((string=? path "/palette-status")
       (gallery-json #t (gallery-palette-status)))
      ((string=? path "/close")
       ;; primitive-exit, not exit: a request is answered in its own thread,
       ;; and `exit' would end that thread and leave the process serving.
       (gallery-retire-server!)
       (primitive-exit 0))
      (else
       (gallery-respond 'text/plain "not found\n")))))

(define* (run-gallery-server #:key (port (gallery-port)))
  "Serve the gallery on @var{port}, on the loopback interface only.

One thread per connection, because the page asks for a dozen thumbnails at once
and each one is an ImageMagick run: serving them in sequence would make the
first look at the collection take ten seconds.  After the first request they are
cached, so this only buys the first impression - which is the whole impression.

The server stops after @code{gallery-idle-seconds} without a request, so a
window that is closed - or a browser that dies - does not leave a process
behind.  The page asks for @code{/close} when it unloads, which is the usual way
out; the timeout is the backstop."
  (let* ((impl (lookup-server-impl 'http))
         (server (open-server impl (list #:host "127.0.0.1" #:port port)))
         (last (make-parameter (current-time)))
         (handler (lambda (request body)
                    (last (current-time))
                    (gallery-handler request))))
    (call-with-new-thread
     (lambda ()
       (let loop ()
         (sleep 10)
         (when (> (- (current-time) (last)) (gallery-idle-seconds))
           (log-info s "Gallery idle, shutting down")
           ;; primitive-exit for the same reason as /close: `exit' from this
           ;; thread would only end the watchdog.
           (gallery-retire-server!)
           (primitive-exit 0))
         (loop))))
    (log-info s "Serving the wallpaper gallery on port ~a" port)
    ;; Announced after the socket is bound and before the first request: this is
    ;; what a launcher waits for, and it is the only reliable way to be told the
    ;; server is up from a shell with no socket tool of its own.
    (gallery-announce-server!)
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (let loop ()
          (call-with-values (lambda () (read-client impl server))
            (lambda (client request body)
              (when client
                (call-with-new-thread
                 (lambda ()
                   (call-with-values
                       (lambda ()
                         (handle-request handler request body '()))
                     (lambda (response response-body state)
                       (write-client impl server client response response-body))))))
              (loop)))))
      (lambda () (gallery-retire-server!)))))

(define (main)
  "Entry point for the launcher script: serve the gallery until it is closed."
  (format #t "http://127.0.0.1:~a/\n" (gallery-port))
  (run-gallery-server))

;; --- Installation ---

(define* (mk-gallery-launcher-cmd #:key (port (gallery-port))
                                  (anchor "")
                                  (fallback "")
                                  (environment (or (getenv "GUIX_ENVIRONMENT")
                                                   "")))
  "Render the launcher that opens the gallery in a browser app window.

@var{port} is where the server listens, @var{anchor} is the tab the window opens
on and @var{fallback} is a command line to run instead when the page cannot be
served at all - empty for a page with no equivalent, which then says why it did
not open instead of quietly opening something older and worse.  The fallback is
word-split, because it is a line this module generates rather than something a
user types.

@var{environment} is the store profile the server is started from, captured when
the launcher was generated: the server needs the project's libraries, and asking
Guix to work out the manifest on every click costs seconds before a window can
appear.  When the profile has been collected, the launcher falls back to
@code{guix shell} and is merely slow rather than broken.

The server is left to its own idle timeout instead of being tied to the browser
process: a browser that already has a window open answers the launch by opening
another one and exiting immediately, and killing the server at that moment would
close the gallery the user is looking at."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux wallpaper gallery ======
#
# auto-generated file, DO NOT EDIT!
#
# Opens the wallpaper collection as a page with a large preview, served from a
# socket on this machine.

set -u

PORT=~a
URL=\"http://127.0.0.1:$PORT/~a\"
CLONE=\"~a\"
SRC=\"$CLONE/src\"
FALLBACK=\"~a\"
SERVER_ENV=\"~a\"
READY=\"${XDG_RUNTIME_DIR:-/tmp}/heks-linux-gallery-$PORT.pid\"
LOG=\"${TMPDIR:-/tmp}/heks-gallery.log\"

port_open() {
    # Whether the server is up.  The kernel is asked first and its answer is
    # final: a pid file can outlive the server that wrote it, and a killed
    # process lingers as a zombie that still answers kill -0.
    #
    # Note what is *not* used here: /dev/tcp.  The first bash the bar finds on
    # @env{PATH} is Guix's bash-minimal, built without net redirections, so a
    # probe through it fails while the server is running perfectly well - which
    # is how a click on the wallpaper button came to do nothing at all.
    if command -v ss >/dev/null 2>&1; then
        [ -n \"$(ss -ltnH \"sport = :$PORT\" 2>/dev/null)\" ] && return 0
        return 1
    fi
    # With no ss to ask, believe the pid the server wrote - while the process
    # behind it is really there.  A zombie's cmdline is empty, so a killed
    # server cannot pass for a running one.
    local pid
    [ -f \"$READY\" ] || return 1
    read -r pid < \"$READY\" || return 1
    [ -n \"$pid\" ] && [ -s \"/proc/$pid/cmdline\" ] && kill -0 \"$pid\" 2>/dev/null
}

browser_bin() {
    local candidate
    for candidate in google-chrome chromium chromium-browser brave-browser; do
        if command -v \"$candidate\" >/dev/null 2>&1; then
            printf '%s' \"$candidate\"
            return 0
        fi
    done
    return 1
}

# Out of ways to open the page.  A fallback is run if this launcher has one;
# otherwise the failure is announced, because silence here reads as a dead click.
# The notification is sent from a background subshell so a notification daemon
# that is slow, absent or waiting on a request cannot hold the launcher open.
give_up() {
    if [ -n \"$FALLBACK\" ]; then
        exec $FALLBACK
    fi
    if command -v fyi >/dev/null 2>&1; then
        ( fyi -u critical -a \"Heks Linux\" \"The gallery did not open\" \"$1\" \\
              >/dev/null 2>&1 & )
    fi
    printf 'heks-linux gallery: %s\\n' \"$1\" >&2
    exit 1
}

# The page is rendered by the project's own modules, so the server needs the
# manifest shell: a bare guile has the interpreter and not the libraries.  The
# store profile captured at install time is tried first - sourcing its profile
# is what puts those libraries on the load path - and guix second, for when the
# profile has been collected.
start_server() {
    cd \"$CLONE\" || return 1
    if [ -n \"$SERVER_ENV\" ] && [ -x \"$SERVER_ENV/bin/guile\" ]; then
        ( set +u
          GUIX_PROFILE=$SERVER_ENV
          . \"$GUIX_PROFILE/etc/profile\"
          exec \"$SERVER_ENV/bin/guile\" -L \"$SRC\" \\
              -c '((@ (heks-linux gallery) main))' )
    fi
    exec guix shell -m manifest.scm -- guile -L \"$SRC\" \\
        -c '((@ (heks-linux gallery) main))'
}

BROWSER=$(browser_bin) || give_up \"no browser to open it in.\"
[ -d \"$SRC\" ] || give_up \"the checkout at $CLONE has no src directory.\"
if [ -z \"$SERVER_ENV\" ] || [ ! -x \"$SERVER_ENV/bin/guile\" ]; then
    command -v guix >/dev/null 2>&1 \\
        || give_up \"the server needs guix and there is no profile to run it from.\"
fi

# One server per session: a second launch reuses the first one.
if ! port_open; then
    ( start_server >\"$LOG\" 2>&1 & )
    # Thirty seconds, counted in shell arithmetic rather than by forking seq: on
    # a machine whose bytecode cache has just been wiped the first launch
    # compiles every module the page needs before it can bind.
    for ((attempt = 0; attempt < 300; attempt++)); do
        port_open && break
        sleep 0.1
    done
fi
port_open || give_up \"the server did not answer; see $LOG\"

exec \"$BROWSER\" --app=\"$URL\" --window-size=1320,900
"
          port
          anchor
          (gallery-clone-dir-absolute)
          fallback
          environment))

(define (gallery-clone-dir-absolute)
  "Expand a leading @file{~/} in the configured clone dir."
  (let ((home (or (getenv "HOME") "/tmp"))
        (dir (heks-linux-clone-dir)))
    (if (string-prefix? "~/" dir)
        (string-append home (substring dir 1))
        dir)))

(define* (install-gallery-config)
  "Write the two launchers: the wallpaper gallery and the palette chooser.

They are the same page on two tabs, so they share one server.  Local overrides
are read from @code{$XDG_CONFIG_HOME/heks-linux/gallery-settings.scm} first, so a
machine can move the port or point the launcher at a different checkout.
Nothing has to be restarted: a launcher starts the server when it needs one."
  (log-info s "Installing the wallpaper gallery")
  (load-local-overrides '(heks-linux gallery)
                        'gallery-settings)
  (install-config-file! #:name (gallery-launcher-filename)
                        #:dir (gallery-launcher-dir)
                        #:contents (mk-gallery-launcher-cmd)
                        #:perms 493)
  ;; The palette tab keeps a fallback - ~rofi -show theme~ opens the same picker
  ;; in Rofi, which is a script mode the generated Rofi config already declares.
  ;; The wallpaper launcher has none: the Rofi wall is gone, and a page that
  ;; cannot open should say so rather than open something worse.
  (install-config-file! #:name (palette-launcher-filename)
                        #:dir (gallery-launcher-dir)
                        #:contents (mk-gallery-launcher-cmd
                                    #:anchor "#palettes"
                                    #:fallback "rofi -show theme")
                        #:perms 493)
  (log-success s "Installed the wallpaper gallery"))
