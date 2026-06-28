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

(use-modules (guix packages)
             (gnu)
             (guix utils)
             (guix download)
             (gnu packages guile)
             (gnu packages nss)
             (gnu packages admin)
             (gnu packages gnupg)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (guix build-system guile)
             (gnu packages texinfo)
             (gnu packages emacs)
             (gnu packages linux)
             (gnu packages base)
             (gnu packages rust-apps)
             ((guix licenses)
              #:prefix license:))

(packages->manifest (list guile-3.0-latest
                          guile-json-4
                          texinfo
                          emacs-no-x
                          coreutils
                          guile-gcrypt
                          guile-veritas
                          guile-documenta
                          guile-scriba
                          glibc-locales
                          guile-ares-rs))
