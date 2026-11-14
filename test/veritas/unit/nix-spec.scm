;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux packages nix).
;;
;; The declaration is data and the installable is one string, so the tests are
;; about those two: an attribute that is not an attribute is refused before it
;; can reach a command line, the prefix is added in exactly one place, and the
;; union is sorted, duplicate-free and reads the category parameters at call
;; time.  Nothing here runs `nix': the suite is hermetic, and the profile is
;; someone's machine rather than the repository.

;;; Code:

(define-module (veritas unit nix-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux packages nix)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (attributes packages)
  (map nix-package-attribute packages))

(define (attributes-sorted? names)
  (or (null? names)
    (every (lambda (a b)
             (string<=? a b)) names
           (cdr names))))

(define (contains-attribute? names name)
  (not (eq? #f
            (member name names))))

(define (declaration-suite)
  (suite "Package Declarations"
    (test "An Attribute Becomes A Package"
      (assert-true (nix-package? (nix-package "nil"))
        #:name "A declaration produces a package record")
      (assert-equal #:expect "yaml-language-server"
        #:got (nix-package-attribute (nix-package
                                      "yaml-language-server"))
        #:name "The attribute is kept as written"))
    (test "Symbols And Strings Are Both Accepted"
      (assert-equal #:expect "nil"
        #:got (nix-package-attribute (nix-package 'nil))
        #:name "A symbol is coerced to the attribute string")
      (assert-true (string? (nix-package-attribute (nix-package
                                                    "hfsprogs")))
        #:name "Attributes are always strings"))
    (test "Dotted Attribute Paths Are Allowed"
      (assert-true (nix-attribute? "python3Packages.yaml")
        #:name "A set attribute is a valid attribute")
      (assert-true (nix-attribute? "libfoo-unstable")
        #:name "A hyphen is part of an attribute name"))
    (test "Malformed Attributes Are Rejected"
      (assert-equal #:expect #f
        #:got (nix-attribute? "")
        #:name "An empty attribute is not an attribute")
      (assert-equal #:expect #f
        #:got (nix-attribute? "-O2")
        #:name "An attribute may not look like an option")
      (assert-equal #:expect #f
        #:got (nix-attribute? "nixpkgs#nil")
        #:name "The installable prefix is not part of it")
      (assert-error (lambda ()
                      (nix-package "two words"))
        #:name "The constructor refuses whitespace")
      (assert-error (lambda ()
                      (nix-package "nil!"))
        #:name "The constructor refuses punctuation"))))

(define (installable-suite)
  (suite "Installables"
    (test "The Installable Is This Project's Flake"
      (assert-equal #:expect ".#nil"
        #:got (nix-installable (nix-package "nil"))
        #:name
        "An attribute becomes an attribute of the flake at the root")
      (assert-equal #:expect 1
        #:got (length (filter (lambda (character)
                                (char=? character #\#))
                              (string->list
                               (nix-installable
                                (nix-package "nil")))))
        #:name
        "The attribute carries no prefix of its own"))))

;;; What `nix profile list' prints, with an element from the registry and one
;;; from a checkout: that difference is the whole question the installer asks,
;;; because the first was pinned by nothing and has to be replaced from the
;;; flake at the root.
(define profile-listing
  (string-append "Name:               gifski\n"
                 "Flake attribute:    legacyPackages.x86_64-linux.gifski\n"
                 "Original flake URL: flake:nixpkgs\n"
                 "Locked flake URL:   https://example.org/nixpkgs.tar.zst\n"
                 "Store paths:        /nix/store/abc-gifski-1.34.0\n"
                 "\n"
                 "Name:               heks-toon\n"
                 "Flake attribute:    packages.x86_64-linux.heks-toon\n"
                 "Original flake URL: /nix/store/def-source\n"
                 "Locked flake URL:   git+https://example.org/heks-toon?rev=123\n"
                 "Store paths:        /nix/store/ghi-heks-toon-0.3.3\n"))

