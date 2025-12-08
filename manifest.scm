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

(use-modules (guix packages)
             (gnu)
             (guix utils)
             (guix download)
             (gnu packages guile)
             (gnu packages nss)
             (gnu packages admin)
             (gnu packages gnupg)
             (gnu packages guile-xyz)
             (guix build-system guile)
             (gnu packages texinfo)
             (gnu packages rust-apps)
             ((guix licenses)
              #:prefix license:))

(packages->manifest (list guile-next
                          (specification->package "guile-json@4") texinfo
                          guile-documenta guile-ares-rs))

