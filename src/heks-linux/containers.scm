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
  #:use-module (heks-linux prelude)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (install-containers-registries-config
            install-containers-policy-config containers-config-dir
            containers-registries-config-filename
            containers-policy-config-filename))

(define s
  (scriba-auto-logger))

(define containers-registries-config-filename
  (make-parameter "registries.conf"))

(define containers-config-dir
  (make-parameter (format #f "~a/.config/containers"
                          (or (getenv "HOME") "/tmp"))))

(define containers-policy-config-filename
  (make-parameter "policy.json"))

(define (install-containers-registries-config)
  (log-info s "Installing Containers Registries configuration")

  (install-config-file! #:name (containers-registries-config-filename)
                        #:dir (containers-config-dir)
                        #:contents "
unqualified-search-registries = [
       'docker.io',
       'registry.fedoraproject.org',
       'registry.access.redhat.com',
       'registry.centos.org'
]")

  (log-success s "Installed Containers Registries configuration"))

(define (install-containers-policy-config)
  (log-info s "Installing Containers Policy configuration")
  (load-local-overrides '(heks-linux containers) 'containers-settings)
  (install-config-file! #:name (containers-policy-config-filename)
                        #:dir (containers-config-dir)
                        #:contents (scm->json-string `((default . #(((type . insecureAcceptAnything)))))))
  (log-success s "Installed Containers Policy configuration"))
