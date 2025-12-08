;;; hekserij

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; hekserij is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; hekserij is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with hekserij.  If not, see <https://www.gnu.org/licenses/>.

(define-module (hekserij packages dnfs)
  #:declarative? #t
  #:use-module (hekserij prelude)
  #:use-module (ice-9 string-fun)
  #:export (hekserij-dnfs hekserij-other-dnfs
                          hekserij-graphics-dnfs
                          hekserij-power-user-dnfs
                          hekserij-lib-dnfs
                          hekserij-net-dnfs
                          install-dnfs))

(define hekserij-graphics-dnfs
  '(gimp inkscape))

(define hekserij-other-dnfs
  '())

(define hekserij-power-user-dnfs
  '(alacritty emacs-pgtk niri rg rofi rofimoji))

(define hekserij-dev-dnfs
  '(direnv gh just shfmt ShellCheck))

(define hekserij-lib-dnfs
  '())

(define hekserij-dict-dnfs
  '(aspell aspell-ca
           aspell-en
           aspell-es
           aspell-nl
           aspell-pt-pt
           enchant
           enchant-aspell))

(define hekserij-net-dnfs
  '(wireshark openvpn darkhttpd))

(define hekserij-dnfs
  (append hekserij-graphics-dnfs
          hekserij-other-dnfs
          hekserij-power-user-dnfs
          hekserij-dev-dnfs
          hekserij-lib-dnfs
          hekserij-dict-dnfs
          hekserij-net-dnfs))

(define (install-dnfs)
  (for-each (lambda (pkg)
              (let* ((cmd (format #f "sudo dnf install -y ~a" pkg)))
                (display (format #f "\nExecuting command: ~a\n" cmd))
                (syscall cmd))) hekserij-dnfs))
