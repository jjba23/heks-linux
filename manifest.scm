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

;; Commentary:
;;
;; The development shell: Guile, the test suite and the documentation
;; tooling.  The collection's packages come from the jointhefreeworld
;; channel pinned in channels.scm, not from copies defined here, so a
;; version is bumped once, in the channel, and every `guix shell -m
;; manifest.scm' and `guix time-machine --channels=channels.scm' run picks
;; it up.
;;
;; The channel modules are imported with a prefix because Guix itself still
;; carries older guile-veritas, guile-scriba and maak bindings; the prefix
;; makes it explicit which release the shell gets instead of leaving it to
;; import order.

(use-modules (guix packages)
             (guix profiles)
             (gnu packages base)
             (gnu packages emacs)
             (gnu packages gnupg)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages texinfo)
             ((jointhefreeworld packages guile)
              #:prefix jtf:)
             ((jointhefreeworld packages applications)
              #:prefix jtf:))

(packages->manifest (list guile-3.0-latest
                          guile-json-4
                          texinfo
                          emacs-no-x
                          coreutils
                          guile-gcrypt
                          jtf:guile-veritas
                          guile-documenta
                          jtf:guile-scriba
                          glibc-locales
                          jtf:maak
                          guile-ares-rs))
