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
;; Renders the two files under @file{~/.config/containers} that teach Podman
;; where to look for images and how much to trust them:
;;
;; - @file{registries.conf} lists the unqualified search registries, so
;;   @code{podman pull alpine} resolves without an explicit host name.
;; - @file{policy.json} is deliberately permissive
;;   (@code{insecureAcceptAnything}) because this is a developer workstation,
;;   not a hardened registry mirror.  Tighten it in your own
;;   @code{containers-settings.scm} override if that is wrong for you.
;;
;; Note that Podman itself is installed through the Zypper package list; this
;; module only owns the configuration.

;;; Code:

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

;; Name of the registry search-list file (Podman reads exactly this name).
(define containers-registries-config-filename
  (make-parameter "registries.conf"))

;; Directory receiving both files; defaults to @file{~/.config/containers}.
(define containers-config-dir
  (make-parameter (format #f "~a/.config/containers"
                          (or (getenv "HOME") "/tmp"))))

;; Name of the signature policy file.  Podman also honours
;; @file{/etc/containers/policy.json}; the user-level file takes precedence for
;; rootless containers.
(define containers-policy-config-filename
  (make-parameter "policy.json"))

(define (install-containers-registries-config)
  "Write the unqualified search registries to @code{containers-config-dir}.

Unlike the policy file this one is not derived from user settings, so it has no
local override to load."
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
  "Write a permissive Podman signature policy to @code{containers-config-dir}.

Local overrides are read from
@code{$XDG_CONFIG_HOME/heks-linux/containers-settings.scm} first."
  (log-info s "Installing Containers Policy configuration")
  (load-local-overrides '(heks-linux containers) 'containers-settings)
  (install-config-file! #:name (containers-policy-config-filename)
                        #:dir (containers-config-dir)
                        #:contents (scm->json-string `((default . #(((type . insecureAcceptAnything)))))))
  (log-success s "Installed Containers Policy configuration"))
