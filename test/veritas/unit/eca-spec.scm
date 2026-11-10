;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux eca).  The module renders the configuration the
;; Emacs client and the terminal client share, and names the release asset the
;; installer downloads.  Both are read here the way the two clients read them: a
;; provider whose key is a command rather than a secret, and an asset name that
;; follows the machine.  Nothing here downloads anything - the suite is
;; hermetic, and the release is a network away.

;;; Code:

(define-module (veritas unit eca-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux eca)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (config-occurs? fragment)
  "Whether the rendered @file{config.json} contains @var{fragment}."
  (not (eq? #f (string-contains (eca-serialize-config) fragment))))

(define eca-suite
  (suite "ECA Suite"

    (test "The Configuration Holds A Provider And Its Models"
      (assert-true (config-occurs? "\"deepseek\"")
        #:name "The DeepSeek provider is named")
      (assert-true (config-occurs? "\"api\": \"openai-chat\"")
        #:name "The provider speaks the OpenAI chat API")
      ;; The order matters: these are the models heks-emacs offers, under the
      ;; same names, so a chat started in either client lands on one of them.
      (for-each (lambda (model)
                  (assert-true (config-occurs? (format #f "\"~a\": {}" model))
                    #:name (format #f "~a is configured with its defaults" model)))
                (eca-deepseek-models)))

    (test "The Key Is A Command, Not A Secret"
      ;; The file is in a repository-rendered dotfile: a key written here would
      ;; be a key written into every backup of it.
      (assert-true (config-occurs? "${cmd:")
        #:name "The key is decrypted when a request is made")
      (assert-true (not (config-occurs? "sk-"))
        #:name "No API key is written into the file"))

    (test "The Asset Follows The Machine"
      (assert-equal #:expect "eca-cli-linux-amd64.tar.gz"
        #:got (eca-cli-asset "x86_64")
        #:name "An x86_64 machine takes the amd64 build")
      (assert-equal #:expect "eca-cli-linux-aarch64.tar.gz"
        #:got (eca-cli-asset "aarch64")
        #:name "An aarch64 machine takes the aarch64 build"))

    (test "The Release URL Names The Pinned Version"
      (assert-true (not (eq? #f (string-contains (eca-cli-url)
                                                 (eca-cli-version))))
        #:name "The URL carries the pinned version")
      (assert-true (not (eq? #f (string-contains (eca-cli-url)
                                                 (eca-cli-asset-name))))
        #:name "The URL carries the asset this machine installs"))))

(define (spec)
  (veritas-run eca-suite))
