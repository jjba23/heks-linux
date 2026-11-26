;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux mako).  A notification banner is the one surface
;; a person reads without opening anything, so the tests ask the questions a
;; screen asks: does the panel wear the palette's own background, is the ink
;; the palette's ink, and does a critical banner say so in the accent.
;;
;; The suite renders every registered palette, not just the default, because a
;; banner is translucent: the values mako is handed are eight-digit hex pairs,
;; and a palette that lost one is a banner that falls back to mako's own black.

;;; Code:

(define-module (veritas unit mako-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 format)
  #:use-module (heks-linux mako)
  #:use-module (heks-linux palette)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

(define (setting name config)
  "Return @var{name}'s value in a rendered mako @var{config}, or @code{#f}.

The configuration is a list of pairs plus the raw strings that carry mako's
sections, so the pairs are selected before they are looked up."
  (assoc-ref (filter pair? config) name))

(define (banner config)
  "Return @var{config}'s banner background, as mako spells it."
  (setting 'background-color config))

(define (critical-section config)
  "Return the @code{[urgency=critical]} section of @var{config}."
  (find (lambda (line)
          (and (string? line)
            (not (eq? #f (string-contains line "[urgency=critical]")))))
        config))

(define (upper-hex colour)
  "Return @var{colour} the way mako's colours are rendered: uppercased."
  (string-upcase colour))

(define (expected-background palette)
  "Return the banner background @var{palette} should render."
  (string-upcase (string-append (get-color palette 'background)
                                (opacity->hex-alpha (get-mako-opacity palette)))))

(define mako-suite
  (suite "Mako Banners"
    (test "The Banner Wears The Palette's Own Colours"
      (let* ((palette 'catppuccin-mocha)
             (config (mako-config #:palette palette
                                  #:sans-font "Work Sans")))
        (assert-equal #:expect (expected-background palette)
          #:got (banner config)
          #:name "The panel is the palette's background, at the palette's alpha")
        (assert-equal #:expect (string-upcase
                                (string-append (get-color palette 'text)
                                               (@@ (heks-linux mako) mako-text-alpha)))
          #:got (setting 'text-color config)
          #:name "The body is the palette's text")
        (assert-equal #:expect (string-append (get-color palette 'text-l)
                                              (@@ (heks-linux mako) mako-border-alpha))
          #:got (setting 'border-color config)
          #:name "The hairline is the palette's quiet ink")
        (assert-equal #:expect (string-upcase
                                (string-append (get-color palette 'primary)
                                               (@@ (heks-linux mako) mako-accent-alpha)))
          #:got (setting 'progress-color config)
          #:name "The progress bar is the palette's accent")))

    (test "A Light Palette Gets A Light Banner"
      ;; The reference's banners were smoked glass whatever the theme.  Here the
      ;; two halves of the registry have to read as two different surfaces, or
      ;; the palette is not reaching the notification at all.
      (assert-true (not (string=? (banner (mako-config #:palette 'modus-operandi
                                                       #:sans-font "Work Sans"))
                                  (banner (mako-config #:palette 'modus-vivendi
                                                       #:sans-font "Work Sans"))))
        #:name "A light palette and a dark one do not render the same panel")
      (assert-true (>= (contrast-ratio (get-color 'modus-operandi 'text)
                                       (get-color 'modus-operandi 'background))
                       7)
        #:name "And the light palette's ink is readable on its own panel"))

    (test "A Critical Banner Wears The Accent Rim"
      (let ((palette 'dracula))
        (assert-true (not (eq? #f (critical-section (mako-config #:palette palette
                                                                 #:sans-font "Work Sans"))))
          #:name "An urgency section is rendered")
        (assert-true (not (eq? #f (string-contains (critical-section
                                                    (mako-config #:palette palette
                                                                 #:sans-font "Work Sans"))
                                                   (get-color palette 'primary))))
          #:name "And it is edged in the palette's accent")))

    (test "Every Palette Renders A Banner"
      ;; A palette is translucent here: the eight-digit colours mako takes are
      ;; built from the palette's own key, so a palette that cannot produce one
      ;; is a banner in mako's default black.
      (assert-equal #:expect '()
        #:got (filter-map (lambda (palette)
                            (catch #t
                                   (lambda ()
                                     (let ((config (mako-config #:palette palette
                                                                #:sans-font "Work Sans")))
                                       (if (string=? (banner config)
                                                     (expected-background palette))
                                         #f
                                         (format #f "~a: banner is ~a"
                                                 palette
                                                 (banner config)))))
                                   (lambda (key . args)
                                     (format #f "~a: ~a" palette key))))
                          (palette-names))
        #:name "Every palette the registry names reaches the notification panel"))))

(define (spec)
  (veritas-run mako-suite))
