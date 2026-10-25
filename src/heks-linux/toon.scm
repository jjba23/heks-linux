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
;; The window behind the three questions this desktop answers about itself: what
;; do I press, what does it look like, and what could it look like instead?
;; heks-toon answers all three - the keyboard reference, the wall chooser and the
;; palette chooser - in one GTK4 window, painted from the palette the desktop is
;; wearing.
;;
;; It is a program of its own, installed from the jointhefreeworld collection
;; (`maak install-heks-toon'), and it already knows this desktop: the palette
;; comes from ~/.config/heks-linux/local-settings.scm, the pictures from the
;; collection `maak install-wallpaper-files' clones, and the switching from
;; `heks-wallpaper' and `heks-rofi-theme-menu', both of which this configuration
;; installs.  So the half that belongs here is small - the command lines the bar
;; and the compositor build, the application id the compositor matches on, and
;; the retirement of the three HTML pages this configuration used to render.
;;
;; Those pages were documents: an HTML file this configuration wrote, a local
;; HTTP server it ran to serve thumbnails, and a Chrome app window to look at
;; them in.  heks-toon is the same three views without a browser in the middle,
;; which is why nothing here renders, serves or watches anything.

;;; Code:

(define-module (heks-linux toon)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-13)
  #:export (toon-command
            toon-keys-command
            toon-walls-command
            toon-palettes-command
            toon-spawn-command
            toon-app-id
            toon-launcher-dir
            toon-config-dir
            toon-retired-launchers
            toon-retired-pages
            install-toon-config))

(define s
  (scriba-auto-logger))

;; The program's name as installed.  A parameter rather than a literal so the
;; bar can be pointed at a checkout (with HEKS_TOON_SCHEME_DIR set) the way
;; `wallpaper-script-command' names the engine.
(define toon-command
  (make-parameter "heks-toon"))

;; The GTK application id.  The compositor's window rule matches on it, so it is
;; a name this configuration and that program have to agree on - and it is the
;; same string as the desktop entry's StartupWMClass.
(define toon-app-id
  "org.jointhefreeworld.heks-toon")

;; Where the launchers the pages used to install live.  Nothing is written here
;; any more; it is only where the old ones are removed from.
(define toon-launcher-dir
  (make-parameter (format #f "~a/.local/bin"
                          (or (getenv "HOME") "/tmp"))))

;; Where this configuration keeps its own files.  The keyboard reference was one
;; directory of it, and retiring that page is the only thing left to do there.
(define toon-config-dir
  (make-parameter (format #f "~a/.config/heks-linux"
                          (or (getenv "HOME") "/tmp"))))

;; The launchers the three pages installed.  A machine that had them keeps them
;; until they are removed, and a script nobody calls is a script somebody will
;; eventually click: it would open a page nothing writes any more.
(define toon-retired-launchers
  '("heks-keybindings" "heks-wallpaper-gallery" "heks-palette-gallery"))

;; What those launchers opened, below `toon-config-dir': the generated keyboard
;; reference, and the directory it lived in.  The wall and palette pages were
;; served from memory and left nothing behind.
(define toon-retired-pages
  '("keybindings/index.html" "keybindings"))

(define (toon-command-line . args)
  "Return the command that runs heks-toon with @var{args}.

The bar and the compositor both spawn it through a shell, so the program and
its arguments are joined into one line here instead of being handed over as
argv.  No argument means the window's default view."
  (if (null? args)
      (toon-command)
      (format #f "~a ~a" (toon-command) (string-join args " "))))

(define (toon-keys-command)
  "Return the command that opens the keyboard reference.
The reference is the window's first view, so it is the program on its own -
which is also why the bar's question mark needs no argument."
  (toon-command-line))

(define (toon-walls-command)
  "Return the command that opens the wall chooser, on its own view."
  (toon-command-line "walls"))

(define (toon-palettes-command)
  "Return the command that opens the palette chooser, on its own view.
Choosing a card there runs the same `heks-rofi-theme-menu' the bar's palette
button opens, so a switch reads the same whichever way it was started."
  (toon-command-line "palettes"))

(define (toon-spawn-command command)
  "Return @var{command} the way a surface that is not the compositor runs it.

The bar is a plain client, and a window that is already open cannot be raised by
a client with nothing to prove it was the user who asked: under Wayland that
takes an activation token, and a program started by another program has none.
Niri's own IPC spawn hands one over, so the bar asks the compositor to spawn it,
and falls back to running it directly on a machine where niri is not the
compositor."
  (format #f "niri msg action spawn -- ~a 2>/dev/null || ~a" command command))

(define (remove-retired-file! label path)
  "Delete @var{path} if it is there, saying which @var{label} it belonged to.
Called for the files the pages installed: they are only removed when present,
so installing on a machine that never had the pages says nothing."
  (when (file-exists? path)
    (delete-file path)
    (log-info s "Removed the retired ~a: ~a" label path)))

(define (install-toon-config)
  "Retire the pages heks-toon replaces, and leave the window to find its data.

Nothing is written: heks-toon reads the desktop's own files, so it has no
configuration of ours to render.  What is removed is what the three HTML pages
left behind - their launchers, and the generated keyboard reference with the
directory around it - so that a machine which had the pages does not keep
scripts and documents nothing maintains."
  (log-info s "Retiring the HTML pages heks-toon replaces")
  (load-local-overrides '(heks-linux toon)
                        'toon-settings)
  (for-each (lambda (launcher)
              (remove-retired-file! "page launcher"
                                    (format #f "~a/~a"
                                            (toon-launcher-dir)
                                            launcher)))
            toon-retired-launchers)
  (for-each (lambda (page-name)
              (let ((page (format #f "~a/~a"
                                  (toon-config-dir)
                                  page-name)))
                (if (file-exists? page)
                    (if (eq? 'directory (stat:type (stat page)))
                        ;; An emptied directory goes too, but only when this run
                        ;; emptied it: rmdir refuses a directory with anything
                        ;; else in it, which is the safety we want.
                        (catch #t
                          (lambda ()
                            (rmdir page)
                            (log-info s "Removed the retired page directory: ~a"
                                      page))
                          (lambda (key . args)
                            (log-info s "Kept the page directory ~a: it is not empty"
                                      page)))
                        (remove-retired-file! "page" page)))))
            toon-retired-pages)
  (log-success s "Installed heks-toon configuration"))
