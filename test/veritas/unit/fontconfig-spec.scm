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
;; Unit tests for (heks-linux fontconfig).

;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure that
;; the veritas runner later applies to a context.  When such a call sits in a
;; non-final position of a body (typically inside a `let'), its return value is
;; unused and Guile's optimizer deletes the call entirely, so the assertion
;; silently never runs.  Always pass assertions as direct arguments to `test', as
;; this file does.

;;; Code:

(define-module (veritas unit fontconfig-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux fontconfig)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (edit-attr edit key)
  "Return attribute @var{key} of the fontconfig @code{edit} element @var{edit}.

An edit is SXML: its attributes are the second element, as an alist of
two-element lists, so this is a lookup in that alist."
  (let ((attrs (cdr (cadr edit))))
    (and (assoc key attrs)
         (cadr (assoc key attrs)))))

(define (tree-contains? tree needle)
  "Return @code{#t} when @var{needle} occurs anywhere inside @var{tree}."
  (cond ((null? tree) #f)
        ((pair? tree) (or (tree-contains? (car tree) needle)
                          (tree-contains? (cdr tree) needle)))
        ((equal? tree needle) #t)
        (else #f)))

(define (edit-named name)
  "Return the first edit that assigns @var{name}, or @code{#f}."
  (find (lambda (edit)
          (equal? (edit-attr edit 'name) name)) (fontconfig-edits)))

(define (edit-value name)
  "Return the value node of the edit that assigns @var{name}, or @code{#f}.

The node is a boolean or a constant, which is exactly the distinction fontconfig
makes between a flag and a keyword."
  (let ((edit (edit-named name)))
    (and edit (caddr edit))))

(define fontconfig-suite
  (suite "Fontconfig Configuration Suite"
         (test "Text Is Smoothed The Way A Mac Smooths It"
               ;; Grayscale antialiasing, light hinting, no LCD filter: the
               ;; three rules that make a Linux desktop's text look like macOS
               ;; instead of like subpixel-rendered Linux text.
               (assert-equal #:expect "none"
                             #:got
                             (cadr (edit-value "rgba"))
                             #:name
                             "Text should be smoothed in grey, not in subpixels")
               (assert-equal #:expect "hintslight"
                             #:got
                             (cadr (edit-value "hintstyle"))
                             #:name
                             "Glyphs should be hinted lightly, so the design survives")
               (assert-equal #:expect "lcdnone"
                             #:got
                             (cadr (edit-value "lcdfilter"))
                             #:name
                             "The LCD filter should leave the glyphs alone")
               (assert-equal #:expect 'bool
                             #:got (car (edit-value "antialias"))
                             #:name
                             "Antialiasing should be a boolean, not a keyword")
               (assert-equal #:expect "true"
                             #:got
                             (cadr (edit-value "antialias"))
                             #:name "Antialiasing should be on"))

         (test "Every Rule Assigns"
               ;; A program that wants subpixel text asks for it in the pattern
               ;; it matches; an edit in the default weak mode would be skipped
               ;; as redundant and the program would keep its own rendering.
               (assert-equal #:expect '()
                             #:got
                             (remove (lambda (edit)
                                       (equal? (edit-attr edit 'mode)
                                               "assign"))
                                     (fontconfig-edits))
                             #:name
                             "Every edit should assign, not merely prefer"))

         (test "The Rules Are Overridable"
               (assert-equal #:expect "rgb"
                             #:got
                             (parameterize ((fontconfig-rgba-order "rgb"))
                               (cadr (edit-value "rgba")))
                             #:name
                             "A machine that wants subpixel rendering should be able to ask for it")
               (assert-equal #:expect "false"
                             #:got
                             (parameterize ((fontconfig-antialias? #f))
                               (cadr (edit-value "antialias")))
                             #:name
                             "And a machine that wants no smoothing at all"))

         (test "The File Is Valid Fontconfig XML"
               ;; fontconfig parses its files against its own DTD: an xmlns
               ;; attribute is rejected as invalid, once per font match, for a
               ;; file only fontconfig ever reads.
               (assert-true (not (eq? #f (string-contains
                                          (fontconfig-config-xml)
                                          "<?xml version=")))
                            #:name "The file should open with an XML declaration")
               (assert-true (not (eq? #f (string-contains
                                          (fontconfig-config-xml)
                                          "<!DOCTYPE fontconfig")))
                            #:name
                            "It should carry the DOCTYPE fontconfig's own files carry")
               (assert-equal #:expect #f
                             #:got
                             (string-contains (fontconfig-config-xml)
                                              "xmlns")
                             #:name
                             "It should not carry a namespace fontconfig rejects")
               (assert-true (not (eq? #f (string-contains
                                          (fontconfig-config-xml)
                                          "<match target=\"font\">")))
                            #:name "The rules should be one font-targeted match")
               (assert-equal #:expect 'fontconfig
                             #:got (car (fontconfig-config))
                             #:name
                             "The renderer should return the fontconfig element"))

         (test "Emboldening Is Off Unless Asked For"
               (assert-equal #:expect 1
                             #:got (length (fontconfig-matches))
                             #:name
                             "One match by default: the size-gated rule is not written")
               (assert-equal #:expect 2
                             #:got
                             (length (parameterize ((fontconfig-embolden? #t))
                                       (fontconfig-matches)))
                             #:name
                             "A second, size-gated match appears when faking bold")
               (assert-true (eq? #f (tree-contains? (fontconfig-config)
                                                    "size"))
                            #:name
                            "By default there is no size gate to read")
               (assert-true (not (eq? #f (tree-contains?
                                          (parameterize ((fontconfig-embolden?
                                                          #t))
                                            (fontconfig-config))
                                          "size")))
                            #:name
                            "The faking should be gated on the point size")
               (assert-true (not (eq? #f (tree-contains?
                                          (parameterize ((fontconfig-embolden?
                                                          #t)
                                                         (fontconfig-embolden-threshold
                                                          14))
                                            (fontconfig-config))
                                          "14")))
                            #:name
                            "The gate should use the configured size"))))

(define (spec)
  (veritas-run fontconfig-suite))
