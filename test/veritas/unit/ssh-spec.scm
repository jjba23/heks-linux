;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux ssh).  The module renders three files from one
;; table of hosts, so the tests read the rendered text the way ssh(1) and
;; systemd will: a Host keyword that starts in the first column, one
;; IdentityFile per host, and an agent socket that is named the same way in the
;; environment file and in the service.

;;; Code:

(define-module (veritas unit ssh-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux ssh)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (config-occurs? fragment)
  "Whether the rendered @file{~/.ssh/config} contains @var{fragment}."
  (not (eq? #f (string-contains (ssh-config) fragment))))

(define (host-blocks)
  "Return the rendered config split into Host blocks, without the header."
  (filter (lambda (line) (not (string-null? line)))
          (cdr (string-split (ssh-config) #\newline))))

(define (host-lines)
  "Return every rendered @code{Host} line."
  (filter (lambda (line) (string-prefix? "Host " line))
          (host-blocks)))

(define ssh-suite
  (suite "SSH Suite"

         (test "Keys Are Added To The Agent On First Use"
               ;; This single option is what makes a passphrase-protected key
               ;; cost one prompt instead of one per push.
               (assert-true (config-occurs? "AddKeysToAgent yes")
                            #:name
                            "The config should hand a used key to the agent"))

         (test "Every Host In The Table Is Rendered"
               (assert-equal #:expect (length (ssh-hosts))
                             #:got (length (host-lines))
                             #:name
                             "There should be exactly one Host line per entry")
               (assert-true (config-occurs? "Host personal.github.com")
                            #:name "The GitHub alias should be rendered")
               (assert-true (config-occurs? "Host codeberg.org")
                            #:name "The Codeberg host should be rendered")
               (assert-true (config-occurs? "Host wolk-jjba")
                            #:name "The wolk-jjba host should be rendered"))

         (test "Host Keywords Start In The First Column"
               (assert-true (not (config-occurs? "\n     Host "))
                            #:name
                            "Host is a block header, not an option: it must not be indented")
               (assert-true (config-occurs? "\n     HostName github.com")
                            #:name "The options under a Host block stay indented"))

         (test "Identities Are Declared Per Host"
               (assert-true (config-occurs? "IdentityFile ~/.ssh/personal_github")
                            #:name "GitHub should use the personal key")
               (assert-true (config-occurs? "IdentityFile ~/.ssh/gitlab_prive")
                            #:name "Codeberg should use its own key")
               (assert-true (config-occurs? "IdentitiesOnly yes")
                            #:name
                            "A host that pins one key should not offer the rest"))

         (test "Non-Default Ports Are Rendered"
               (assert-true (config-occurs? "Port 2323")
                            #:name "The wolk-jjba host listens on 2323")
               (assert-true (config-occurs? "Port 23")
                            #:name "The Storage Box listens on 23"))

         (test "The Environment File Names The Agent Socket"
               (let ((rendered (ssh-agent-environment)))
                 (assert-true (not (eq? #f
                                        (string-contains
                                         rendered
                                         (format #f "SSH_AUTH_SOCK=~a"
                                                 (ssh-agent-socket)))))
                              #:name
                              "The exported socket should be the one the agent listens on")))

         (test "The Provider Decides Socket And Unit Together"
               ;; The two must never disagree: an environment file pointing at
               ;; a socket no unit creates is a passphrase prompt waiting to
               ;; happen, and it looks like ssh being broken.
               (let ((provider (ssh-agent-provider)))
                 (dynamic-wind
                   (lambda () #t)
                   (lambda ()
                     (ssh-agent-provider 'agent)
                     (assert-equal #:expect "ssh-agent.service"
                                   #:got (ssh-agent-unit)
                                   #:name
                                   "Without a keyring agent the plain unit is used")
                     (assert-equal #:expect "${XDG_RUNTIME_DIR}/ssh-agent.socket"
                                   #:got (ssh-agent-socket)
                                   #:name
                                   "and the plain socket is exported")

                     (ssh-agent-provider 'gcr)
                     (assert-equal #:expect "gcr-ssh-agent.socket"
                                   #:got (ssh-agent-unit)
                                   #:name
                                   "With the keyring agent its socket unit is used")
                     (assert-equal #:expect "${XDG_RUNTIME_DIR}/gcr/ssh"
                                   #:got (ssh-agent-socket)
                                   #:name
                                   "and the keyring socket is exported"))
                   (lambda () (ssh-agent-provider provider)))))

         (test "The Plain Agent Unit Is A Detached Agent"
               (let ((unit (ssh-agent-service)))
                 (assert-true (not (eq? #f (string-contains unit "Type=simple")))
                              #:name "The agent should not fork into the background twice")
                 (assert-true (not (eq? #f
                                        (string-contains
                                         unit
                                         "ssh-agent -D -a %t/ssh-agent.socket")))
                              #:name
                              "The agent should listen on the runtime directory socket")
                 (assert-true (not (eq? #f
                                        (string-contains
                                         unit "WantedBy=default.target")))
                              #:name "The unit should be enabled with the user session")))))

(define (spec)
  (veritas-run ssh-suite))
