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
;; The Flatpak application catalog, grouped by the part of the desktop it
;; serves.
;;
;; An application is declared with @code{flatpak-app}: the id that Flathub
;; uses (the reverse-DNS name, also the desktop file and the sandbox name) and
;; the remote it comes from.  The remote defaults to @code{flatpak-remote},
;; which is Flathub, so the ordinary entry is just
;; @code{(flatpak-app "org.gnome.Boxes")}; the second argument is there for the
;; day an application only exists on a beta or vendor remote.  Declaring the
;; remote instead of smuggling it into the id as a string is what lets the
;; installer add the remote itself, check that the id is actually an id, and
;; build an argument vector rather than a shell line.
;;
;; @code{flatpak-remotes} maps a remote name to the @file{.flatpakrepo} file
;; that describes it.  @code{install-flatpak} adds every remote used by the
;; catalog that is not already configured, with
;; @code{flatpak remote-add --user --if-not-exists}, so a fresh machine does
;; not have to be bootstrapped by hand.  The check looks at every installation,
;; not only the user one: adding a second @code{flathub} remote when the system
;; installation already has one makes @command{flatpak} ambiguous.
;;
;; The category lists are parameters, so a machine can replace one without
;; forking the module.  @code{install-flatpak} reads
;; @file{$XDG_CONFIG_HOME/heks-linux/flatpak-settings.scm} first, which is where
;; those parameters are set.  @code{heks-linux-flatpak} is a procedure rather
;; than a list because it has to observe them: it prepends
;; @code{heks-linux-extra-flatpak} to the categories, drops duplicate ids and
;; sorts the result, so the order of the groups never matters and two categories
;; can share an application without installing it twice.  The extras come first
;; on purpose: redeclaring an id there wins, which is how a machine can move an
;; application to a beta remote without editing the catalog.
;;
;; The catalog leans on well-known applications for jobs the rest of Heks does
;; not cover: an office suite, a password manager, a backup tool, a torrent
;; client, a remote-desktop client, digital painting, and the Flatpak manager
;; itself.  Everything is installed with @code{flatpak install --user}, in the
;; user installation, the same way the rest of the Heks applications are.

;;; Code:

(define-module (heks-linux packages flatpak)
  #:declarative? #t
  #:use-module (heks-linux prelude)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:export (flatpak-app flatpak-app?
                        flatpak-app-id
                        flatpak-app-remote
                        flatpak-app-id?
                        flatpak-remote
                        flatpak-remotes
                        flatpak-remote-url
                        flatpak-remote-add-args
                        flatpak-install-args
                        heks-linux-extra-flatpak
                        heks-linux-dev-flatpak
                        heks-linux-gaming-flatpak
                        heks-linux-media-flatpak
                        heks-linux-music-flatpak
                        heks-linux-net-flatpak
                        heks-linux-other-flatpak
                        heks-linux-work-flatpak
                        heks-linux-flatpak
                        install-flatpak))

;; --- Declaring an application ---

;; The Flatpak installation an application comes from.  Flathub is the one
;; remote with an app for almost everything, so it is the default.
(define flatpak-remote
  (make-parameter "flathub"))

;; The repositories Heks knows how to add.  A remote named here can be used by
;; @code{flatpak-app} without the machine having been configured by hand; the
;; beta repository is listed because it is the other Flathub remote an
;; application may need, not because anything in the catalog uses it.
(define flatpak-remotes
  (make-parameter '(("flathub" . "https://dl.flathub.org/repo/flathub.flatpakrepo")
                    ("flathub-beta" . "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo"))))

(define-record-type <flatpak-app>
  (%make-flatpak-app id remote) flatpak-app?
  (id flatpak-app-id)
  (remote flatpak-app-remote))

(define (flatpak-app-id? id)
  "Return @code{#t} when @var{id} can be a Flatpak application id.

The check is deliberately shallow: a non-empty string with a dot and no
whitespace.  It catches the mistake that actually happens - a bare symbol such
as @code{Boxes}, or a half-copied entry with a space in it - without pretending
to implement Flatpak's own naming rules, which also allow underscores in the
first segment."

  (and (string? id)
       (> (string-length id) 0)
       (not (eq? #f
                 (string-contains id ".")))
       (eq? #f
            (string-contains id " "))))

