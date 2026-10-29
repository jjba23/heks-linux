;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux image).
;;
;; The thing under test is a description of a machine nobody has booted yet, so
;; what can be checked is that it is internally consistent: that the packages
;; name a session rather than a pile of programs, that the account the image
;; creates is the account its build script logs in, that the first boot and the
;; unit that triggers it agree about where their marker lives, and that the XML
;; KIWI is handed is well formed.  These are the mistakes that cost a build.

;; IMPORTANT contributor note:
;;
;; `assert-true' and friends are *pure constructors*: they return a closure
;; that the veritas runner later applies to a context.  When such a call sits
;; in a non-final position of a body (typically inside a `let'), its return
;; value is unused and Guile's optimizer deletes the call entirely, so the
;; assertion silently never runs.  Always pass assertions as direct arguments
;; to `test', as this file does.

;;; Code:

(define-module (veritas unit image-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux image)
  #:use-module (heks-linux user-settings)
  #:use-module (heks-linux packages zypper)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 regex)
  #:export (spec))

;; ===========================================
;; Reading the description back
;; ===========================================

(define (child-of element name)
  "Return the first child of @var{element} whose head is @var{name}, or @code{#f}."
  (let loop ((children (if (and (pair? (cdr element))
                                (pair? (cadr element))
                                (eq? '@ (car (cadr element))))
                           (cddr element)
                           (cdr element))))
    (cond ((null? children) #f)
          ((and (pair? (car children))
                (eq? name (car (car children))))
           (car children))
          (else (loop (cdr children))))))

(define (children-of element name)
  "Return every child of @var{element} whose head is @var{name}."
  (filter (lambda (child)
            (and (pair? child) (eq? name (car child))))
          (if (and (pair? (cdr element))
                   (pair? (cadr element))
                   (eq? '@ (car (cadr element))))
              (cddr element)
              (cdr element))))

(define (attribute element name)
  "Return the value of attribute @var{name} on SXML @var{element}, or @code{#f}."
  (let ((attributes (and (pair? (cdr element))
                         (pair? (cadr element))
                         (eq? '@ (car (cadr element)))
                         (cdr (cadr element)))))
    (and attributes
         (let ((entry (assoc name attributes)))
           (and entry (cadr entry))))))

(define (image-packages-of-type type)
  "Return the package names the description puts in a @code{<packages>} of @var{type}."
  (let ((block (find (lambda (child)
                       (and (eq? 'packages (car child))
                            (equal? type (attribute child 'type))))
                     (children-of (image-description) 'packages))))
    (and block (map (lambda (package) (attribute package 'name))
                    (children-of block 'package)))))

;; ===========================================
;; The suites
;; ===========================================

(define (session-cases)
  "Return the cases for the packages that make the image a session.

An image that installs a distribution and no session boots to a login prompt and
nothing else, which is what this list is for: the bar, the compositor's session
entry, the display manager, the audio stack and the portals."
  (let ((packages (image-packages-of-type "image")))
    (list (assert-true (not (eq? #f (member "waybar" packages)))
                       #:name "The image should carry the bar")
          (assert-true (not (eq? #f (member "niri" packages)))
                       #:name "The image should carry the compositor")
          (assert-true (not (eq? #f (member "gdm" packages)))
                       #:name "The image should carry the display manager")
          (assert-true (not (eq? #f (member "emacs" packages)))
                       #:name "The image should carry the editor")
          (assert-true (not (eq? #f (member "guile" packages)))
                       #:name "The image should carry the language the desktop is written in")
          (assert-true (not (eq? #f (member "pipewire" packages)))
                       #:name "The image should carry the audio server")
          (assert-true (not (eq? #f (member "xdg-desktop-portal-gnome" packages)))
                       #:name "The image should carry the portals a Wayland session needs")
          (assert-true (not (eq? #f (member "dracut-kiwi-live"
                                            (image-packages-of-type "iso"))))
                       #:name "A live ISO boots from KIWI's own initrd module")
          ;; The two steps that are not session software but are load-bearing all
          ;; the same: the build clones the checkouts with git inside the image,
          ;; and the first boot downloads the Guix installer with curl and checks
          ;; its signature with gpg2.  Without them the image builds nothing and
          ;; then cannot finish itself.
          (assert-true (not (eq? #f (member "git" packages)))
                       #:name "The image should carry the git its build clones with")
          (assert-true (not (eq? #f (member "curl" packages)))
                       #:name "The image should carry the curl its first boot downloads with")
          (assert-true (not (eq? #f (member "gpg2" packages)))
                       #:name "The image should carry the gpg that verifies the download"))))

(define (curation-cases)
  "Return the cases for what the image deliberately leaves out.

The package list this project installs on a workstation carries a compiler, an
IDE's worth of graphics programs and a typesetting system.  A live image is not
where a person builds software, and every one of them is a gigabyte of the disc
the ISO is written to."
  (let ((packages (image-packages-of-type "image")))
    (list (assert-true (eq? #f (member "texlive" packages))
                       #:name "The image should not carry a typesetting system")
          (assert-true (eq? #f (member "blender" packages))
                       #:name "The image should not carry a 3D suite")
          (assert-true (eq? #f (member "rpm-build" packages))
                       #:name "The image should not carry a compiler toolchain")
          (assert-true (eq? #f (member "gimp" packages))
                       #:name "The image should not carry an image editor")
          ;; One network applet, not two: the other one has no icon in the theme
          ;; the session wears, and shows in the bar as an empty square.
          (assert-true (eq? #f (member "nm-tray" packages))
                       #:name "The image should carry one network applet")
          (assert-true (not (eq? #f (member "NetworkManager-applet" packages)))
                       #:name "The one it carries should be the GNOME applet")
          ;; What is left out has to still be installable: `maak install-zypper'
          ;; brings the whole list to an installed system.
          (assert-true (not (eq? #f (member 'texlive heks-linux-zypper)))
                       #:name "The workstation list should still carry the typesetting system"))))

(define (distribution-cases)
  "Return the cases for the distribution the image is made of."
  (let ((repositories (children-of (image-description) 'repository))
        (bootstrap (image-packages-of-type "bootstrap")))
    (list (assert-equal #:expect 2
                        #:got (length repositories)
                        #:name "The image should be built from exactly two repositories")
          (assert-equal #:expect
                        "https://download.opensuse.org/slowroll/repo/oss/"
                        #:got (attribute (child-of (car repositories) 'source)
                                         'path)
                        #:name "The first repository should be Slowroll's open source one")
          (assert-equal #:expect "true"
                        #:got (attribute (car repositories) 'imageinclude)
                        #:name "The repository should be included in the image, not only used to build it")
          (assert-true (not (eq? #f (member "openSUSE-release" bootstrap)))
                       #:name "The bootstrap set should carry the release package, or zypper cannot tell what it is")
          (assert-true (not (eq? #f (member "shadow" bootstrap)))
                       #:name "The bootstrap set should carry the tools that create the live user"))))

(define (user-cases)
  "Return the cases for the live account, and the login that uses it."
  (let* ((user (child-of (child-of (image-description) 'users) 'user))
         (script (image-config-script)))
    (list (assert-equal #:expect (image-user)
                        #:got (attribute user 'name)
                        #:name "The image should create the user it is named after")
          (assert-equal #:expect (image-user-home)
                        #:got (attribute user 'home)
                        #:name "The live user's home should be the one the checkouts are cloned into")
          (assert-true (not (eq? #f (string-contains (attribute user 'groups)
                                                     "wheel")))
                       #:name "The live user should be able to use sudo")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     (format #f "AutomaticLogin=~a"
                                             (image-user)))))
                       #:name "GDM should log in the same user the image creates")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "AutomaticLoginEnable=true")))
                       #:name "The autologin should be enabled, not merely configured")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "systemctl enable gdm.service")))
                       #:name "The display manager should be enabled")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "systemctl set-default graphical.target")))
                       #:name "The image should boot to the graphical target"))))

(define (checkout-cases)
  "Return the cases for the three projects the image is pre-loaded with."
  (let ((script (image-config-script)))
    (append
     (map (lambda (checkout)
            (assert-true (not (eq? #f (string-contains
                                       script
                                       (format #f "~a.git ~a"
                                               (car checkout)
                                               (car checkout)))))
                         #:name
                         (format #f "The image should clone ~a" (car checkout))))
          (image-checkouts))
     (list (assert-true (not (eq? #f (string-contains script ".emacs.d")))
                        #:name
                        "The editor's configuration directory should be created")
           (assert-true (not (eq? #f (string-contains script
                                                      "heks-emacs/src/init.el")))
                        #:name "The editor's configuration should be installed, not only checked out")
           (assert-true (not (eq? #f (string-contains script "snippets")))
                        #:name "The editor's modules and snippets should be copied with it")))))

(define (toolchain-cases)
  "Return the cases for the two stores the desktop's programs come from.

openSUSE packages both, and the packaging gets two things subtly wrong for a
desktop: `guix-publish' serves the store on the network, and a unit the guix
package ships makes /gnu/store read-only.  A machine whose owner installs
packages wants neither.
  "
  (let ((packages (image-packages-of-type "image"))
        (script (image-config-script)))
    (list (assert-true (not (eq? #f (member "guix" packages)))
                       #:name "The image should carry Guix")
          (assert-true (not (eq? #f (member "nix" packages)))
                       #:name "The image should carry Nix")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "systemctl enable guix-daemon.service")))
                       #:name "The Guix daemon should be enabled, or the store cannot be added to")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "systemctl disable guix-publish.service")))
                       #:name "Publishing the store on the network is not a desktop's job")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "systemctl mask gnu-store.mount")))
                       #:name "The store should stay writable, so its read-only mount is masked")
          (assert-true (not (eq? #f (string-contains
                                     script
                                     "systemctl enable nix-daemon.socket")))
                       #:name "The nix daemon should start when something asks it to")
          (assert-true (not (eq? #f (string-contains script "wait_for nix-daemon")))
                       #:name "The build should wait for its own nix daemon")
          (assert-true (not (eq? #f (string-contains script "wait_for guix-daemon")))
                       #:name "The build should wait for its own guix daemon"))))

(define (installable-cases)
  "Return the cases for the half of the image you keep.

The live ISO is the one you try; the OEM image is the installed system, and the
install ISO writes it to a machine's disk.  Without it this is a demo.
  "
  (let* ((preferences (child-of (image-description) 'preferences))
         (types (children-of preferences 'type))
         (oem (find (lambda (type)
                      (equal? "oem" (attribute type 'image)))
                    types)))
    (list (assert-equal #:expect 2
                        #:got (length types)
                        #:name "The description should produce a live ISO and an installable image")
          (assert-true (not (eq? #f oem))
                       #:name "One of them should be an OEM image")
          (assert-equal #:expect "true"
                        #:got (attribute oem 'installiso)
                        #:name "The OEM image should ship an install ISO")
          (assert-equal #:expect "true"
                        #:got (cadr (child-of (child-of oem 'oemconfig) 'oem-resize))
                        #:name "An installed image should grow to the disk it lands on")
          (assert-true (not (eq? #f (member "dracut-kiwi-oem-repart"
                                            (image-packages-of-type "image"))))
                       #:name "The initrd module that grows it should be on the image"))))

(define (render-cases)
  "Return the cases for how the desktop's files get written.

The build renders them, so the image is ready when it boots.  `heks-render' is
the way to do it again - and the one thing about it that has to hold is that it
renders what the build rendered: two lists that are meant to be the same list
are two lists that will disagree.
  "
  (let* ((tool (image-payload-script))
         (unit (image-payload-unit))
         (build (image-config-script))
         (tasks '("maak home-reconfigure"
                  "maak install-bash"
                  "maak install-icon-files"
                  "maak install-heks-toon"
                  "maak install-lambdock")))
    (append
     (map (lambda (task)
            (assert-true (not (eq? #f (string-contains tool task)))
                         #:name
                         (format #f "heks-render should run ~a" task)))
          tasks)
     (map (lambda (task)
            (assert-true (not (eq? #f (string-contains build task)))
                         #:name
                         (format #f "The build should run ~a" task)))
          tasks)
     (list (assert-true (not (eq? #f (string-contains tool "id -un")))
                        #:name "heks-render should refuse to render another user's home as a user")
            (assert-true (not (eq? #f (string-contains
                                       unit
                                       (format #f "ConditionPathExists=!~a/rendered"
                                               (image-payload-state-dir)))))
                         #:name "The unit should skip itself once the desktop is rendered")
            (assert-true (not (eq? #f (string-contains build (format #f "~a/rendered"
                                                                     (image-payload-state-dir)))))
                         #:name "The build should leave the marker the unit reads")
            (assert-true (not (eq? #f (string-contains unit "Type=oneshot")))
                         #:name "It is a one-shot, not a daemon")
            (assert-true (not (eq? #f (string-contains unit "After=network-online.target")))
                         #:name "Rendering downloads, so it should wait for the network")))))

(define (verification-cases)
  "Return the cases for the phase that decides whether the build worked.

A build is only finished if it says so: every promise the phases make is checked
as a file or a command, and the build fails with the list of what is missing.
  "
  (let ((script (image-config-script)))
    (list (assert-true (not (null? image-required-paths))
                       #:name "The build should know what a ready system looks like")
          (assert-true (not (null? image-required-commands))
                       #:name "It should check programs as well as files")
          (assert-true (not (eq? #f (member "guix" image-required-commands)))
                       #:name "Guix should be one of the programs a ready image has")
          (assert-true (not (eq? #f (member "nix" image-required-commands)))
                       #:name "Nix should be one of them too")
          (assert-true (not (eq? #f (string-contains script "is it ready?")))
                       #:name "The build should have a phase that asks")
          (assert-true (not (eq? #f (string-contains script "$missing thing(s) missing")))
                       #:name "And it should refuse to produce an image that fails it"))))

(define (xml-cases)
  "Return the cases for the text KIWI is actually handed."
  (let ((xml (image-description-xml)))
    (list (assert-true (not (eq? #f (string-contains
                                     xml
                                     "<?xml version=\"1.0\" encoding=\"utf-8\"?>")))
                       #:name "The description should declare itself as UTF-8 XML")
          (assert-true (not (eq? #f (string-contains
                                     xml
                                     "<image schemaversion=\"8.5\"")))
                       #:name "The schema version should be the one KIWI 10.3 validates against")
          ;; A well formed document: once the self-closing elements - which have
          ;; no closing tag by design - are taken out, every element the
          ;; description opens is closed.  This is what a hand-written renderer
          ;; gets wrong.
          (assert-equal #:expect
                        (length (list-matches "<([a-z-]+)[ >]"
                                              (regexp-substitute/global
                                               #f
                                               "<[a-z-]+[^>]*/>"
                                               xml
                                               'pre "" 'post)))
                        #:got
                        (length (list-matches "</([a-z-]+)>" xml))
                        #:name "Every element the description opens should be closed")
          (assert-equal #:expect #f
                        #:got (string-contains xml "&&")
                        #:name "The renderer should not double-escape"))))

(define image-suite
  (suite "Heks-Linux Live Image Suite"
         (test "The Description Is A Live Image"
               (let ((type (child-of (child-of (image-description) 'preferences)
                                     'type)))
                 (assert-equal #:expect "iso"
                               #:got (attribute type 'image)
                               #:name "The image should be an ISO")
                 (assert-equal #:expect "overlay"
                               #:got (attribute type 'flags)
                               #:name "The ISO should boot from an overlay, so the medium stays read-only")
                 (assert-equal #:expect "true"
                               #:got (attribute type 'hybridpersistent)
                               #:name "The same file should keep a session when it is written to a stick")
                 (assert-true (not (eq? #f (child-of (image-description)
                                                     'preferences)))
                              #:name "The description should have preferences at all")))

         (test "The Image Follows The Desktop's Settings"
               (let ((preferences (child-of (image-description) 'preferences)))
                 (assert-equal #:expect (heks-linux-timezone)
                               #:got (cadr (child-of preferences 'timezone))
                               #:name "The image should be in the timezone the desktop declares")
                 (assert-equal #:expect (heks-linux-language)
                               #:got (cadr (child-of preferences 'locale))
                               #:name "The image should be in the locale the desktop declares")
                 (assert-true (not (eq? #f (string-contains
                                            (image-config-script)
                                            (format #f "echo ~a" (heks-linux-hostname)))))
                              #:name "The image should carry the desktop's hostname")))

         (test "The Session Is On The Image" (session-cases))
         (test "What The Image Leaves Out" (curation-cases))
         (test "The Distribution Is Slowroll" (distribution-cases))
         (test "The Live Account Is The One That Logs In" (user-cases))
         (test "The Three Projects Are Pre-Loaded" (checkout-cases))
         (test "Guix And Nix Are On It" (toolchain-cases))
         (test "It Installs As Well As Boots" (installable-cases))
         (test "It Is Rendered Before It Ships" (render-cases))
         (test "The Build Checks Itself" (verification-cases))
         (test "The Description Is Well Formed XML" (xml-cases))))

(define (spec)
  (veritas-run image-suite))
