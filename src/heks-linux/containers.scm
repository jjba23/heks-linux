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

(define-module (heks-linux containers)
  #:declarative? #t
  #:use-module (json)
  #:export (install-containers-registries-config
            install-containers-policy-config))

(define (install-containers-registries-config)
  (with-output-to-file (format #f "~a/.config/containers/registries.conf"
                               (getenv "HOME"))
    (lambda ()
      (display "
unqualified-search-registries = [
       'docker.io',
       'registry.fedoraproject.org',
       'registry.access.redhat.com',
       'registry.centos.org'
]"))))

(define (install-containers-policy-config)
  (with-output-to-file (format #f "~a/.config/containers/policy.json"
                               (getenv "HOME"))
    (lambda ()
      (display (scm->json-string `((default . #(((type . insecureAcceptAnything))))))))))

