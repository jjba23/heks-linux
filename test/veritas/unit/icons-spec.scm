;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux icons): the Tela variants every palette draws
;; from, and the pinned checkout the installer renders them from.

;;; Code:

(define-module (veritas unit icons-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux icons)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (tela-variant? theme)
  "Whether @var{theme} is a Tela theme directory."
  (string-prefix? "Tela" theme))

(define icons-suite
  (suite "Tela Icon Themes Suite"
    (test "Every Variant Is Installed Whole"
      (assert-equal #:expect 15
        #:got (length tela-icon-colors)
        #:name "Tela 2026-07-07 ships fifteen colour variants")
      (assert-equal #:expect 3
        #:got (length tela-icon-brightnesses)
        #:name "Each colour is rendered at three brightnesses")
      (assert-equal #:expect 45
        #:got (length (tela-icon-themes))
        #:name "Fifteen colours at three brightnesses make forty-five themes")
      (assert-equal #:expect 45
        #:got (length (delete-duplicates (tela-icon-themes)))
        #:name "No variant should be installed twice")
      (assert-true (not (not (every tela-variant? (tela-icon-themes))))
        #:name "Every entry should be a Tela theme")
      (assert-true (not (not (member "Tela" (tela-icon-themes))))
        #:name "The standard colour should be the bare Tela theme")
      (assert-true (not (not (member "Tela-purple-light"
                                     (tela-icon-themes))))
        #:name "A colour and brightness pair should be installed"))

    (test "Every Accent Has An Installed Theme"
      (assert-true (not (not (every (lambda (accent)
                                      (and (member
                                            (tela-icon-theme accent
                                                             #:dark? #f)
                                            (tela-icon-themes))
                                        (member
                                         (tela-icon-theme accent
                                                          #:dark? #t)
                                         (tela-icon-themes))))
                                    (map car tela-icon-accents))))
        #:name
        "Every accent should name a theme the installer puts in place"))

    (test "Accents Pick The Matching Variant"
      (assert-equal #:expect "Tela-purple-light"
        #:got (tela-icon-theme 'purple #:dark? #f)
        #:name "A light purple palette should take the light purple artwork")
      (assert-equal #:expect "Tela-purple-dark"
        #:got (tela-icon-theme 'purple #:dark? #t)
        #:name "A dark purple palette should take the dark purple artwork")
      (assert-equal #:expect "Tela-green-light"
        #:got (tela-icon-theme 'green #:dark? #f)
        #:name "Green should take the green artwork")
      (assert-equal #:expect "Tela-blue-light"
        #:got (tela-icon-theme 'cyan #:dark? #f)
        #:name "Cyan should take the nearest colour Tela ships")
      (assert-equal #:expect "Tela-black-dark"
        #:got (tela-icon-theme 'black #:dark? #t)
        #:name "Black should take the black artwork")
      (assert-error (lambda () (tela-icon-theme 'chartreuse #:dark? #f))
        #:name "An accent no Tela variant carries should raise"))

    (test "The Checkout Is Pinned To A Release"
      (assert-equal #:expect 'tela-icon-theme
        #:got (car tela-icon-repository)
        #:name "The installer should name its checkout")
      (assert-equal #:expect "2026-07-07"
        #:got (caddr tela-icon-repository)
        #:name "The installer should clone a released tag, not a branch")
      (assert-true (not (not (and (string-prefix? "https://"
                                                  (cadr tela-icon-repository))
                               (string-suffix? ".git"
                                               (cadr tela-icon-repository)))))
        #:name "The theme should come from its own Git repository"))))

(define (spec)
  (veritas-run icons-suite))