(define* (flatpak-app id
                      #:key (remote (flatpak-remote)))
  "Declare one Flatpak application.

@var{id} is the reverse-DNS application id, the name Flathub and
@command{flatpak} use everywhere.  @var{remote} names the remote it comes from
and defaults to @code{flatpak-remote} (Flathub).  Symbols are accepted for the
convenience of a REPL, but the catalog uses strings.

@example
(flatpak-app \"org.gnome.Boxes\")
@result{} #<flatpak-app>
@end example"
  (let ((id (if (symbol? id)
                (symbol->string id) id))
        (remote (if (symbol? remote)
                    (symbol->string remote) remote)))
    (unless (flatpak-app-id? id)
      (error "flatpak-app: not a Flatpak application id:" id))
    (%make-flatpak-app id remote)))

;; --- The catalog ---

(define heks-linux-dev-flatpak
  (make-parameter (list (flatpak-app "ai.lmstudio.lm-studio")
                        (flatpak-app "com.bardojai.ForgeSparks")
                        (flatpak-app "com.github.finefindus.eyedropper")
                        (flatpak-app "com.rafaelmardojai.WebfontKitGenerator")
                        (flatpak-app "io.github.fizzyizzy05.binary")
                        (flatpak-app "io.gitlab.liferooter.TextPieces")
                        (flatpak-app "org.gaphor.Gaphor")
                        (flatpak-app "org.gnome.Boxes")
                        (flatpak-app "org.gnome.design.Emblem")
                        (flatpak-app "org.gnome.design.Lorem")
                        (flatpak-app "re.sonny.Workbench")
                        (flatpak-app "se.sjoerd.Graphs"))))

(define heks-linux-gaming-flatpak
  (make-parameter (list (flatpak-app "com.valvesoftware.Steam")
                        (flatpak-app "net.retrodeck.retrodeck")
                        (flatpak-app "org.libretro.RetroArch")
                        (flatpak-app "org.prismlauncher.PrismLauncher")
                        (flatpak-app "page.kramo.Cartridges"))))

(define heks-linux-media-flatpak
  (make-parameter (list (flatpak-app "com.github.huluti.Curtail")
                        (flatpak-app "fr.handbrake.ghb")
                        (flatpak-app "io.github.aandrew_me.ytdn")
                        (flatpak-app "io.github.wartybix.Constrict")
                        (flatpak-app "io.gitlab.adhami3310.Converter")
                        (flatpak-app "org.gnome.gitlab.YaLTeR.VideoTrimmer")
                        (flatpak-app "org.kde.kdenlive")
                        (flatpak-app "org.kde.krita"))))

(define heks-linux-music-flatpak
  (make-parameter (list (flatpak-app "com.spotify.Client")
                        (flatpak-app "de.haeckerfelix.Shortwave")
                        (flatpak-app "dev.bragefuglseth.Fretboard")
                        (flatpak-app "dev.diegovsky.Riff")
                        (flatpak-app "dog.unix.cantata.Cantata")
                        (flatpak-app "io.bassi.Amberol")
                        (flatpak-app "io.github.htkhiem.Euphonica"))))

(define heks-linux-net-flatpak
  (make-parameter (list (flatpak-app "app.zen_browser.zen")
                        (flatpak-app "com.brave.Browser")
                        (flatpak-app "com.discordapp.Discord")
                        (flatpak-app "com.github.hugolabe.Wike")
                        (flatpak-app "com.rtosta.zapzap")
                        (flatpak-app "com.rustdesk.RustDesk")
                        (flatpak-app "com.usebruno.Bruno")
                        (flatpak-app "de.haeckerfelix.Fragments")
                        (flatpak-app "engineer.atlas.Nyxt")
                        (flatpak-app "io.gitlab.news_flash.NewsFlash")
                        (flatpak-app "org.gnome.Epiphany")
                        (flatpak-app "org.qbittorrent.qBittorrent")
                        (flatpak-app "org.telegram.desktop"))))

(define heks-linux-other-flatpak
  (make-parameter (list (flatpak-app "app.drey.Dialect")
                        (flatpak-app "app.drey.Warp")
                        (flatpak-app "com.belmoussaoui.Decoder")
                        (flatpak-app "com.github.tchx84.Flatseal")
                        (flatpak-app "dev.mufeed.Wordbook")
                        (flatpak-app "io.github.flattool.Warehouse")
                        (flatpak-app "io.github.idevecore.Valuta")
                        (flatpak-app "io.gitlab.adhami3310.Impression")
                        (flatpak-app "net.nokyan.Resources")
                        (flatpak-app "org.gnome.DejaDup")
                        (flatpak-app "org.gnome.Solanum")
                        (flatpak-app "org.keepassxc.KeePassXC")
                        (flatpak-app "org.signal.Signal")
                        (flatpak-app "org.zulip.Zulip"))))

(define heks-linux-work-flatpak
  (make-parameter (list (flatpak-app "com.slack.Slack")
                        (flatpak-app "org.libreoffice.LibreOffice"))))

;; Applications a machine wants on top of the catalog.  The value is a list of
;; @code{flatpak-app} records.  It is read before the categories, so an id that
;; already exists can be redeclared to change its remote, and it is also the
;; place to try an application before moving it into a category:
;;
;; @example
;; (heks-linux-extra-flatpak
;;  (list (flatpak-app "org.example.Tool")))
;; @end example
(define heks-linux-extra-flatpak
  (make-parameter '()))

;; --- Rendering ---

(define (flatpak-unique apps)
  "Return @var{apps} with only the first declaration of each id.

The first declaration keeps its remote, so callers order the more specific list
first; without this, an application that fits two groups would be installed
twice."
  (let loop
    ((remaining apps)
     (seen '())
     (result '()))
    (cond
      ((null? remaining)
       (reverse result))
      ((member (flatpak-app-id (car remaining)) seen)
       (loop (cdr remaining) seen result))
      (else (loop (cdr remaining)
                  (cons (flatpak-app-id (car remaining)) seen)
                  (cons (car remaining) result))))))

(define (heks-linux-flatpak)
  "Return the whole Flatpak catalog, deduplicated and sorted by id.

The result is the union of @code{heks-linux-extra-flatpak} and the category
parameters, read at call time so a local override is observed.  The extras come
first, so redeclaring an id there wins; sorting by id makes the installation
order stable and the generated list easy to inspect.

@example
(map flatpak-app-id (heks-linux-flatpak))
@end example"
  (sort (flatpak-unique (append (heks-linux-extra-flatpak)
                                (heks-linux-dev-flatpak)
                                (heks-linux-gaming-flatpak)
                                (heks-linux-media-flatpak)
                                (heks-linux-music-flatpak)
                                (heks-linux-net-flatpak)
                                (heks-linux-other-flatpak)
                                (heks-linux-work-flatpak)))
        (lambda (a b)
          (string<? (flatpak-app-id a)
                    (flatpak-app-id b)))))

(define (flatpak-remote-url remote)
  "Return the @file{.flatpakrepo} URL registered for @var{remote}.

An unknown remote is an error rather than a silent skip: the alternative is an
installation that looks like it worked and an empty application list."
  (let ((entry (assoc remote
                      (flatpak-remotes))))
    (if entry
        (cdr entry)
        (error "flatpak-remote-url: unknown remote:" remote))))

(define (flatpak-remote-add-args remote)
  "Return the argument vector that registers @var{remote} for the user."
  (list "flatpak"
        "remote-add"
        "--user"
        "--if-not-exists"
        remote
        (flatpak-remote-url remote)))

(define (flatpak-install-args app)
  "Return the argument vector that installs @var{app} for the user.

The id and the remote are separate arguments, never a command string, because a
shell would re-parse an id that was already checked and could expand anything
that looks like a metacharacter."
  (list "flatpak"
        "install"
        "--user"
        "--assumeyes"
        (flatpak-app-remote app)
        (flatpak-app-id app)))

(define (flatpak-remote-present? remote)
  "Return @code{#t} when @var{remote} is configured in any Flatpak installation.

@command{flatpak remote-add} would happily add a second @code{flathub} to the
user installation when the system one already exists, and a duplicate remote
name makes some @command{flatpak} commands ask which one was meant."
  (let ((configured (syscall "flatpak remotes --columns=name"
                             #:silent? #t)))
    (and configured
         (not (eq? #f
                   (member remote
                           (string-split configured #\newline)))))))

(define (run-flatpak args)
  "Run @var{args} with @command{flatpak} and report whether it succeeded."
  (format #t "\nExecuting command: ~a\n"
          (string-join args " "))
  (let ((status (apply system* args)))
    (cond
      ((eq? status #f)
       (format (current-error-port) "could not execute ~a\n"
               (string-join args " ")) #f)
      ((zero? status)
       #t)
      (else (format (current-error-port) "flatpak exited with status ~a: ~a\n"
                    status
                    (string-join args " ")) #f))))

(define (install-flatpak)
  "Install every application in @code{(heks-linux-flatpak)}.

Each remote the catalog uses is registered first when it is not configured in
any installation, so a fresh machine does not have to add Flathub by hand.
Applications are installed into the user installation with
@code{flatpak install --user --assumeyes}; an application that is already
present is skipped by Flatpak itself.  A failure is reported but does not stop
the rest of the list, because one unavailable application should not leave the
machine without the others.

Per-machine additions live in
@file{$XDG_CONFIG_HOME/heks-linux/flatpak-settings.scm}, which is evaluated in
this module's scope before the catalog is read:

@example
(heks-linux-extra-flatpak
 (list (flatpak-app \"org.gnome.Boxes\")))
@end example"
  (load-local-overrides '(heks-linux packages flatpak)
                        'flatpak-settings)
  (let ((apps (heks-linux-flatpak)))
    (for-each (lambda (remote)
                (unless (flatpak-remote-present? remote)
                  (run-flatpak (flatpak-remote-add-args remote))))
              (delete-duplicates (map flatpak-app-remote apps)))
    (for-each (lambda (app)
                (run-flatpak (flatpak-install-args app))) apps)))
