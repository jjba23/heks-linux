;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux gtk).  Both the @file{settings.ini} files and the
;; dconf writer script must carry the macOS window-control layout, otherwise
;; client-side decorated applications show GNOME-style controls instead of
;; traffic lights.

;;; Code:

(define-module (veritas unit gtk-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux gtk)
  #:use-module (heks-linux palette)
  #:export (spec))

(define macos-decoration-layout "close,minimize,maximize:")

(define (gtk3)
  (gtk3-config #:palette 'modus-operandi #:sans-font "Lucida Sans"))

(define (gtk4)
  (gtk4-config #:palette 'modus-operandi #:sans-font "Lucida Sans"))

(define (gtk-dconf palette)
  (gtk-dconf-settings #:palette palette
                      #:sans-font "Lucida Sans"
                      #:mono-font "Intel One Mono"))

(define (dconf-entry group palette)
  "Return the dconf alist for @var{group} out of the generated GTK settings.

The generated settings are a list of @code{(group . alist)} entries, so the
per-key association list lives in the entry's tail."
  (cdr (assoc group (gtk-dconf palette))))

(define gtk-suite
  (suite "GTK Configuration Suite"
         (test "GTK 3 Settings"
               (assert-true (list? (gtk3))
                            #:name "The GTK 3 settings should be an association list")
               (assert-equal #:expect macos-decoration-layout
                             #:got (assoc-ref (gtk3) 'gtk-decoration-layout)
                             #:name
                             "GTK 3 windows should show macOS style traffic lights")
               (assert-true (not (eq? #f (assoc-ref (gtk3) 'gtk-font-name)))
                            #:name "The sans font should be configured"))

         (test "GTK 4 Settings"
               (assert-true (list? (gtk4))
                            #:name "The GTK 4 settings should be an association list")
               (assert-equal #:expect macos-decoration-layout
                             #:got (assoc-ref (gtk4) 'gtk-decoration-layout)
                             #:name
                             "GTK 4 windows should show macOS style traffic lights"))

         (test "dconf Button Layout"
               (assert-equal #:expect "'close,minimize,maximize:'"
                             #:got
                             (assoc-ref (dconf-entry
                                         "/org/gnome/desktop/wm/preferences"
                                         'modus-operandi)
                                        'button-layout)
                             #:name
                             "The window manager should place the traffic lights on the left"))

         (test "dconf Colour Scheme Follows The Palette"
               (assert-equal #:expect "'prefer-dark'"
                             #:got
                             (assoc-ref (dconf-entry
                                         "/org/gnome/desktop/interface"
                                         'modus-vivendi-tritanopia)
                                        'color-scheme)
                             #:name
                             "Dark palettes should request the dark GTK scheme")
               (assert-equal #:expect "'prefer-light'"
                             #:got
                             (assoc-ref (dconf-entry
                                         "/org/gnome/desktop/interface"
                                         'modus-operandi)
                                        'color-scheme)
                             #:name
                             "Light palettes should request the light GTK scheme"))

         (test "dconf Theme Names Come From The Palette"
               (assert-equal #:expect (format #f "'~a'"
                                              (get-icon-theme 'modus-operandi))
                             #:got
                             (assoc-ref (dconf-entry
                                         "/org/gnome/desktop/interface"
                                         'modus-operandi)
                                        'icon-theme)
                             #:name "The icon theme should be palette derived")
               (assert-true (not (eq? #f (assoc-ref (dconf-entry
                                                     "/org/gnome/desktop/interface"
                                                     'modus-operandi)
                                                    'accent-color)))
                            #:name "An accent colour should always be exported"))))

(define (spec)
  (veritas-run gtk-suite))
