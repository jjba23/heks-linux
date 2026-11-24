;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The pins a project declares, in one table, with one way to move them.
;;
;; A repository that is careful about versions keeps the same fact in four
;; formats.  Guix writes a channel's commit into @file{channels.scm}; Nix writes
;; an input's revision into @file{flake.lock}; Maven writes a property into
;; @file{pom.xml}; and a manifest can pin a package with the whole point being
;; that the version is written down.  They are all the same question - which
;; release is this repository built against - and each one has its own way of
;; answering it, usually a good one, which is why they stay separate.
;;
;; What is missing is the view across them: which pins has this checkout
;; outgrown, and what would moving them do?  So this module reads the four
;; formats as *text* - never evaluating a channels file, never importing a flake
;; - and asks the network only when it is asked to.  An update rewrites the one
;; string the format keeps its pin in, and nothing else; `--check' is the same
;; comparison with no write at all, which is what makes it safe in a pipeline.
;;
;; The bounded claim: this reads pins, it does not solve them.  A Maven property
;; that is not a plain version (`${revision}'), a flake input that is a path, or a
;; channel held to a tag rather than a branch is reported with an unknown latest
;; rather than guessed at.  `nix flake update' is the one updater delegated,
;; because the lock file's own resolution is the only correct answer for it.
;;
;;; Code:

(define-module (heks-linux pins)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:use-module (heks-linux prelude)
  #:export (pin pin?
                pin-kind
                pin-file
                pin-name
                pin-current
                pin-latest
                pin-locator
                all-matches
                property-table
                pin-status
                discover-pins
                channel-pins
                flake-pins
                maven-pins
                manifest-pins
                refresh-pins!
                apply-pin!
                pins-report
                pins-json
                main))

(define-record-type <pin>
  (%pin kind file name current latest locator)
  pin?
  (kind pin-kind)
  (file pin-file)
  (name pin-name)
  (current pin-current)
  (latest pin-latest)
  (locator pin-locator))

(define* (pin kind file name current #:key (latest #f) (locator #f))
  "Construct one pin: @var{kind}, in @var{file}, called @var{name}.

@var{locator} is whatever the updater needs to rewrite that one pin - a channel's
name, an artifact's coordinates, a property key - and is opaque to every other
part of this module."
  (%pin kind file name current latest locator))

(define (pin-status pin)
  "Return @code{'current}, @code{'behind} or @code{'unknown} for @var{pin}."
  (cond
    [(not (pin-latest pin)) 'unknown]
    [(string=? (pin-latest pin) (pin-current pin)) 'current]
    [else 'behind]))

;;; ====== Guix channels ======

(define (strip-quote value)
  "Return @var{value} without a @code{quote} wrapper, if it has one."
  (if (and (pair? value) (eq? 'quote (car value)) (pair? (cdr value)))
    (cadr value)
    value))

(define (channel-field form key)
  "Return @var{key}'s value in the @code{channel} @var{form}, or @code{#f}."
  (let ((pair (assq key (cdr form))))
    (and pair (cadr pair))))

(define (channel-pins file)
  "Return the Guix channel pins @var{file} declares.

The file is read as data, never evaluated: what a check needs is where a channel
lives and which commit it is held at, and @code{channel} means nothing outside a
Guix process."
  (if (not (file-exists? file))
    '()
    (catch #t
           (lambda ()
             (map (lambda (form)
                    (let ((url (channel-field form 'url))
                          (branch (channel-field form 'branch))
                          (commit (channel-field form 'commit)))
                      (pin 'guix-channel
                           file
                           (symbol->string (strip-quote (channel-field form 'name)))
                           commit
                           #:locator (list url branch))))
                  (filter (lambda (form)
                            (and (pair? form) (eq? 'channel (car form))))
                          (call-with-input-file file read))))
           (lambda (key . args)
             (format (current-error-port)
                     "heks-pins: ~a could not be read as a channels file (~a)~%"
                     file key)
             '()))))

(define (git-output args)
  "Run @command{git} with @var{args} and return its stdout, or @code{#f}."
  (catch #t
         (lambda ()
           (let ((port (apply open-pipe* OPEN_READ "git" args)))
             (let ((text (get-string-all port)))
               (close-pipe port)
               text)))
         (lambda _ #f)))

(define (remote-tip url branch)
  "Return the commit @var{url}'s @var{branch} points at, or @code{#f}.

`git ls-remote' is what the channels file's own commentary names for choosing a
pin, and it reads the forge without cloning it.  Only the line whose ref is
exactly the branch counts: the branch argument matches the tail of a ref name, so
a mirror's copy of it answers too."
  (let* ((ref (format #f "refs/heads/~a" branch))
         (listing (git-output (list "ls-remote" url ref))))
    (and listing
      (let ((line (find (lambda (line)
                          (string-suffix? (format #f "\t~a" ref) line))
                        (string-split listing #\newline))))
        (and line (car (string-split line #\tab)))))))

;;; ====== Nix flake inputs ======

(define (flake-pins file)
  "Return the locked inputs of the flake at @var{file}, as pins.

A node is a pin when it has a @code{locked} value with a @code{rev}: the root
node does not, and a node that points at a path has nothing to move.  The latest
revision is left unknown on purpose - only @command{nix flake update} can resolve
what an input's branch points at - and the status says so."
  (if (not (file-exists? file))
    '()
    (catch #t
           (lambda ()
             (let* ((document (call-with-input-file file json->scm))
                    (nodes (assoc-ref document "nodes")))
               (if (not (and (list? nodes) (pair? nodes)))
                 '()
                 (filter-map (lambda (node)
                               (let ((locked (assoc-ref (cdr node) "locked")))
                                 (and (list? locked)
                                   (assoc-ref locked "rev")
                                   (pin 'nix-input
                                        file
                                        (car node)
                                        (assoc-ref locked "rev")
                                        #:locator (car node)))))
                             nodes))))
           (lambda (key . args)
             (format (current-error-port)
                     "heks-pins: ~a could not be read as a flake lock (~a)~%"
                     file key)
             '()))))

;;; ====== Maven ======

(define (all-matches pattern text)
  "Return every submatch vector @var{pattern} finds in @var{text}."
  (let loop ((start 0) (found '()))
    (let ((match (regexp-exec pattern text start)))
      (if (not match)
        (reverse found)
        (loop (match:end match 0) (cons match found))))))

(define (text-between text open close)
  "Return every piece of @var{text} between @var{open} and @var{close}, in order.

A pom is XML, and a reader that needs three tags out of it should not need an XML
library: the tags are literal, and reading them by hand keeps the reader total -
a malformed file answers fewer pins instead of raising from inside a report."
  (let loop ((start 0) (found '()))
    (let ((from (string-contains text open start)))
      (if (not from)
        (reverse found)
        (let* ((begin (+ from (string-length open)))
               (to (string-contains text close begin)))
          (if (not to)
            (reverse found)
            (loop (+ to (string-length close))
                  (cons (substring text begin to) found))))))))

(define (tag-value text tag)
  "Return the text of the first @code{<TAG>} in @var{text}, trimmed, or #f."
  (let ((values (text-between text (format #f "<~a>" tag)
                              (format #f "</~a>" tag))))
    (and (pair? values) (string-trim-both (car values)))))

(define (property-table pom)
  "Return the @code{<properties>} of @var{pom} as an alist of strings."
  (let ((block (text-between pom "<properties>" "</properties>")))
    (if (null? block)
      '()
      (map (lambda (match)
             (cons (match:substring match 1)
                   (string-trim-both (match:substring match 2))))
           (all-matches
            (make-regexp
             "<([A-Za-z0-9._-]+)>[[:space:]]*([^<[:space:]]+)[[:space:]]*</\\1>")
            (car block))))))

(define (maven-pins file)
  "Return the dependency and property pins @var{file} declares.

Only versions written as literal text are pins.  A version that is
@code{${...}} is resolved through the file's own properties when it can be, and
skipped when it cannot: the property is the pin, and reporting both would be
reporting one fact twice."
  (if (not (file-exists? file))
    '()
    (catch #t
           (lambda ()
             (let* ((pom (call-with-input-file file get-string-all))
                    (properties (property-table pom))
                    (dependencies
                     (filter-map
                      (lambda (block)
                        (let* ((group (tag-value block "groupId"))
                               (artifact (tag-value block "artifactId"))
                               (raw (tag-value block "version"))
                               (resolved
                                (and raw
                                  (if (string-prefix? "${" raw)
                                    (let* ((key (substring raw 2
                                                           (- (string-length raw) 1)))
                                           (found (assoc key properties)))
                                      (and found (cdr found)))
                                    raw))))
                          (and group artifact resolved
                            (pin 'maven file
                                 (format #f "~a:~a" group artifact)
                                 resolved
                                 #:locator (list group artifact)))))
                      (text-between pom "<dependency>" "</dependency>"))))
               (append dependencies
                       (map (lambda (property)
                              (pin 'maven-property file (car property) (cdr property)
                                   #:locator (car property)))
                            properties))))
           (lambda (key . args)
             (format (current-error-port)
                     "heks-pins: ~a could not be read as a pom (~a)~%"
                     file key)
             '()))))

;;; ====== Manifests that write a version down ======

(define (manifest-pins file)
  "Return the @code{name@@version} pins a Guix manifest carries.

A manifest usually pins through its channel rather than through a version, and
then it has no pins - which is why this reports nothing for this repository.  A
manifest that does write @code{guile-veritas@@0.11.0} as a string is a project
that chose a release, and that string is a pin the table should show."
  (if (not (file-exists? file))
    '()
    (catch #t
           (lambda ()
             (let* ((text (call-with-input-file file get-string-all))
                    (pattern (make-regexp
                              "\"([A-Za-z0-9][A-Za-z0-9+._-]*)@([0-9][A-Za-z0-9+._-]*)\"")))
               (map (lambda (match)
                      (pin 'scm-version file
                           (match:substring match 1)
                           (match:substring match 2)
                           #:locator (match:substring match 0)))
                    (all-matches pattern text))))
           (lambda _ '()))))

;;; ====== Discovery ======

(define (subdirectories directory)
  "Return the directories directly below @var{directory}, by name."
  (catch #t
         (lambda ()
           (filter (lambda (name)
                     (let ((path (format #f "~a/~a" directory name)))
                       (and (not (string-prefix? "." name))
                         (file-exists? path)
                         (eq? 'directory (stat:type (stat path))))))
                   (scandir directory)))
         (lambda _ '())))

(define* (discover-pins directory #:key (only #f))
  "Return every pin the project in @var{directory} declares.

Four formats are read: the root @file{channels.scm}, @file{flake.lock} and
@file{manifest.scm}, and every @file{pom.xml} at the root or one level down - the
shape of a Maven reactor.  @var{only} filters by kind when the caller asked for
one family."
  (let* ((pins (append (channel-pins (format #f "~a/channels.scm" directory))
                       (flake-pins (format #f "~a/flake.lock" directory))
                       (manifest-pins (format #f "~a/manifest.scm" directory))
                       (maven-pins (format #f "~a/pom.xml" directory))
                       (append-map (lambda (name)
                                     (maven-pins
                                      (format #f "~a/~a/pom.xml" directory name)))
                                   (subdirectories directory)))))
    (if only
      (filter (lambda (pin)
                (memq (pin-kind pin) only))
              pins)
      pins)))

;;; ====== Asking the network ======

(define (network-enabled?)
  (not (getenv "HEKS_PINS_OFFLINE")))

(define (curl-text url)
  "Return @var{url}'s body, or @code{#f} when it cannot be fetched."
  (catch #t
         (lambda ()
           (let ((port (open-pipe* OPEN_READ "curl" "-fsSL" "--max-time" "15"
                                   url)))
             (let ((text (get-string-all port)))
               (close-pipe port)
               text)))
         (lambda _ #f)))

(define (maven-latest group artifact)
  "Return the newest release Maven Central publishes for @var{group}:@var{artifact}."
  (let* ((path (string-join (string-split group #\.) "/"))
         (url (format #f
                      "https://repo1.maven.org/maven2/~a/~a/maven-metadata.xml"
                      path artifact))
         (metadata (and (network-enabled?) (curl-text url))))
    (and metadata
      (let ((match (regexp-exec (make-regexp
                                 "<(latest|release)>[[:space:]]*([^<]+)[[:space:]]*</\\1>")
                                metadata)))
        (and match (string-trim-both (match:substring match 2)))))))

(define (refresh-pins! pins)
  "Ask each source what it currently offers, and return @var{pins} with answers.

Only the sources that can answer are asked: a Maven artifact through Maven
Central's metadata, a Guix channel through @command{git ls-remote}.  A Nix input
has no cheap answer and a manifest pin has no registry behind it, so they stay
unknown rather than being guessed."
  (map (lambda (pin)
         (let ((latest
                (case (pin-kind pin)
                  [(guix-channel)
                   (apply remote-tip (pin-locator pin))]
                  [(maven maven-property)
                   (let ((locator (pin-locator pin)))
                     (if (and (list? locator) (= (length locator) 2))
                       (maven-latest (first locator) (second locator))
                       #f))]
                  [else #f])))
           (%pin (pin-kind pin)
                 (pin-file pin)
                 (pin-name pin)
                 (pin-current pin)
                 latest
                 (pin-locator pin))))
       pins))

;;; ====== Writing one pin ======

(define (read-text file)
  (call-with-input-file file
                        (lambda (port)
                          (get-string-all port))))

(define (write-text file text)
  "Write @var{text} to @var{file}, atomically and beside it."
  (let* ((port (mkstemp! (string-append file ".XXXXXX")))
         (temporary (port-filename port)))
    (set-port-encoding! port "UTF-8")
    (display text port)
    (close-port port)
    (chmod temporary #o644)
    (rename-file temporary file)))

(define (replace-channel-commit text name commit)
  "Return @var{text} with @var{name}'s channel commit replaced by @var{commit}.

The commit is found *after* the channel's name rather than by searching for the
old string: two channels may carry the same commit, and replacing the first one
would move the wrong pin."
  (let* ((name-match (regexp-exec (make-regexp
                                   (format #f "\\(name '~a\\)" (regexp-quote name)))
                                  text))
         (start (and name-match (match:end name-match 0)))
         (commit-match (and start
                         (regexp-exec (make-regexp "\\(commit[[:space:]]+\"([0-9a-f]+)\"")
                                      text start))))
    (if (not commit-match)
      #f
      (string-append (substring text 0 (match:start commit-match 1))
                     commit
                     (substring text (match:end commit-match 1))))))

(define (replace-next-version text marker version)
  "Replace the @code{<version>} following @var{marker} in @var{text}."
  (let* ((marker-match (regexp-exec (make-regexp (regexp-quote marker)) text))
         (start (and marker-match (match:end marker-match 0)))
         (version-match (and start
                          (regexp-exec
                           (make-regexp "<version>[[:space:]]*([^<]+?)[[:space:]]*</version>")
                           text start))))
    (if (not version-match)
      #f
      (string-append (substring text 0 (match:start version-match 1))
                     version
                     (substring text (match:end version-match 1))))))

(define (replace-literal text old new)
  "Return @var{text} with its first literal @var{old} replaced by @var{new}."
  (let ((index (string-contains text old)))
    (and index
      (string-append (substring text 0 index)
                     new
                     (substring text (+ index (string-length old)))))))

(define (update-flake-input! pin)
  "Move a Nix flake input with Nix's own resolver; return whether it moved.

The lock file holds a revision, a nar hash and a last-modified stamp, and only
`nix flake update' can write all three consistently.  Rewriting the revision by
hand would leave the other two lying, which is worse than not updating at all."
  (let* ((directory (dirname (pin-file pin)))
         (previous (getcwd)))
    (dynamic-wind
      (lambda () (chdir directory))
      (lambda ()
        (let ((status (system* "nix" "flake" "update" (pin-locator pin))))
          (and status (zero? status) #t)))
      (lambda () (chdir previous)))))

(define (updated-pin-text pin latest)
  "Return @var{pin}'s file with its own string moved to @var{latest}, or #f.

One string is rewritten, chosen by the format: a channel's commit after its name,
a Maven artifact's version after its id, a property's value, or the literal
`name@version' a manifest wrote down."
  (let ((text (read-text (pin-file pin))))
    (case (pin-kind pin)
      [(guix-channel)
       (replace-channel-commit text (pin-name pin) latest)]
      [(maven)
       (let ((locator (pin-locator pin)))
         (replace-next-version text
                               (format #f "<artifactId>~a</artifactId>"
                                       (second locator))
                               latest))]
      [(maven-property)
       (replace-literal text
                        (format #f "<~a>~a</~a>"
                                (pin-name pin) (pin-current pin)
                                (pin-name pin))
                        (format #f "<~a>~a</~a>"
                                (pin-name pin) latest (pin-name pin)))]
      [(scm-version)
       (replace-literal text
                        (format #f "~a@~a" (pin-name pin) (pin-current pin))
                        (format #f "~a@~a" (pin-name pin) latest))]
      [else #f])))

(define (apply-pin! pin)
  "Move @var{pin} to its latest value in its own file; return @code{#t} on success."
  (let ((latest (pin-latest pin)))
    (cond
      [(or (not latest) (eq? (pin-status pin) 'current)) #f]
      [(eq? (pin-kind pin) 'nix-input) (update-flake-input! pin)]
      [else
        (let ((updated (updated-pin-text pin latest)))
          (and updated
            (not (string=? updated (read-text (pin-file pin))))
            (begin
              (write-text (pin-file pin) updated)
              #t)))])))

;;; ====== The views ======

(define (relativize path directory)
  (if (string-prefix? (format #f "~a/" directory) path)
    (substring path (+ 1 (string-length directory)))
    path))

(define* (pins-report pins #:key (directory (getcwd)) (port (current-output-port))
                      (verbose? #f))
  "Print the pin table and return whether every pin is current or unknowable.

A pin is @code{behind} when the source has a newer answer, @code{current} when
they agree, and @code{unknown} when nothing cheap can say - which is a fact worth
printing rather than a failure."
  (let ((behind (filter (lambda (pin)
                          (eq? (pin-status pin) 'behind))
                        pins)))
    (format port "~a ~a ~a ~a ~a~%"
            (string-pad-right "FILE" 14)
            (string-pad-right "KIND" 14)
            (string-pad-right "NAME" 28)
            (string-pad-right "PINNED" 14)
            (string-pad-right "LATEST" 14)
            "STATUS")
    (for-each (lambda (pin)
                (let ((current (pin-current pin))
                      (latest (or (pin-latest pin) "-")))
                  (format port "~a ~a ~a ~a ~a~%"
                          (string-pad-right
                           (relativize (pin-file pin) directory) 14)
                          (string-pad-right
                           (symbol->string (pin-kind pin)) 14)
                          (string-pad-right (pin-name pin) 28)
                          (string-pad-right
                           (if (> (string-length current) 12)
                             (substring current 0 12)
                             current)
                           14)
                          (string-pad-right
                           (if (> (string-length latest) 12)
                             (substring latest 0 12)
                             latest)
                           14)
                          (case (pin-status pin)
                            [(behind) "behind"]
                            [(current) "up to date"]
                            [else "unknown"]))))
              pins)
    (format port "~%heks-pins: ~a pin(s), ~a behind~%"
            (length pins)
            (length behind))
    (if (null? behind)
      #t
      (begin
        (format port
                "heks-pins: run `heks-pins --update' to move them~%")
        #f))))

(define (pins-json pins)
  "Return the pin table as JSON."
  (to-json
   `((version . 1)
     (pins . ,(map (lambda (pin)
                     `((kind . ,(symbol->string (pin-kind pin)))
                       (file . ,(pin-file pin))
                       (name . ,(pin-name pin))
                       (current . ,(pin-current pin))
                       (latest . ,(or (pin-latest pin) #f))
                       (status . ,(symbol->string (pin-status pin)))))
                   pins)))))

(define (usage port)
  (format port "heks-pins - the versions a project pins, in one table

Usage: heks-pins [DIRECTORY] [OPTIONS]

  --check       Report what is behind and exit 1 when something is
  --update      Move every pin whose source answered, then report
  --only KINDS  Comma-separated: guix-channel, nix-input, maven,
                maven-property, scm-version
  --offline     Do not ask the network; every latest is unknown
  --json        Print the table as JSON
  -h, --help    This text

Exit status: 0 when nothing is behind (or after a successful update), 1 when a
check found a pin behind, 2 for a usage error.
"))

(define (parse-kinds value)
  (map string->symbol (string-split value #\,)))

(define (main args)
  "Entry point for @command{heks-pins}; @var{args} is @code{(command-line)}."
  (let loop ((remaining (cdr args))
             (directory #f)
             (check? #f)
             (update? #f)
             (only #f))
    (cond
      [(null? remaining)
       (let* ((dir (or directory (getcwd)))
              (discovered (discover-pins dir #:only only))
              (pins (if (or check? update?) (refresh-pins! discovered)
                      discovered)))
         (cond
           [update?
             (let ((moved (filter apply-pin! pins)))
               (format #t "heks-pins: moved ~a pin(s)~%" (length moved))
               ;; After a move the table is read again, so the report says what
               ;; is true now rather than what was true before the write.
               (exit (if (pins-report (refresh-pins!
                                       (discover-pins dir #:only only)))
                       0
                       1)))]
           [check?
             (exit (if (pins-report pins #:directory dir) 0 1))]
           [else
             (let ((pins (if (network-enabled?)
                           (refresh-pins! discovered)
                           discovered)))
               (pins-report pins #:directory dir)
               (exit 0))]))]
      [(member (car remaining) '("-h" "--help"))
       (usage (current-output-port))
       (exit 0)]
      [(string=? (car remaining) "--check")
       (loop (cdr remaining) directory #t update? only)]
      [(string=? (car remaining) "--update")
       (loop (cdr remaining) directory check? #t only)]
      [(string=? (car remaining) "--offline")
       (setenv "HEKS_PINS_OFFLINE" "1")
       (loop (cdr remaining) directory check? update? only)]
      [(string=? (car remaining) "--json")
       (let* ((dir (or directory (getcwd)))
              (pins (refresh-pins! (discover-pins dir #:only only))))
         (display (pins-json pins))
         (newline)
         (exit 0))]
      [(string=? (car remaining) "--only")
       (if (null? (cdr remaining))
         (begin
           (format (current-error-port) "heks-pins: --only needs a value~%")
           (exit 2))
         (loop (cddr remaining) directory check? update?
               (parse-kinds (cadr remaining))))]
      [else
        (if (and (not directory) (file-exists? (car remaining)))
          (loop (cdr remaining) (car remaining) check? update? only)
          (begin
            (format (current-error-port) "heks-pins: unknown option ~a~%"
                    (car remaining))
            (usage (current-error-port))
            (exit 2)))])))

;;; pins.scm ends here
