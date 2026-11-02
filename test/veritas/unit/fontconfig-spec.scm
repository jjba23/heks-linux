;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

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
  #:use-module (heks-linux user-settings)
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
  (cond [(null? tree) #f]
        [(pair? tree) (or (tree-contains? (car tree) needle)
                        (tree-contains? (cdr tree) needle))]
        [(equal? tree needle) #t]
        [else #f]))

(define (edit-named name)
  "Return the first edit that assigns @var{name}, or @code{#f}."
  (find (lambda (edit)
          (equal? (edit-attr edit 'name) name)) (fontconfig-edits)))

(define (fallbacks-without-sans)
  "Return the fallback families the rule actually writes, best first.

The configured family is dropped when the rule is written - a family is not its
own fallback - so this is what the rendered list should say."
  (remove (lambda (family)
            (equal? family (heks-linux-sans-font)))
          (fontconfig-sans-fallbacks)))

(define (fontconfig-family-matches-edits)
  "Return the @code{edit} elements of the sans-fallback rule, or @code{'()}.

A match is @code{(match (@ ...) (test ...) (edit ...) ...)}, so this is the
children of the first match with the attribute list and the test dropped."
  (let ((matches (fontconfig-family-matches)))
    (if (null? matches)
      '()
      (filter (lambda (element)
                (and (pair? element) (eq? 'edit (car element))))
              (cddar matches)))))

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
        "The gate should use the configured size"))

    (test "A Missing Sans Family Falls Back To The Faces This Desktop Is Drawn In"
      ;; Every surface asks fontconfig for one family by name.  When the
      ;; machine has not got it, the rule is what stands between the menu
      ;; bar and the distribution's idea of a default sans.
      (assert-equal #:expect 1
        #:got (length (fontconfig-family-matches))
        #:name "One rule, and only when there is something to fall back to")
      (assert-true (not (eq? #f (string-contains
                                 (fontconfig-config-xml)
                                 "<match target=\"pattern\">")))
        #:name "The fallback rule matches patterns, not faces")
      (assert-true (not (eq? #f (tree-contains?
                                 (fontconfig-config)
                                 (heks-linux-sans-font))))
        #:name
        "The rule should test for the family this desktop asks for")
      (assert-true (not (eq? #f (tree-contains?
                                 (fontconfig-config)
                                 "Helvetica Neue")))
        #:name "The Mac faces should be in the file"))

    (test "The Fallbacks Outrank The Distribution's Default"
      ;; A weak edit loses to the generic chain the distribution has
      ;; already resolved the pattern to - measured: with a weak edit,
      ;; asking for a family that is not installed answered Arial, not
      ;; the face the edit named.  `same' is what makes the rule work.
      (assert-equal #:expect '("append")
        #:got
        (delete-duplicates (map (lambda (edit)
                                  (edit-attr edit 'mode))
                                (fontconfig-family-matches-edits))
                           string=?)
        #:name "The fallbacks should be appended")
      (assert-equal #:expect '("same")
        #:got
        (delete-duplicates (map (lambda (edit)
                                  (edit-attr edit 'binding))
                                (fontconfig-family-matches-edits))
                           string=?)
        #:name
        "They should be bound as strongly as the family that was asked for")
      (assert-equal #:expect 0
        #:got
        (length (remove (lambda (edit)
                          (equal? (edit-attr edit 'name) "family"))
                        (fontconfig-family-matches-edits)))
        #:name "Every edit should assign a family"))

    (test "The Fallbacks Are Written In The Order They Are Preferred"
      ;; fontconfig tries the last appended family first, so the rule is
      ;; written backwards and the parameter reads best-first.
      (assert-equal #:expect (last (fallbacks-without-sans))
        #:got
        (cadr (caddr (car (fontconfig-family-matches-edits))))
        #:name
        "The last edit written should be the last name in the list")
      (assert-equal #:expect (car (fallbacks-without-sans))
        #:got
        (cadr (caddr (last (fontconfig-family-matches-edits))))
        #:name
        "And the first edit written should be the first expected face")
      (assert-equal #:expect '("Adwaita Sans" "Helvetica Neue")
        #:got
        (map (lambda (edit) (cadr (caddr edit)))
             (parameterize ((fontconfig-sans-fallbacks '("Helvetica Neue"
                                                         "Adwaita Sans")))
               (fontconfig-family-matches-edits)))
        #:name "A two-family list should be written bottom-up"))

    (test "An Empty List Writes No Rule"
      (assert-equal #:expect '()
        #:got
        (parameterize ((fontconfig-sans-fallbacks '()))
          (fontconfig-family-matches))
        #:name
        "A machine that wants the stock fontconfig gets no rule at all")
      (assert-equal #:expect '()
        #:got
        (parameterize ((fontconfig-sans-fallbacks (list (heks-linux-sans-font))))
          (fontconfig-family-matches))
        #:name
        "A list that only repeats the configured family has nothing to add")
      (assert-equal #:expect 1
        #:got
        (length (parameterize ((fontconfig-sans-fallbacks '("Helvetica Neue"
                                                            "Lucida Grande")))
                  (fontconfig-family-matches-edits)))
        #:name
        "A family is not its own fallback"))))

(define (spec)
  (veritas-run fontconfig-suite))
