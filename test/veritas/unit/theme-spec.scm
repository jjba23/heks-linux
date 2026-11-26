;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The palette reaches a dozen surfaces, and each one renders it differently: a
;; KDL file, a CSS file, an alist mako reads, a Lisp form Emacs loads.  This
;; file asks the two questions that keep them one system:
;;
;;   does every palette render every surface, and
;;   does a palette switch re-render every surface that reads one?
;;
;; The second is the one that rots quietly.  A surface added with a `get-color'
;; in it and not added to `theme-surfaces' draws yesterday's palette until the
;; next `maak home-reconfigure', which nobody runs after clicking a swatch.

;;; Code:

(define-module (veritas unit theme-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 format)
  #:use-module (maak)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux niri)
  #:use-module (heks-linux whelk)
  #:use-module (heks-linux waybar)
  #:use-module (heks-linux rofi)
  #:use-module (heks-linux mako)
  #:use-module (heks-linux gtk)
  #:use-module (heks-linux kitty)
  #:use-module (heks-linux btop)
  #:use-module (heks-linux labwc)
  #:use-module (heks-linux lambdock)
  #:use-module (heks-linux rmpc)
  #:use-module (heks-linux palette-picker)
  #:use-module (heks-linux bridges)
  #:use-module (heks-linux zen)
  #:use-module (heks-linux wallpaper)
  #:use-module (heks-linux dconf)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

;; The surfaces whose colours are the palette's, as the (module function) pair
;; `maak install-theme' renders them.  A surface belongs here when its output
;; contains a colour or a theme chosen from `(heks-linux-palette)'; the surfaces
;; that read a palette-derived file instead - the compositor, the shell, the
;; dock - watch it themselves and are not in this list.
(define palette-surfaces
  '((mako mako)
    (waybar waybar)
    (rofi rofi)
    (rmpc rmpc)))

(define (surface-renders? thunk)
  "Whether @var{thunk} returns something a file can be written from."
  (catch #t
         (lambda ()
           (let ((value (thunk)))
             (cond
               [(string? value) (> (string-length value) 0)]
               [(pair? value) (> (length value) 0)]
               [else #f])))
         (lambda (key . args) #f)))

(define (surfaces-for palette)
  "Return @code{(NAME . THUNK)} for every palette-dependent surface.

@var{palette} is passed explicitly where the renderer takes it and bound as the
current palette where it reads the setting, because both kinds of surface are
the palette's.
  "
  (let ((bound (lambda (thunk)
                 (lambda ()
                   (parameterize ((heks-linux-palette palette))
                     (thunk))))))
    (list (cons 'niri
                (lambda ()
                  (string-join (serialize-kdl (niri-config #:palette palette))
                               "\n")))
          (cons 'whelk (lambda () (whelk-config #:palette palette)))
          (cons 'waybar (bound (lambda () (waybar-style))))
          (cons 'rofi (bound (lambda () (rofi-theme))))
          (cons 'mako (lambda () (mako-config #:palette palette
                                              #:sans-font "Work Sans")))
          (cons 'gtk (lambda () (gtk3-config #:palette palette
                                             #:sans-font "Work Sans")))
          (cons 'gtk-dconf (lambda () (gtk-dconf-settings #:palette palette
                                                          #:sans-font "Work Sans"
                                                          #:mono-font "JuliaMono")))
          (cons 'kitty (bound kitty-config))
          (cons 'btop (bound heks-linux-btop-settings))
          (cons 'labwc (lambda () (labwc-themerc #:palette palette)))
          (cons 'lambdock (lambda () (lambdock-config)))
          (cons 'rmpc (bound rmpc-theme))
          (cons 'palette-picker (lambda () (palette-swatch-colors palette)))
          (cons 'emacs (bound heks-linux-to-emacs-bridge))
          (cons 'zen (bound zen-user-js))
          (cons 'wallpaper (lambda () (wallpapers)))
          (cons 'dconf (lambda () (heks-linux-dconf-settings))))))

(define (palettes-that-fail palette)
  "Return the names of the surfaces that fail to render for @var{palette}."
  (filter-map (lambda (surface)
                (if (surface-renders? (cdr surface))
                  #f
                  (format #f "~a" (car surface))))
              (surfaces-for palette)))

(define theme-suite
  (suite "Palette Surfaces"
    (test "A Palette Switch Re-Renders Every Surface That Reads One"
      ;; `maak install-theme' is what the picker runs.  A surface missing from
      ;; this list keeps its old palette until a full reconfigure, which is a
      ;; desktop half-repainted by a click.
      (let ((surfaces (@@ (maak) theme-surfaces)))
        (for-each (lambda (surface)
                    (assert-true (not (eq? #f (member surface surfaces)))
                      #:name (format #f "~a re-renders with the palette"
                                     (car surface))))
                  palette-surfaces)))

    (test "A Palette Switch Reloads The Bars That Do Not Watch Their File"
      ;; Niri, whelk and the dock see the file they read change.  Waybar and
      ;; mako do not: they are told, and a switch that writes their file and
      ;; does not tell them is a palette that landed everywhere but the bar.
      (let ((commands ((@@ (maak) palette-reload-commands))))
        (assert-true (not (not (any (lambda (argv)
                                      (and (member "waybar" argv)
                                        (member "-USR2" argv)))
                                    commands)))
          #:name "Waybar is told to re-read its file")
        (assert-true (not (not (any (lambda (argv)
                                      (and (member "makoctl" argv)
                                        (member "reload" argv)))
                                    commands)))
          #:name "Mako is told to re-read its file")))

    (test "Every Palette Renders Every Surface"
      ;; The registry is the input to all of them, so a palette that a surface
      ;; cannot read is a render that raises halfway through a reconfigure.
      (assert-equal #:expect '()
        #:got (filter-map (lambda (palette)
                            (let ((failures (palettes-that-fail palette)))
                              (if (null? failures)
                                #f
                                (format #f "~a: ~a"
                                        palette
                                        (string-join failures " ")))))
                          (palette-names))
        #:name "No palette leaves a surface unrendered"))))

(define (spec)
  (veritas-run theme-suite))
