;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux packages flatpak).
;;
;; The catalog is data, so the tests are about the invariants of that data:
;; every id is a reverse-DNS string, every remote is one the installer knows how
;; to add, the union is sorted and free of duplicates, and the extra parameter
;; really is appended at call time.  The command vectors are checked exactly,
;; because a stray string that a shell would split is the failure this
;; declaration replaced.

;;; Code:

(define-module (veritas unit flatpak-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux packages flatpak)
  #:use-module (srfi srfi-1)
  #:export (spec))

(define (flatpak-ids apps)
  (map flatpak-app-id apps))

(define (ids-sorted? ids)
  (or (null? ids)
      (every (lambda (a b)
               (string<=? a b)) ids
             (cdr ids))))

(define (count-id id apps)
  (length (filter (lambda (app)
                    (string=? id
                              (flatpak-app-id app))) apps)))

(define (contains-id? ids id)
  (not (eq? #f
            (member id ids))))

(define (declaration-suite)
  (suite "Application Declarations"
         (test "The Default Remote Is Flathub"
               (assert-true (flatpak-app? (flatpak-app "org.gnome.Boxes"))
                            #:name
                            "A declaration produces an application record")
               (assert-equal #:expect "flathub"
                             #:got (flatpak-app-remote (flatpak-app
                                                        "org.gnome.Boxes"))
                             #:name "The ordinary entry needs no remote")
               (assert-equal #:expect "flathub-beta"
                             #:got (flatpak-app-remote (flatpak-app
                                                        "org.gnome.Boxes"
                                                        #:remote
                                                        "flathub-beta"))
                             #:name "An application can name another remote"))
         (test "Symbols And Strings Are Both Accepted"
               (assert-equal #:expect "org.gnome.Boxes"
                             #:got (flatpak-app-id (flatpak-app 'org.gnome.Boxes))
                             #:name "A symbol is coerced to the id string")
               (assert-true (string? (flatpak-app-id (flatpak-app
                                                      "app.zen_browser.zen")))
                            #:name "Ids are always strings in the catalog"))
         (test "Malformed Ids Are Rejected"
               (assert-equal #:expect #t
                             #:got (flatpak-app-id?
                                    "io.github.aandrew_me.ytdn")
                             #:name "An underscore in a segment is allowed")
               (assert-equal #:expect #f
                             #:got (flatpak-app-id? "Boxes")
                             #:name "A bare name is not an id")
               (assert-error (lambda ()
                               (flatpak-app "Boxes"))
                             #:name "The constructor refuses a bare name")
               (assert-error (lambda ()
                               (flatpak-app "org.gnome Boxes"))
                             #:name "The constructor refuses whitespace"))))

(define (command-suite)
  (suite "Command Vectors"
         (test "Install Arguments Are Separate Strings"
               (assert-equal #:expect '("flatpak" "install" "--user"
                                        "--assumeyes" "flathub"
                                        "org.gnome.Boxes")
                             #:got (flatpak-install-args (flatpak-app
                                                          "org.gnome.Boxes"))
                             #:name
                             "The id and remote are never one shell string")
               (assert-equal #:expect '("flatpak" "install" "--user"
                                        "--assumeyes" "flathub-beta"
                                        "org.gnome.Boxes")
                             #:got (flatpak-install-args (flatpak-app
                                                          "org.gnome.Boxes"
                                                          #:remote
                                                          "flathub-beta"))
                             #:name "A custom remote is passed through"))
         (test "Remote Addition Uses The Registered URL"
               (assert-equal #:expect '("flatpak" "remote-add" "--user"
                                        "--if-not-exists" "flathub"
                                        "https://dl.flathub.org/repo/flathub.flatpakrepo")
                             #:got (flatpak-remote-add-args "flathub")
                             #:name "remote-add carries the .flatpakrepo URL")
               (assert-equal #:expect
                "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo"
                #:got (flatpak-remote-url "flathub-beta")
                #:name "The beta repository is known")
               (assert-error (lambda ()
                               (flatpak-remote-url "not-a-remote"))
                             #:name "An unknown remote is an error"))))

(define (catalog-suite)
  (suite "Catalog"
         (test "The Union Is Sorted And Duplicate-Free"
               (let* ((apps (heks-linux-flatpak))
                      (ids (flatpak-ids apps)))
                 (assert-true (ids-sorted? ids)
                              #:name "Applications are sorted by id")
                 (assert-equal #:expect (length ids)
                               #:got (length (delete-duplicates ids))
                               #:name "No id is declared twice")))
         (test "Every Entry Is Installable"
               (let ((apps (heks-linux-flatpak)))
                 (assert-true (every flatpak-app-id?
                                     (flatpak-ids apps))
                              #:name "Every id passes the form check")
                 (assert-true (every (lambda (app)
                                       (not (eq? #f
                                                 (assoc (flatpak-app-remote
                                                         app)
                                                        (flatpak-remotes)))))
                                     apps)
                              #:name "Every remote can be bootstrapped")))
         (test "The Curated Additions Are Present"
               (let ((ids (flatpak-ids (heks-linux-flatpak))))
                 (assert-true (contains-id? ids "org.libreoffice.LibreOffice")
                              #:name "LibreOffice fills the office gap")
                 (assert-true (contains-id? ids "org.keepassxc.KeePassXC")
                              #:name
                              "KeePassXC fills the password-manager gap")
                 (assert-true (contains-id? ids "org.telegram.desktop")
                              #:name "Telegram is declared")
                 (assert-true (contains-id? ids "org.gnome.DejaDup")
                              #:name "DejaDup covers backups")
                 (assert-true (contains-id? ids "org.qbittorrent.qBittorrent")
                              #:name "qBittorrent covers torrents")
                 (assert-true (contains-id? ids "org.kde.krita")
                              #:name "Krita covers digital painting")
                 (assert-true (contains-id? ids "fr.handbrake.ghb")
                              #:name "HandBrake covers video conversion")
                 (assert-true (contains-id? ids "com.valvesoftware.Steam")
                              #:name "Steam is declared for gaming")
                 (assert-true (contains-id? ids "com.rustdesk.RustDesk")
                              #:name "RustDesk covers remote support")
                 (assert-true (contains-id? ids "io.github.flattool.Warehouse")
                              #:name
                              "Warehouse manages the Flatpak installation")
                 (assert-true (contains-id? ids "app.zen_browser.zen")
                              #:name "Zen Browser is still declared")))
         (test "Applications Installed By Hand Are Now Declared"
               (let ((ids (flatpak-ids (heks-linux-flatpak))))
                 (assert-true (contains-id? ids "dog.unix.cantata.Cantata")
                              #:name "Cantata is in the music category")
                 (assert-true (contains-id? ids "io.github.aandrew_me.ytdn")
                              #:name "ytdn is in the media category")
                 (assert-true (contains-id? ids "org.gnome.Boxes")
                              #:name "Boxes is in the development category")))))

(define (override-suite)
  (suite "Overrides"
         (test "Extra Applications Join The Union"
               (parameterize ((heks-linux-extra-flatpak (list (flatpak-app
                                                               "org.example.Tool"))))
                 (assert-true (contains-id? (flatpak-ids (heks-linux-flatpak))
                                            "org.example.Tool")
                              #:name "An extra application joins the union")))
         (test "A Duplicate Extra Entry Is Installed Once"
               (parameterize ((heks-linux-extra-flatpak (list (flatpak-app
                                                               "app.zen_browser.zen"))))
                 (assert-equal #:expect 1
                               #:got (count-id "app.zen_browser.zen"
                                               (heks-linux-flatpak))
                               #:name "The first declaration wins")))
         (test "An Extra Can Change An Existing Remote"
               (parameterize ((heks-linux-extra-flatpak (list (flatpak-app
                                                               "app.zen_browser.zen"
                                                               #:remote
                                                               "flathub-beta"))))
                 (let ((zen (find (lambda (app)
                                    (string=? "app.zen_browser.zen"
                                              (flatpak-app-id app)))
                                  (heks-linux-flatpak))))
                   (assert-equal #:expect "flathub-beta"
                    #:got (flatpak-app-remote zen)
                    #:name "The extra declaration wins over the category"))))
         (test "Category Parameters Are Read At Call Time"
               (parameterize ((heks-linux-work-flatpak '()))
                 (assert-equal #:expect #f
                               #:got (contains-id? (flatpak-ids (heks-linux-flatpak))
                                      "org.libreoffice.LibreOffice")
                               #:name "Replacing a category removes its apps"))
               (assert-true (contains-id? (flatpak-ids (heks-linux-flatpak))
                                          "org.libreoffice.LibreOffice")
                            #:name "The default category is back afterwards"))))

(define (spec)
  (veritas-run (declaration-suite)
               (command-suite)
               (catalog-suite)
               (override-suite)))
