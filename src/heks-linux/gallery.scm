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
  ".tabs { display: flex; flex-direction: column; gap: 3px; margin-bottom: 4px; }
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
  font-family: @mono@, ui-monospace, monospace;
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
#filter {
  flex: 1;
  padding: 10px 14px 10px 34px;
  border: 1px solid @hairline@;
  border-radius: 11px;
  background-color: @field@;
  background-image: @magnifier@;
  background-repeat: no-repeat;
  background-position: 12px center;
  background-size: 13px 13px;
  color: @text@;
  font: inherit;
  font-size: 13px;
  outline: none;
  transition: border-color 0.16s ease, box-shadow 0.16s ease;
}
#filter::placeholder { color: @text-l@; opacity: 0.75; }
#filter:focus { border-color: @primary@; box-shadow: 0 0 0 3px @primary-ghost@; }
.toolbar .hint {
  font-family: @mono@, ui-monospace, monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  color: @text-l@;
  opacity: 0.7;
  white-space: nowrap;
}

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
  flex: 0 0 40%;
  display: flex;
  flex-direction: column;
  gap: 11px;
  padding: 16px 18px 18px;
  border-left: 1px solid @hairline@;
  min-width: 0;
}
#preview img {
  flex: 1;
  min-height: 0;
  width: 100%;
  border-radius: 12px;
  object-fit: contain;
  background: @background@;
  border: 1px solid @hairline-soft@;
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
  let selected = null;
  let mode = 'wallpapers';

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
    if (scroll) { cell.scrollIntoView({ block: 'nearest' }); }
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
    if (next === 'palettes') { history.replaceState(null, '', '#palettes'); }
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

  function applyPalette(card) {
    if (!card) { return; }
    const wanted = card.dataset.palette;
    showToast('Applying ' + wanted + '…');
    fetch('/palette?name=' + encodeURIComponent(wanted))
      .then(response => response.json())
      .then(result => {
        if (!result.ok) { showToast(result.error || 'Could not apply that palette'); return; }
        palettes.forEach(other => other.classList.toggle('is-current', other === card));
        /* The page was painted in the old palette; the honest thing is to say
           so and offer the reload rather than pretend the cards now match. */
        showToast('Palette applied: ' + wanted + ' — reload to repaint this page');
      })
      .catch(() => showToast('Could not reach the server'));
  }

  cells.forEach(cell => {
    cell.addEventListener('click', () => select(cell, false));
    cell.addEventListener('dblclick', () => { select(cell, false); applyWallpaper(); });
  });

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
  if (location.hash === '#palettes') { setMode('palettes'); }")

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

