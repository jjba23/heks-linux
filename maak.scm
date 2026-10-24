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

(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak))

;; ====== Certificate store ======

;; Guix links its Git support against OpenSSL, whose compiled-in trust store
;; is its own store directory and therefore empty; libgit2 then falls back to
;; /etc/ssl/certs/ca-certificates.crt, which openSUSE does not have -- it keeps
;; the bundle in /etc/ssl/ca-bundle.pem.  Without a bundle every channel fetch
;; fails with "Git-fout: the SSL certificate is invalid" before a single object
;; moves, which reads like a network problem rather than a missing CA file, and
;; it is what `guix time-machine --channels=channels.scm' -- and with it every
;; task below that runs in the pinned manifest shell -- reported.
;;
;; Point the environment at whichever bundle this machine has: SSL_CERT_FILE is
;; what OpenSSL and libgit2 read, GIT_SSL_CAINFO what a plain `git' reads.  An
;; SSL_CERT_FILE already set wins, so a machine with its own bundle keeps it.
(define ca-bundle-candidates
  '("/etc/ssl/certs/ca-certificates.crt"
    "/etc/ssl/ca-bundle.pem"
    "/etc/pki/tls/certs/ca-bundle.crt"
    "/etc/ssl/cert.pem"))

(define (first-existing-file files)
  "Return the first of FILES that exists, or #f."
  (cond ((null? files) #f)
        ((file-exists? (car files)) (car files))
        (else (first-existing-file (cdr files)))))

(let ((bundle (or (getenv "SSL_CERT_FILE")
                  (first-existing-file ca-bundle-candidates))))
  (when bundle
    (setenv "SSL_CERT_FILE" bundle)
    (setenv "GIT_SSL_CAINFO" bundle)))

;; ====== Maak constants ======

;; The URL for the CSS style-sheet used to style API documentation.
(define api-docs-css-url
  "https://jointhefreeworld.org/static/css/jointhefreeworld.css")

;; The path to the directory where the API documentation will be deployed.
(define deploy-api-docs-dir
  "/srv/http/jointhefreeworld.org")

;; The name of the project, represented as a symbol.
(define project-name
  'heks-linux)

(define hot-reload-file-types
  '(scm))

;; The home directory, resolved once.  The file helpers run their program
;; without a shell, so a `~' left in a path would be a literal directory name;
;; every path below is written from this instead.
(define home
  (home-dir))

;; ====== Maak tasks ======

(define* (run-heks-install-config-script func
                                         #:key (mod #f)
                                         (config-suffix? #t) verbose?)
  (let ((mod (~ "'((@(heks-linux ~a) install-~a~a))'"
                (if mod mod func) func
                (if config-suffix? "-config" ""))))
    (time-machine-manifest-shell (list "guile" "-L" "./src" "-c" mod)
                                 #:verbose? verbose?)))

(define (compile)
  "Compile all project source code."
  (time-machine-manifest-shell (list "guild" "compile" "-L" "./src" "-W3"
                                     "./src/**/*.scm")))

;; Run @var{cmd-parts} in the pinned manifest shell, but inside a Guix
;; container.  A plain `guix shell' (even with --pure) inherits the caller's
;; $HOME and $XDG_CONFIG_HOME, so loading a config module at test time would
;; read the developer's ~/.config/heks-linux/local-settings.scm and make the
;; suite depend on host state.  The container gives the tests a private /home
;; and /tmp, so they run the same way on any machine.
(define* (time-machine-manifest-container-shell cmd-parts
                                               #:key (verbose? #f)
                                               (channels "channels.scm")
                                               (manifest "manifest.scm"))
  ;; The manifest-shell helpers have no `--container' option, so the pinned
  ;; `guix time-machine' line is built here: `time-machine' prepends the pin
  ;; and takes the rest of the command as argv.
  (time-machine (append (list "shell" "-m" manifest "--container" "--")
                        cmd-parts)
                #:channels channels
                #:verbose? verbose?))

(define (install-lambdock)
  "Install Lambdock config files."
  (mkdir-p (~ "~a/.config/lambdock" home))
  (run-heks-install-config-script 'lambdock))

(define (install-gif)
  "Install GIF config files."
  (mkdir-p (~ "~a/.local/bin" home))
  (run-heks-install-config-script 'gif))

(define (install-waybar)
  "Install Waybar config files."
  (mkdir-p (~ "~a/.config/waybar" home))
  (run-heks-install-config-script 'waybar))

(define (install-rofi)
  "Install Rofi config files (theme, launcher and the script modes)."
  (mkdir-p (~ "~a/.config/rofi" home))
  (run-heks-install-config-script 'rofi))

(define (install-niri)
  "Install Niri config files."
  (mkdir-p (~ "~a/.config/niri" home))
  (run-heks-install-config-script 'niri))

(define (install-rmpc)
  "Install RMPC config files."
  (mkdir-p (~ "~a/.config/rmpc" home))
  (run-heks-install-config-script 'rmpc))

(define (install-wezterm)
  "Install WezTerm config files."
  (mkdir-p (~ "~a/.config/wezterm" home))
  (run-heks-install-config-script 'wezterm))

(define (install-zen)
  "Install the Zen Browser user.js and uBlock Origin in every profile."
  (run-heks-install-config-script 'zen))

(define (install-mako)
  "Install Mako config files."
  (mkdir-p (~ "~a/.config/mako" home))
  (run-heks-install-config-script 'mako))

(define (install-btop)
  "Install Btop config files."
  (mkdir-p (~ "~a/.config/btop" home))
  (run-heks-install-config-script 'btop))

(define (install-keybindings)
  "Install the keyboard reference and its launcher."
  (mkdir-p (~ "~a/.config/heks-linux/keybindings" home))
  (mkdir-p (~ "~a/.local/bin" home))
  (run-heks-install-config-script 'keybindings))

(define (install-git)
  "Install Git config files."
  (run-heks-install-config-script 'git))

(define (install-dconf)
  "Install DConf config files."
  (run-heks-install-config-script 'dconf))

(define (install-fastfetch)
  "Install FastFetch config files."
  (mkdir-p (~ "~a/.config/fastfetch" home))
  (run-heks-install-config-script 'fastfetch))

(define (install-gtk)
  "Install GTK config files."
  (mkdir-p (~ "~a/.config/gtk-3.0" home))
  (run-heks-install-config-script 'gtk3
                                  #:mod 'gtk)
  (mkdir-p (~ "~a/.config/gtk-4.0" home))
  (run-heks-install-config-script 'gtk4
                                  #:mod 'gtk)
  (mkdir-p (~ "~a/.local/bin" home))
  (run-heks-install-config-script 'gtk-dconf
                                  #:mod 'gtk))

(define (install-flatpak)
  "Install Flatpak packages."
  (time-machine-manifest-shell
   (list "guile" "-L" "./src" "-c"
         "'((@(heks-linux packages flatpak) install-flatpak))'")
   #:verbose? #t))

(define (gc-flatpak)
  "Garbage collection of Flatpak."
  (run (list "flatpak" "uninstall" "--unused")
       #:verbose? #t))

(define (update-flatpak)
  "Update Flatpak packages."
  (run (list "flatpak" "update" "-y")
       #:verbose? #t)
  (gc-flatpak))

(define (guix-pull)
  "Update Guix channels to the pinned ones.

channels.scm is copied to ~/.config/guix/trusted-channels.scm first.  Guix
only pulls a channel that carries an introduction if the channel is one of the
trusted ones -- those in that file, or else the channels the running guix
already has -- and without it the first pull after a channel is added warns
that the channel is not trusted."
  (run (list "install" "-D" "-m" "644" "channels.scm"
             (~ "~a/.config/guix/trusted-channels.scm" home))
       #:verbose? #t)
  (run (list "guix" "pull" "--channels=channels.scm")
       #:verbose? #t)
  ;; `hash' is a shell builtin -- there is no program to run -- so this line
  ;; keeps its shell.
  ($ '("hash guix")
     #:verbose? #t))

(define (update-guix)
  "Update Guix packages."
  (guix-pull)
  (run (list "guix" "upgrade")
       #:verbose? #t)
  (gc-guix))

(define (gc-guix)
  "Garbage collection of Guix."
  (run (list "guix" "gc")
       #:verbose? #t))

(define (install-zypper)
  "Install Heks Linux system Zypper packages (openSUSE, SLE, etc)."
  (time-machine-manifest-shell
   (list "guile" "-L" "./src" "-c"
         "'((@(heks-linux packages zypper) install-zypper))'")
   #:verbose? #t))

(define (update-zypper)
  "Update Zypper package manager."
  (run (list "zypper" "refresh")
       #:sudo? #t #:verbose? #t)
  (run (list "zypper" "update" "-y")
       #:sudo? #t #:verbose? #t)
  (run (list "zypper" "dup")
       #:sudo? #t #:verbose? #t))

(define (update-nix)
  "Update Nix packages."
  (run (list "nix-env" "--upgrade")
       #:verbose? #t)
  (gc-nix))

(define (gc-nix)
  "Garbage collect Nix."
  (run (list "nix-env" "--delete-generations" "old")
       #:verbose? #t)
  (run (list "nix-store" "--gc")
       #:verbose? #t))

(define (install-whitesur-icons)
  "Install WhiteSur icons."
  (let ((dest (~ "~a/.config/whitesur-icon-theme" home)))
    (delete-file-recursively dest
                             #:verbose? #f)
    (git-clone "https://github.com/vinceliuice/WhiteSur-icon-theme.git"
               #:directory dest)
    ;; `cd DEST && ./install.sh': the script is run from the tree it belongs
    ;; to, so `with-directory' says where rather than a shell sequence.
    (with-directory dest
      (lambda ()
        (run (list "./install.sh" "--theme" "all"))))))

(define (install-whitesur-cursors)
  "Install WhiteSur cursors."
  (let ((dest (~ "~a/.config/whitesur-cursor-theme" home)))
    (delete-file-recursively dest)
    (git-clone "https://github.com/vinceliuice/WhiteSur-cursors.git"
               #:directory dest)
    (with-directory dest
      (lambda ()
        (run (list "./install.sh"))))))

(define (install-icon-files)
  "Install icon packs."
  (install-whitesur-icons)
  (install-whitesur-cursors))

(define (install-wallpaper-files)
  "Install wallpaper files and images."
  (mkdir-p (~ "~a/.local/bin" home))
  (let ((dest (~ "~a/.config/digital-art-dreams" home)))
    (delete-file-recursively dest)
    (git-clone "https://codeberg.org/jjba23/digital-art-dreams.git"
               #:directory dest)))

(define (install-wallpapers)
  "Install the wallpaper engine, its picker and the rotation timer, then
re-apply the wallpaper that is on record."
  (mkdir-p (~ "~a/.config/systemd/user/" home))
  ;; The engine used to ship as random-wallpaper.{service,timer} around a
  ;; user-script-set-random-wallpaper script, and that service never exited, so
  ;; the timer could never fire twice.  Retire all three, or a machine that has
  ;; been running them keeps an inert timer pointing at a script this module no
  ;; longer writes.
  (run (list "systemctl" "--user" "disable" "--now" "random-wallpaper.timer")
       #:allow-failure? #t)
  (run (list "rm" "-f"
             (~ "~a/.local/bin/user-script-set-random-wallpaper" home)
             (~ "~a/.config/systemd/user/random-wallpaper.service" home)
             (~ "~a/.config/systemd/user/random-wallpaper.timer" home))
       #:allow-failure? #t)
  (run-heks-install-config-script 'wallpaper)
  (run (list "systemctl" "--user" "daemon-reload"))
  (run (list "systemctl" "--user" "enable" "--now" "heks-wallpaper.timer"))
  ;; Re-apply what is on record, so the engine's first act is not to wait for
  ;; the rotation timer.  It discovers the Wayland socket itself, so this works
  ;; from a task runner that has no session environment.
  (run (list (~ "~a/.local/bin/heks-wallpaper" home) "restore")
       #:allow-failure? #t))

(define (install-emacs-bridge)
  "Install bridge to Emacs configuration files."
  (mkdir-p (~ "~a/.emacs.d" home))
  (run-heks-install-config-script 'heks-linux-to-emacs-bridge
                                  #:mod 'bridges))

(define (install-bash-bridge)
  "Install bridge to Bash configuration files."
  (run-heks-install-config-script 'heks-linux-to-bash-bridge
                                  #:mod 'bridges))

(define (install-containers-config)
  "Install Podman containers configuration files."
  (mkdir-p (~ "~a/.config/containers" home))
  (run-heks-install-config-script 'containers-registries
                                  #:mod 'containers)
  (run-heks-install-config-script 'containers-policy
                                  #:mod 'containers))

(define (default)
  "Default task to run, call program's help."
  (list-tasks))

(define has-formatted-already?
  #f)
(define (fmt)
  "Format Scheme source code files according to the Guix style guide."
  (unless has-formatted-already?
    (run (list "find" "." "-maxdepth" "8" "-name" "*.scm"
               "-type" "f" "-exec" "guix" "style" "-f" "{}" ";")
         #:verbose? #t)
    (set! has-formatted-already? #t)))

(define (repl)
  "Development REPL."
  (time-machine-manifest-shell (list "guile" "-L" "./src"
                                     "-c" "'((@ (ares server) run-nrepl-server))'")))

(define (home-reconfigure)
  "Complete home reconfigure."
  (setenv "SCRIBA_LOGGER" "color-console")
  (compile)
  (install-gif)
  (install-lambdock)
  (install-niri)
  (install-mako)
  (install-btop)
  (install-keybindings)
  (install-git)
  (install-rofi)
  (install-fastfetch)
  (install-gtk)
  (install-dconf)
  (install-rmpc)
  (install-wallpapers)
  (install-wezterm)
  (install-zen)
  (install-emacs-bridge)
  (install-bash-bridge)
  (install-waybar)
  (install-containers-config)
  ;; `|| true': a surface that is not running is the normal case, so the exit
  ;; status is not the task's business.
  (run (list "pkill" "waybar") #:allow-failure? #t)
  (run (list "setsid" "waybar") #:async? #t #:dev-null? #t)
  (run (list "pkill" "mako") #:allow-failure? #t)
  (run (list "setsid" "mako") #:async? #t #:dev-null? #t)
  (run (list "write-gtk-dconf-settings") #:allow-failure? #t)
  (run (list "write-heks-linux-dconf-settings") #:allow-failure? #t)
  (run (list "fyi" "-i" "emblem-success"
             "Succesfully completed home-reconfigure on heks-linux")
       #:allow-failure? #t))

(define (install-theme)
  "Re-render every palette-dependent configuration file.

This is the entry point used by the Rofi theme picker: after the palette is
changed in ~/.config/heks-linux/local-settings.scm, this task regenerates the
dotfiles that embed colours and restarts the surfaces that have no hot reload
(Waybar and Mako)."
  (setenv "SCRIBA_LOGGER" "color-console")
  (install-gtk)
  (install-dconf)
  (install-niri)
  (install-waybar)
  (install-mako)
  (install-rofi)
  (install-keybindings)
  (install-wezterm)
  (install-zen)
  (install-btop)
  (install-lambdock)
  (install-wallpapers)
  (run (list "pkill" "waybar") #:allow-failure? #t)
  (run (list "setsid" "waybar") #:async? #t #:dev-null? #t)
  (run (list "pkill" "mako") #:allow-failure? #t)
  (run (list "setsid" "mako") #:async? #t #:dev-null? #t)
  (run (list "write-gtk-dconf-settings") #:allow-failure? #t)
  (run (list "write-heks-linux-dconf-settings") #:allow-failure? #t)
  (run (list "fyi" "-i" "emblem-success"
             "Applied the new Heks Linux theme")
       #:allow-failure? #t))

(define (test)
  "Unit tests, run in a hermetic container."
  (delete-file-recursively "reports/lcov/coverage*"
                           #:verbose? #f
                           #:expand? #t)
  (delete-file-recursively "reports/html"
                           #:verbose? #f)
  (time-machine-manifest-container-shell
   (list "guile" "-L" "./src" "-L" "./test"
         "-c" "'((@ (veritas runner) run-tests))'")
   #:verbose? #t)
  (coverage-report))

(define (update)
  "Update system and all packages."
  (update-flatpak)
  (update-zypper)
  (update-nix)
  (update-guix))

(define (install-kotlin-lsp)
  "Install Kotlin Language Server (by JetBrains)"
  (let* ((release "262.9593.0")
         (download-dest (~ "~a/Downloads/kotlin-lsp-latest.tar.gz" home))
         (extract-dest (~ "~a/Downloads/kotlin-lsp-latest" home))
         (bin-dest (~ "~a/.local/bin/intellij-server" home))
         (server (~ "~a/kotlin-server-~a/bin/intellij-server"
                    extract-dest release)))
    (delete-file-recursively download-dest)
    (delete-file-recursively extract-dest)
    (delete-file-recursively bin-dest)
    (curl-download
     (~ "https://download-cdn.jetbrains.com/language-server/kotlin-server/~a/kotlin-server-~a.tar.gz"
        release release)
     #:output download-dest
     #:verbose? #t)
    (mkdir-p extract-dest)
    (tar-extract download-dest #:directory extract-dest #:verbose? #t)
    (chmod-file "755" server)
    (ln-s server bin-dest #:force? #f)))

(define (validate)
  "Format, compile and test."
  (fmt)
  (compile)
  (test))

(define (coverage-report)
  "Make test coverage report."
  ;; A glob and a silenced command: the shell expands the .info files and the
  ;; report's chatter is not the report.  A failure is not a failure either --
  ;; the tests have already run and said what they had to say.
  (run (list "genhtml" "reports/lcov/*.info"
             "--output-directory" "reports/html")
       #:expand? #t #:dev-null? #t #:allow-failure? #t))

(define (deploy)
  "Deploy the project's documentation."
  (docs)
  (remkdir-p (~ "~a/api-docs/~a" deploy-api-docs-dir project-name))
  (mv "doc/api-dist/*"
      (~ "~a/api-docs/~a" deploy-api-docs-dir project-name)
      #:expand? #t)
  (delete-file-recursively "doc"))

(define (docs)
  "Generate technical API documentation."
  (delete-file-recursively "doc")
  ;; Two calls rather than one `&&' chain, so the renderer only runs where the
  ;; generator succeeded and fails where it happens.
  (time-machine-manifest-shell
   (list "documenta" "api" (~ "./src/~a" project-name))
   #:verbose? #t)
  (time-machine-manifest-shell
   (list "texi2any" "-v" "--html"
         (~ "--css-ref=~a" api-docs-css-url)
         "-o" "index_html" "./doc/api/index.texi")
   #:verbose? #t)
  (mv "./index_html" "./doc/api-dist"))
