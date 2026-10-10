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
;; Unit tests for (heks-linux dconf): the nested setting flattener and the
;; writer script contents.

;;; Code:

(define-module (veritas unit dconf-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux dconf)
  #:use-module (heks-linux user-settings)
  #:export (spec))

;; A small stand-in for a generated dconf settings tree.
(define dconf-fixture
  (list (list "/org/gnome/desktop/interface"
              (cons 'gtk-key-theme "'Emacs'")
              (cons 'cursor-size 24)
              (cons 'enable-animations 'true))))

(define expected-dconf-writer-commands
  '("echo \"/org/gnome/desktop/interface/gtk-key-theme --> 'Emacs'\" && dconf write \"/org/gnome/desktop/interface/gtk-key-theme\" \"'Emacs'\""
    "echo \"/org/gnome/desktop/interface/cursor-size --> 24\" && dconf write \"/org/gnome/desktop/interface/cursor-size\" \"24\""
    "echo \"/org/gnome/desktop/interface/enable-animations --> true\" && dconf write \"/org/gnome/desktop/interface/enable-animations\" \"true\""))

(define (render-dconf-settings)
  "Render every Heks Linux dconf key as one newline separated string."
  (string-join (mk-nested-dconf-writer-commands (heks-linux-dconf-settings))
               "\n"))

(define (rendered? fragment)
  "Whether @var{fragment} appears in the rendered dconf writer commands."
  (not (eq? #f (string-contains (render-dconf-settings) fragment))))

(define dconf-test-suite
  (suite "dconf test suite"
         (test "mk-nested-dconf-writer-commands"
               (assert-equal #:got (mk-nested-dconf-writer-commands
                                    dconf-fixture)
                             #:expect expected-dconf-writer-commands
                             #:name
                             "Nested settings should flatten into dconf write commands"))

         (test "Heks settings are namespaced and complete"
               (assert-true (rendered? "\"/heks-linux/lang\"")
                            #:name
                            "The language should be written under /heks-linux")
               (assert-true (rendered? "\"/heks-linux/palette\"")
                            #:name "The palette should be exported to dconf")
               (assert-true (rendered? "\"/heks-linux/mono-font\"")
                            #:name "The mono font should be exported to dconf"))

         (test "caps-to-ctrl follows its parameter"
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-caps-to-ctrl? #f))
                                            (render-dconf-settings))
                                          "/heks-linux/caps-to-ctrl\" \"false\"")))
                            #:name
                            "Disabling caps-to-ctrl must write false, not a hardcoded true")
               (assert-true (not (eq? #f (string-contains
                                          (parameterize ((heks-linux-caps-to-ctrl? #t))
                                            (render-dconf-settings))
                                          "/heks-linux/caps-to-ctrl\" \"true\"")))
                            #:name
                            "Enabling caps-to-ctrl must write true"))))

(define (spec)
  (veritas-run dconf-test-suite))