(define (gallery-magnifier palette)
  "Return a magnifier glyph as a data URI, inked in @var{palette}'s text colour."
  (format #f
          "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' stroke='~a' stroke-width='1.6' stroke-linecap='round'><circle cx='6.6' cy='6.6' r='4.6'/><path d='M10.2 10.2 L14 14'/></svg>\")"
          (string-replace-substring (get-color palette 'text-l)
                                    "#" "%23")))

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
     "Heks Linux · Wallpapers and palettes"
     `((div (@ (class "app"))
            (aside ,glass-brand
                   (h1 "Appearance")
                   (p (@ (class "stat"))
                      (b ,(number->string (length wall))) " wallpapers · "
                      (b ,(number->string (length palettes))) " palettes")
                   (div (@ (class "tabs"))
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
                       (input (@ (id "filter") (type "search")
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
                                   (img (@ (id "preview-image") (alt "") (src "")))
                                   (h2 (@ (id "preview-name")) "Pick a wallpaper")
                                   (p (@ (id "preview-folder")))
                                   (div (@ (class "policy"))
                                        (button (@ (id "apply") (type "button"))
                                                "Set as wallpaper")
                                        (button (@ (id "close") (type "button")
                                                   (class "ghost"))
                                                "Close")))))
                  (div (@ (class "pane") (id "pane-palettes"))
                       (div (@ (id "palettes"))
                            ,@(map (lambda (name)
                                     (palette-card name (eq? name palette)))
                                   palettes)
                            (p (@ (id "empty-palettes"))
                               "Nothing matches that filter.")))
                  (footer (span (kbd "/") " filter")
                          (span (kbd "Enter") " apply")
                          (span (kbd "Esc") " close")
                          (span (@ (class "grow")))
                          ,(glass-credits)
                          (span (@ (class "swatches"))
                                (span (@ (class "swatch"))
                                      (i (@ (style ,(format #f "background: ~a"
                                                            (get-color palette 'primary)))))
                                      (span "primary"))))))
       (div (@ (id "toast")))
       (script (*RAW* ,gallery-script)))
     #:css (fill-template gallery-page-css
                           `(("@cell@" . ,(hex-to-rgba (get-color palette 'background-l)
                                                       #:alpha 0.5))
                             ("@magnifier@" . ,(gallery-magnifier palette))))
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

(define (gallery-run-palette script name)
  "Apply @var{name} by running the palette picker @var{script} in apply mode.

Returns its exit status.  ROFI_RETV=1 is the script's documented \"an entry was
chosen\" branch, so the page and the Rofi picker share one implementation of
what applying a palette means."
  (catch #t
    (lambda ()
      (system* "env" "ROFI_RETV=1" script name))
    (lambda _ #f)))

(define (gallery-run-engine . args)
  "Run the wallpaper engine with @var{args} and return its exit status."
  (catch #t
    (lambda ()
      (apply system* (format #f "~a/~a"
                             (wallpaper-script-dir)
                             (wallpaper-script-filename))
             args))
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
       (let ((file (gallery-safe-path (assoc-ref query "path"))))
         (if (and file (gallery-thumbnail file 1600))
             (gallery-respond 'image/jpeg
                              (call-with-input-file (gallery-thumbnail file 1600)
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
       (let ((wanted (assoc-ref query "name"))
             (script (format #f "~a/~a"
                             (rofi-theme-menu-dir)
                             (rofi-theme-menu-filename))))
         (cond
           ((not (member (string->symbol (or wanted "")) (palette-names)))
            (gallery-json #f '(("error" . "unknown palette"))))
           ((not (file-exists? script))
            (gallery-json #f '(("error" . "the palette picker is not installed"))))
           ((eqv? 0 (gallery-run-palette script wanted))
            (gallery-json #t `(("current" . ,wanted))))
           (else
            (gallery-json #f '(("error" . "the picker refused")))))))
      ((string=? path "/close")
       ;; primitive-exit, not exit: a request is answered in its own thread,
       ;; and `exit' would end that thread and leave the process serving.
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
           (primitive-exit 0))
         (loop))))
    (log-info s "Serving the wallpaper gallery on port ~a" port)
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
          (loop))))))

(define (main)
  "Entry point for the launcher script: serve the gallery until it is closed."
  (format #t "http://127.0.0.1:~a/\n" (gallery-port))
  (run-gallery-server))

;; --- Installation ---

(define* (mk-gallery-launcher-cmd #:key (port (gallery-port))
                                  (anchor "")
                                  (fallback (format #f "~a/~a"
                                                    (wallpaper-script-dir)
                                                    (wallpaper-chooser-filename))))
  "Render the launcher that opens the gallery in a browser app window.

@var{port} is where the server listens and @var{fallback} is the Rofi wall to
fall back to.  Every way the gallery can fail - no Guix, no browser, no checkout
to load the modules from - ends in that fallback rather than in an error, so the
keybinding always opens something that can change the wallpaper.

The server runs inside the project's manifest shell, because the page is
rendered by the same modules the desktop is: a plain guile on PATH has the
interpreter but not the libraries.  The server is also left to its own idle
timeout instead of being tied to the browser process - a browser that already
has a window open answers the launch by opening another one and exiting
immediately, and killing the server at that moment would close the gallery the
user is looking at."
  (format #f "#!/usr/bin/env bash
# ====== Heks-Linux wallpaper gallery ======
#
# auto-generated file, DO NOT EDIT!
#
# Opens the wallpaper collection as a page with a large preview, served from a
# socket on this machine.  Falls back to the Rofi wall when the page cannot be
# served.

set -u

PORT=~a
URL=\"http://127.0.0.1:$PORT/~a\"
CLONE=\"~a\"
SRC=\"$CLONE/src\"
FALLBACK=\"~a\"
LOG=\"${TMPDIR:-/tmp}/heks-gallery.log\"

port_open() {
    (exec 3<>\"/dev/tcp/127.0.0.1/$PORT\") >/dev/null 2>&1
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

# The page is rendered by the project's own modules, so the server needs the
# manifest shell: a bare guile has the interpreter and not the libraries.
start_server() {
    cd \"$CLONE\" || return 1
    guix shell -m manifest.scm -- guile -L \"$SRC\" -c '((@ (heks-linux gallery) main))'
}

BROWSER=$(browser_bin) || exec \"$FALLBACK\"
if [ ! -d \"$SRC\" ] || ! command -v guix >/dev/null 2>&1; then
    exec \"$FALLBACK\"
fi

# One server per session: a second launch reuses the first one.
if ! port_open; then
    ( start_server >\"$LOG\" 2>&1 & )
    for _ in $(seq 1 120); do
        port_open && break
        sleep 0.1
    done
fi
if ! port_open; then
    exec \"$FALLBACK\"
fi

exec \"$BROWSER\" --app=\"$URL\" --window-size=1320,900
"
          port
          anchor
          (gallery-clone-dir-absolute)
          fallback))

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
  ;; The palette tab, and the Rofi palette picker as its fallback: the same
  ;; arrangement the wallpaper side has, so neither chooser can be broken by a
  ;; machine without a browser.
  (install-config-file! #:name (palette-launcher-filename)
                        #:dir (gallery-launcher-dir)
                        #:contents (mk-gallery-launcher-cmd
                                    #:anchor "#palettes"
                                    #:fallback (format #f "~a/~a"
                                                       (rofi-theme-menu-dir)
                                                       (rofi-theme-menu-filename)))
                        #:perms 493)
  (log-success s "Installed the wallpaper gallery"))
