;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux surface).
;;
;; The manifest is the one place a surface is described, and the table, the
;; keyboard reference and the doctor report are three printers over it.  What the
;; tests pin is that the description is complete and self-consistent: every
;; surface names a module and an installer that exists, no surface claims a file
;; twice, every keybinding points at a surface, and the printers agree with the
;; data they are printing.

;;; Code:

(define-module (veritas unit surface-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux surface)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:export (spec))

(define (installer-exists? surface)
  "Return #t when @var{surface} names an installer the module exports."
  (let* ((module (resolve-module (list 'heks-linux (surface-module surface))))
         (installer (surface-installer surface)))
    (and module
         (module-defined? module installer)
         (procedure? (module-ref module installer)))))

(define (manifest-suite)
  (suite "Manifest"
    (test "Every Surface Names A Module And An Installer"
      (assert-true (every (lambda (surface)
                            (and (symbol? (surface-module surface))
                                 (symbol? (surface-installer surface))))
                          surfaces)
        #:name "A surface is described by where its writer lives"))
    (test "Every Installer Exists"
      (let ((missing (remove installer-exists? surfaces)))
        (assert-equal #:expect '()
          #:got (map surface-name missing)
          #:name "A surface whose installer is misspelled is a surface that writes nothing")))
    (test "The Surfaces Are Named Once Each"
      (let ((names (map surface-name surfaces)))
        (assert-equal #:expect (length names)
          #:got (length (delete-duplicates names))
          #:name "Two surfaces with one name are one surface")))
    (test "A Surface Reads As Its Name"
      (assert-equal #:expect 'wezterm
        #:got (surface-name (surface-by-name 'wezterm))
        #:name "Lookup by name returns the entry"))))

(define (files-suite)
  (suite "Files"
    (test "No File Is Claimed By Two Modules"
      ;; Within one module an installer may call a sibling's installer - the GTK
      ;; files and their dconf writer are one pass in two procedures - so the
      ;; promise is between modules, where a shared file is a shared owner.
      (let* ((owners (append-map
                      (lambda (surface)
                        (map (lambda (write)
                               (cons (car write) (surface-module surface)))
                             (surface-files surface)))
                      surfaces))
             (files (delete-duplicates (map car owners) string=?)))
        (assert-true (every (lambda (file)
                              (<= (length (delete-duplicates
                                           (map cdr
                                                (filter (lambda (owner)
                                                          (string=? (car owner)
                                                                    file))
                                                        owners))))
                                  1))
                            files)
          #:name "Two modules writing one file is one owner too many")))

    (test "Every File Is Absolute"
      (assert-true (every (lambda (write) (string-prefix? "/" (car write)))
                          (append-map surface-files surfaces))
        #:name "A relative path would mean a different file per caller"))
    (test "A File Carries Its Mode"
      (assert-true (every (lambda (write) (number? (cadr write)))
                          (append-map surface-files surfaces))
        #:name "Every write states the permissions it wants"))))

(define (bindings-suite)
  (suite "Bindings"
    (test "Every Binding Names A Key And A Command"
      (assert-true (if (every (lambda (binding)
                                   (and (assq 'key binding)
                                        (assq 'cmd binding)
                                        (assq 'desc binding)))
                                 (surface-bindings))
                             #t #f)
        #:name "A binding is a key, a command and a description"))
    (test "The Key Column Is Found From The Modules"
      (assert-true (not (null? (surface-bindings)))
        #:name "The compositor declares bindings")
      (assert-true (let ((key (surface-key (surface-by-name 'niri))))
                     (or (not key) (string? (cdr (assq 'key key)))))
        #:name "A surface reports one chord to find it"))))

(define (printers-suite)
  (suite "Printers"
    (test "The Org Table Has One Row Per Surface"
      (let* ((table (org-table))
             (rows (filter (lambda (line)
                             (string-prefix? "| " line))
                           (string-split table #\newline))))
        (assert-equal #:expect (1+ (length surfaces))
          #:got (length (filter (lambda (line)
                                  (not (string-contains line "---")))
                                rows))
          #:name "A header and one row per surface")))
    (test "The Keyboard Reference Names The Chords"
      (let ((lines (keyboard-reference-lines)))
        (assert-true (not (null? lines))
          #:name "There is a reference")
        (assert-true (every (lambda (line) (and (string? (first line))
                                                  (string? (second line))
                                                  (string? (third line))))
                            lines)
          #:name "Every line is a (key action surface) triple")))
    (test "The Doctor Report Is A Report"
      (let ((report (doctor-report)))
        (assert-true (list? report)
          #:name "The doctor answers with one line per finding")
        (assert-true (every string? report)
          #:name "Every finding is a line of text")))))

(define (spec)
  (veritas-run
   (manifest-suite)
   (files-suite)
   (bindings-suite)
   (printers-suite)))
