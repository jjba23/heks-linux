;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux users): the declaration a machine writes once, the
;; account lookup that gives it a home, and the writer that lands a file with the
;; right owner.  The render itself is the audit's, tested there; this suite is
;; about the parts a second user adds.

;;; Code:

(define-module (veritas unit users-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux users)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux profile)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 ftw)
  #:export (spec))

(define (records-of dataset)
  "Return the records @code{validate-users} makes of @var{dataset}."
  (call-with-values (lambda () (validate-users dataset)) list))

(define (problems-of dataset)
  "Return the problems @code{validate-users} finds in @var{dataset}."
  (cadr (records-of dataset)))

(define (contains? haystack needle)
  "Whether any string in @var{haystack} contains @var{needle}."
  (not (eq? #f (any (lambda (line) (string-contains line needle)) haystack))))

(define (scratch-directory name)
  "Return a fresh directory under /tmp for @var{name}."
  (let ((path (format #f "/tmp/~a-~a" name (getpid))))
    (when (file-exists? path)
      (delete-file path))
    (mkdir path)
    path))

(define users-suite
  (suite "Users"
    (test "A Bare Name Is A User With No Settings"
      (let ((records (car (records-of '((joe))))))
        (assert-equal #:expect '((joe))
          #:got records
          #:name "The record is the name and an empty setting list")
        (assert-equal #:expect '()
          #:got (cdr (car records))
          #:name "A bare name declares no settings")))

    (test "Settings Are The Profile Vocabulary"
      (let ((records (car (records-of '((alice (profile . laptop)
                                                (palette . windows-xp)))))))
        (assert-equal #:expect '((alice (profile . laptop)
                                        (palette . windows-xp)))
          #:got records
          #:name "A profile and a parameter are kept in order"))
      (assert-true (contains? (problems-of '((alice (favourite-colour . blue))))
                              "unknown setting")
        #:name "A key outside the vocabulary is a problem"))

    (test "A Declaration Cannot Repeat Itself"
      (assert-true (contains? (problems-of '((joe) (joe)))
                              "declared twice")
        #:name "Two entries for one account are a problem")
      (assert-true (contains? (problems-of '((joe (palette . nord)
                                                     (palette . ayu-dark))))
                              "appears twice")
        #:name "One parameter twice is a problem"))

    (test "A Profile Must Be A Name"
      (assert-true (contains? (problems-of '((joe (profile . "laptop"))))
                              "profile must be a name")
        #:name "A string is not a profile name"))

    (test "A Declaration Is A List Of Entries"
      (assert-true (contains? (problems-of '((joe) . alice))
                              "list of names")
        #:name "A dotted list is refused rather than half-read")
      (assert-true (contains? (problems-of '(42)) "not a user name")
        #:name "A number is not a user"))

    (test "A Missing Declaration Is Empty, Not An Error"
      (let ((read (call-with-values
                    (lambda () (read-users #:path "/tmp/no-such-users-file.scm"))
                    list)))
        (assert-equal #:expect '(() ())
          #:got read
          #:name "No file means no declared users")))

    (test "The Declaration Is Read, Never Loaded"
      (let* ((path (format #f "/tmp/heks-users-spec-~a.scm" (getpid)))
             (port (open-output-file path)))
        (display "((joe (profile . laptop)))" port)
        (close-port port)
        (let ((read (call-with-values (lambda () (read-users #:path path)) list)))
          (assert-equal #:expect '((joe (profile . laptop)))
            #:got (car read)
            #:name "The data is what the file says"))
        (delete-file path)))

    (test "An Account Has A Home And An Owner"
      (let* ((name (or (current-user-name) "root"))
             (entry (passwd-entry name)))
        (assert-true (not (eq? #f entry))
          #:name "The account running the suite exists")
        (assert-true (number? (assoc-ref entry 'uid))
          #:name "The account has an owner")
        (assert-true (and (string? (assoc-ref entry 'home))
                          (string-prefix? "/" (assoc-ref entry 'home)))
          #:name "The account has an absolute home"))
      ;; A hermetic Guix container maps only the invoking account, so the
      ;; root-specific numbers are checked only where a root entry exists.
      (let ((root (passwd-entry "root")))
        (when root
          (assert-equal #:expect 0
            #:got (assoc-ref root 'uid)
            #:name "root is uid zero")
          (assert-equal #:expect "/root"
            #:got (assoc-ref root 'home)
            #:name "root's home is /root")))
      (assert-true (not (passwd-entry "heks-user-that-does-not-exist"))
        #:name "An unknown account answers #f"))

    (test "A Home Must Be A Home"
      (assert-equal #:expect "/home/alice"
        #:got (home-of '((home . "/home/alice")))
        #:name "An absolute home below / is usable")
      (assert-true (not (home-of '((home . "/"))))
        #:name "The root directory is not a home to write into")
      (assert-true (not (home-of '((home . "relative/home"))))
        #:name "A relative home is refused")
      (assert-true (not (home-of '((name . "alice"))))
        #:name "An entry without a home is refused"))

    (test "The Child Gets The Target Home And The Declaration"
      (let* ((entry '((name . "alice") (uid . 1001) (gid . 1001)
                      (home . "/home/alice")))
             (bindings (target-environment 'alice entry
                                           '((profile . laptop)
                                             (palette . windows-xp))
                                           "check" "/tmp/report" "/tmp/users.scm")))
        (assert-equal #:expect "/home/alice"
          #:got (assoc-ref bindings "HOME")
          #:name "HOME is the target's")
        (assert-equal #:expect "/home/alice/.config"
          #:got (assoc-ref bindings "XDG_CONFIG_HOME")
          #:name "Config follows the target home")
        (assert-equal #:expect "laptop"
          #:got (assoc-ref bindings "HEKS_PROFILE")
          #:name "The declared profile is named for the render")
        (assert-equal #:expect "((palette . windows-xp))"
          #:got (assoc-ref bindings "HEKS_USER_SETTINGS")
          #:name "The extra parameters travel as data")
        (assert-equal #:expect "alice"
          #:got (assoc-ref bindings "HEKS_TARGET_USER")
          #:name "Ownership is named, not guessed")))

    (test "A Target File Is Written With Its Mode"
      (let* ((home (scratch-directory "heks-users-home"))
             (target (format #f "~a/.config/example/settings.conf" home)))
        (assert-equal #:expect '(ok . #f)
          #:got (write-target-file! target 420 "hello\n" (getuid) (getgid)
                                    #:home home)
          #:name "The write reports success")
        (assert-true (file-exists? target)
          #:name "The file exists")
        (assert-equal #:expect "hello\n"
          #:got (call-with-input-file target get-string-all)
          #:name "The contents are the rendered ones")
        (assert-equal #:expect #o644
          #:got (stat:perms (stat target))
          #:name "The mode is the one the render asked for")
        (assert-true (eq? 'invalid
                          (car (write-target-file!
                                (format #f "~a/.config/example/broken.xml" home)
                                420 "<not-closed>" (getuid) (getgid)
                                #:home home)))
          #:name "A file its reader rejects is not written")
        (assert-true (not (file-exists? (format #f "~a/.config/example/broken.xml"
                                               home)))
          #:name "The rejected file leaves nothing behind")))

    (test "An Unknown Profile Is Reported, Not Applied"
      ;; The render would print a profile error three processes deep; the parent
      ;; asks first, so one bad line in users.scm is one line on stderr.
      (assert-true (not (assoc-ref (profile-candidates) 'no-such-profile))
        #:name "The named profile does not exist"))))

(define (spec)
  (veritas-run users-suite))