(define (profile-suite)
  (suite "The Profile"
    (test "Elements Are Read With Their Origin"
      (assert-equal #:expect '(("gifski" . "flake:nixpkgs")
                               ("heks-toon" . "/nix/store/def-source"))
        #:got (nix-profile-elements profile-listing)
        #:name
        "A name and the flake it came from, in the order the listing prints them")
      (assert-equal #:expect '()
        #:got (nix-profile-elements "")
        #:name "A profile that lists nothing answers with nothing"))

    (test "An Element Name Tells You Its Attribute"
      ;; `nix profile add' appends -1, -2 ... when the name is taken, so the
      ;; migration from the registry leaves a profile holding gifski and
      ;; gifski-1 at once.  Both provide gifski.
      (assert-equal #:expect "gifski"
        #:got (nix-profile-name "gifski-1")
        #:name "A numbered element is the attribute it numbers")
      (assert-equal #:expect "gifski"
        #:got (nix-profile-name "gifski")
        #:name "An unnumbered element is its own attribute")
      (assert-equal #:expect "heks-toon"
        #:got (nix-profile-name "heks-toon")
        #:name
        "A hyphen in the name itself is not a number and is left alone")
      (assert-equal #:expect "python3.11-foo"
        #:got (nix-profile-name "python3.11-foo")
        #:name "So is a digit that is not at the end")
      (assert-equal #:expect "nil"
        #:got (nix-profile-name "nil-12")
        #:name "A suffix of several digits is still a suffix"))

    (test "Copies Of One Package Are Found By Attribute"
      (let ((present '(("gifski" . "flake:nixpkgs")
                       ("gifski-1" . "/nix/store/abc-source")
                       ("heks-toon" . "/nix/store/def-source"))))
        (assert-equal #:expect
          '(("gifski" . "flake:nixpkgs")
            ("gifski-1" . "/nix/store/abc-source"))
          #:got (nix-profile-elements-of present "gifski")
          #:name "Both copies of gifski should come back, with their origins")
        (assert-equal #:expect '()
          #:got (nix-profile-elements-of present "undmg")
          #:name "A package the profile does not hold answers with nothing")))

    (test "The Bold A Coloured Listing Adds Is Not Part Of The Name"
      ;; `nix profile list' prints each element in bold whether or not its
      ;; output is a terminal, `NO_COLOR' and `TERM=dumb' do not stop it, and
      ;; there is no `--color' flag.  A name read with the escape still on it
      ;; matches no attribute, so the installer saw an empty profile and tried
      ;; to install everything again - which is the one thing `nix profile add'
      ;; refuses.
      (let ((escaped (string-append "Name:               \x1b[1mgifski\x1b[0m\n"
                                    "Original flake URL: flake:nixpkgs\n")))
        (assert-equal #:expect '(("gifski" . "flake:nixpkgs"))
          #:got (nix-profile-elements escaped)
          #:name
          "A bolded name should be read as the name, not as its decoration")
        (assert-equal #:expect "gifski"
          #:got (nix-profile-name (caar (nix-profile-elements escaped)))
          #:name "And it should be found by attribute like any other")))))

(define (catalog-suite)
  (suite "Catalog"
    (test "The Union Is Sorted And Duplicate-Free"
      (let* ((packages (heks-linux-nix))
             (names (attributes packages)))
        (assert-true (attributes-sorted? names)
          #:name "Packages are sorted by attribute")
        (assert-equal #:expect (length names)
          #:got (length (delete-duplicates names))
          #:name "No attribute is declared twice")))
    (test "Every Entry Is Installable"
      (assert-true (every (lambda (package)
                            (nix-attribute?
                             (nix-package-attribute package)))
                          (heks-linux-nix))
        #:name "Every attribute passes the form check"))
    (test "The Language Servers Are Declared"
      (let ((names (attributes (heks-linux-nix))))
        (assert-true (contains-attribute? names "yaml-language-server")
          #:name "YAML is covered where the distribution is not")
        (assert-true (contains-attribute? names "nil")
          #:name "Nix is covered")
        (assert-true (contains-attribute? names "marksman")
          #:name "Markdown is covered")
        (assert-true (contains-attribute?
                      names "vscode-langservers-extracted")
          #:name "JSON, CSS and HTML arrive in one package")))
    (test "The Disk-Image Readers Are Declared"
      (let ((names (attributes (heks-linux-nix))))
        (assert-true (contains-attribute? names "undmg")
          #:name "A .dmg can be unpacked")
        (assert-true (contains-attribute? names "hfsprogs")
          #:name "The HFS+ volume can be inspected")))))

(define (override-suite)
  (suite "Overrides"
    (test "Category Parameters Are Read At Call Time"
      (parameterize ((heks-linux-disk-image-nix '()))
        (assert-equal #:expect #f
          #:got (contains-attribute?
                 (attributes (heks-linux-nix)) "undmg")
          #:name "An emptied category is observed")))
    (test "An Extra Package Joins The Union"
      (parameterize ((heks-linux-language-server-nix
                      (cons (nix-package "zls")
                            (heks-linux-language-server-nix))))
        (assert-true (contains-attribute?
                      (attributes (heks-linux-nix)) "zls")
          #:name "A machine can add a server of its own")))))

(define (spec)
  (veritas-run (declaration-suite)
    (installable-suite)
    (profile-suite)
    (catalog-suite)
    (override-suite)))
