;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux gtk).  Both the @file{settings.ini} files and the
;; dconf writer script must carry the left-hand window-control layout, otherwise
;; client-side decorated applications show GNOME-style controls instead of the
;; controls on the left.

;;; Code:

(define-module (veritas unit gtk-spec)
  #:use-module (veritas veritas)
  ;; The module under test is imported last, so a name both modules carry is
  ;; resolved in its favour: `(heks-linux palette)' is imported here for its
  ;; colours, and what this file tests is `(heks-linux gtk)'.
  #:use-module (heks-linux palette)
  #:use-module (heks-linux gtk)
  #:export (spec))

(define left-decoration-layout "close,minimize,maximize:")

(define (answered-by stage thunk)
  "Run THUNK, and name the stage and the stack if it raises.

A renderer that raises inside `assert-true' reaches the reporter as a bare
`(cdr #f)' with no test named and nothing said about which call produced it --
the one fact a failure on somebody else's machine has to carry.  The stack is
printed from a pre-unwind handler, which is the only place it is still there to
print."
  (catch #t
         thunk
         (lambda (key . args)
           (error "gtk-spec: a renderer this suite asks for raised"
                  (list 'stage stage 'error key 'args args)))
         (lambda (key . args)
           (let ((stack (make-stack #t)))
             (format (current-error-port)
                     "~%!! stage ~a raised ~s ~s~%~a~%"
                     stage
                     key
                     args
                     (with-output-to-string
                      (lambda ()
                        (display-backtrace stack (current-output-port)))))))))

(define (gtk3)
  (answered-by 'gtk3-config
               (lambda ()
                 (gtk3-config #:palette 'modus-operandi
                              #:sans-font "Work Sans"))))

(define (gtk4)
  (answered-by 'gtk4-config
               (lambda ()
                 (gtk4-config #:palette 'modus-operandi
                              #:sans-font "Work Sans"))))

(define (gtk-dconf palette)
  (answered-by 'gtk-dconf-settings
               (lambda ()
                 (gtk-dconf-settings #:palette palette
                                     #:sans-font "Work Sans"
                                     #:mono-font "JuliaMono"))))

(define (dconf-entry group palette)
  "Return the dconf alist for @var{group} out of the generated GTK settings.

The generated settings are a list of @code{(group . alist)} entries, so the
per-key association list lives in the entry's tail.  A group that is not there is
named here, together with the groups that are: left to @code{cdr}, a missing
entry reports itself as @code{(cdr #f)} five times over and says nothing about
the settings the run actually produced."
  (let ((entry (assoc group (gtk-dconf palette))))
    (if entry
      (cdr entry)
      (error "gtk-spec: the generated settings have no such dconf group"
             (list 'palette palette 'wanted group 'got (gtk-dconf palette))))))

(define gtk-suite
  (suite "GTK Configuration Suite"
    (test "The GTK renderers come from this tree's gtk module"
      ;; The renderers are `(heks-linux gtk)'s, and only its: a second module
      ;; that exported `gtk3-config' would be resolved in favour of whichever the
      ;; spec imported last, and the suite would test that copy while believing
      ;; it tested this one.  The failure it produces is a `(cdr #f)' from inside
      ;; a renderer, which names neither the copy nor the module.
      (assert-true (eq? #f (module-variable (resolve-module '(heks-linux palette))
                                            'gtk3-config))
        #:name "The palette module should not carry the GTK renderers")
      (assert-true
        (not (eq? #f (module-variable (resolve-module '(heks-linux gtk))
                                      'gtk3-config)))
        #:name "The gtk module should be the one that defines them"))

    (test "GTK 3 Settings"
      (assert-true (list? (gtk3))
        #:name "The GTK 3 settings should be an association list")
      (assert-equal #:expect left-decoration-layout
        #:got (assoc-ref (gtk3) 'gtk-decoration-layout)
        #:name
        "GTK 3 windows should put the window controls on the left")
      (assert-true (not (eq? #f (assoc-ref (gtk3) 'gtk-font-name)))
        #:name "The sans font should be configured"))

    (test "GTK 4 Settings"
      (assert-true (list? (gtk4))
        #:name "The GTK 4 settings should be an association list")
      (assert-equal #:expect left-decoration-layout
        #:got (assoc-ref (gtk4) 'gtk-decoration-layout)
        #:name
        "GTK 4 windows should put the window controls on the left"))

    (test "dconf Button Layout"
      (assert-equal #:expect "'close,minimize,maximize:'"
        #:got
        (assoc-ref (dconf-entry
                    "/org/gnome/desktop/wm/preferences"
                    'modus-operandi)
                   'button-layout)
        #:name
        "The window manager should place the window controls on the left"))

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
