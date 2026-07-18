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

;; ====== Maak tasks ======

(define* (run-heks-install-config-script func
                                         #:key (mod #f)
                                         (config-suffix? #t) verbose?)
  (let ((mod (~ "'((@(heks-linux ~a) install-~a~a))'"
                (if mod mod func) func
                (if config-suffix? "-config" ""))))
    (time-machine-manifest-shell (list "guile -L ./src -c" mod)
                                 #:verbose? verbose?)))

(define (compile)
  "Compile all project source code."
  (time-machine-manifest-shell (list "guild compile -L ./src" "-W3"
                                     "./src/**/*.scm")))

(define (install-alacritty)
  "Install Alacritty config files."
  (mkdir-p "~/.config/alacritty")
  (run-heks-install-config-script 'alacritty))

(define (install-waybar)
  "Install Waybar config files."
  (mkdir-p "~/.config/waybar")
  (run-heks-install-config-script 'waybar))

(define (install-rofi)
  "Install Niri config files."
  (mkdir-p "~/.config/rofi")
  (run-heks-install-config-script 'rofi))

(define (install-niri)
  "Install Niri config files."
  (mkdir-p "~/.config/niri")
  (run-heks-install-config-script 'niri))

(define (install-kitty)
  "Install Kitty config files."
  (mkdir-p "~/.config/kitty")
  (run-heks-install-config-script 'kitty))

(define (install-mako)
  "Install Mako config files."
  (mkdir-p "~/.config/mako")
  (run-heks-install-config-script 'mako))

(define (install-btop)
  "Install Btop config files."
  (mkdir-p "~/.config/btop")
  (run-heks-install-config-script 'btop))

(define (install-git)
  "Install Git config files."
  (run-heks-install-config-script 'git))

(define (install-dconf)
  "Install DConf config files."
  (run-heks-install-config-script 'dconf))

(define (install-fastfetch)
  "Install FastFetch config files."
  (mkdir-p "~/.config/fastfetch")
  (run-heks-install-config-script 'fastfetch))

(define (install-gtk)
  "Install GTK config files."
  (mkdir-p "~/.config/gtk-3.0")
  (run-heks-install-config-script 'gtk3
                                  #:mod 'gtk)
  (mkdir-p "~/.config/gtk-4.0")
  (run-heks-install-config-script 'gtk4
                                  #:mod 'gtk)
  (mkdir-p "~/.local/bin")
  (run-heks-install-config-script 'gtk-dconf
                                  #:mod 'gtk)
  (run-heks-install-config-script 'dconf))

(define (install-flatpak)
  "Install Flatpak packages."
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux packages flatpak) install-flatpak))'")
                               #:verbose? #t))

(define (gc-flatpak)
  "Garbage collection of Flatpak."
  ($ '("flatpak uninstall --unused")
     #:verbose? #t))

(define (update-flatpak)
  "Update Flatpak packages."
  ($ '("flatpak update -y")
     #:verbose? #t)
  (gc-flatpak))

(define (guix-pull)
  "Update Guix channels to the pinned ones."
  ($ '("guix pull" "--channels=channels.scm")
     #:verbose? #t)
  ($ '("hash guix")
     #:verbose? #t))

(define (update-guix)
  "Update Guix packages."
  (guix-pull)
  ($ '("guix upgrade")
     #:verbose? #t)
  (gc-guix))

(define (gc-guix)
  "Garbage collection of Guix."
  ($ '("guix gc")
     #:verbose? #t))

(define (install-dnf)
  "Install Heks Linux system DNF packages (RPM Fedora, RedHat, etc)."
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux packages dnf) install-dnf))'")
                               #:verbose? #t))

(define (install-apt)
  "Install Heks Linux system APT packages (DEB Debian, Ubuntu, etc)."
  (time-machine-manifest-shell (list "guile -L ./src -c"
                                "'((@(heks-linux packages apt) install-apt))'")
                               #:verbose? #t))

(define (update-dnf)
  "Update DNF package manager."
  ($ '("sudo dnf update -y")
     #:verbose? #t)
  ($ '("sudo dnf upgrade --refresh")
     #:verbose? #t))

(define (update-apt)
  "Update APT package manager."
  ($ '("sudo apt update -y")
     #:verbose? #t)
  ($ '("sudo apt upgrade -y")
     #:verbose? #t))

(define (update-nix)
  "Update Nix packages."
  ($ '("nix-env --upgrade")
     #:verbose? #t)
  (gc-nix))

(define (gc-nix)
  "Garbage collect Nix."
  ($ '("nix-env --delete-generations old")
     #:verbose? #t)
  ($ '("nix-store --gc")
     #:verbose? #t))

(define (install-wallpaper-files)
  "Install wallpaper files and images."
  (mkdir-p "~/.local/bin")
  ($ '("rm -rf ~/.config/digital-art-dreams"))
  ($ '("git clone https://codeberg.org/jjba23/digital-art-dreams.git ~/.config/digital-art-dreams")))

(define (install-wallpapers)
  "Install wallpaper configuration files."
  (mkdir-p "~/.config/systemd/user/")
  (run-heks-install-config-script 'wallpaper)
  ($ '("systemctl --user daemon-reload"))
  ($ '("systemctl --user enable --now random-wallpaper.timer")))

(define (install-emacs-bridge)
  "Install bridge to Emacs configuration files."
  (mkdir-p "~/.emacs.d")
  (run-heks-install-config-script 'heks-linux-to-emacs-bridge
                                  #:mod 'bridges))

(define (install-bash-bridge)
  "Install bridge to Bash configuration files."
  (run-heks-install-config-script 'heks-linux-to-bash-bridge
                                  #:mod 'bridges))

(define (install-containers-config)
  "Install Podman containers configuration files."
  (mkdir-p "~/.config/containers")
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
    ($ '("find . -maxdepth 8 -name '*.scm'"
         "-type f -exec guix style -f {} \\;")
       #:verbose? #t)
    (set! has-formatted-already? #t)))

(define (repl)
  "Development REPL."
  (time-machine-manifest-shell '("guile -L ./src"
                                 "-c '((@ (ares server) run-nrepl-server))'")))

(define (home-reconfigure)
  "Complete home reconfigure."
  (setenv "SCRIBA_LOGGER" "color-console")
  (compile)
  (install-alacritty)
  (install-niri)
  (install-mako)
  (install-btop)
  (install-git)
  (install-rofi)
  (install-fastfetch)
  (install-gtk)
  (install-dconf)
  (install-wallpapers)
  (install-kitty)
  (install-emacs-bridge)
  (install-bash-bridge)
  (install-waybar)
  (install-containers-config)
  ($ '("pkill waybar || true"))
  ($ '("setsid waybar > /dev/null 2>&1 &"))
  ($ '("pkill mako || true"))
  ($ '("setsid mako > /dev/null 2>&1 &"))
  ($ '("fyi -i emblem-success \"Succesfully completed home-reconfigure on heks-linux\"")))

(define (reconfigure)
  "Complete system reconfigure."
  (home-reconfigure)
  (update-flatpak)
  (install-flatpak)
  (update-dnf)
  (install-dnf)
  (install-wallpapers)
  ($ '("fastfetch || true")))

(define (test)
  "Unit tests."
  (delete-file-recursively "reports/lcov/coverage*"
                           #:verbose? #f)
  (delete-file-recursively "reports/html"
                           #:verbose? #f)
  (time-machine-manifest-shell '("guile -L ./src -L ./test"
                                 "-c '((@ (veritas runner) run-tests))'")
                               #:verbose? #t)
  (coverage-report))

(define (update)
  "Update system and all packages."
  (update-flatpak)
  (update-dnf)
  (update-nix)
  (update-guix))

(define (install-kotlin-lsp)
  "Install Kotlin Language Server (by JetBrains)"
  (let* ((release "262.8190.0")
         (download-dest "~/Downloads/kotlin-lsp-latest.tar.gz")
         (extract-dest "~/Downloads/kotlin-lsp-latest")
         (bin-dest "~/.local/bin/intellij-server"))
    (delete-file-recursively download-dest)
    (delete-file-recursively extract-dest)
    (delete-file-recursively bin-dest)
    ($ (list "curl --verbose"
             (~
              "https://download-cdn.jetbrains.com/language-server/kotlin-server/~a/kotlin-server-~a.tar.gz"
              release release)
             (~ "--output ~a" download-dest))
       #:verbose? #t)
    (mkdir-p extract-dest)
    ($ (list "tar -xf" download-dest "-C" extract-dest) #:verbose? #t)
    ($ (list (~ "chmod +x ~a/kotlin-server-~a/bin/intellij-server" extract-dest release)))
    ($ (list "ln -s"
             (~ "~a/kotlin-server-~a/bin/intellij-server" extract-dest release) bin-dest))))

(define (validate)
  "Format, compile and test."
  (fmt)
  (compile)
  (test))

(define (coverage-report)
  "Make test coverage report."
  (catch #t
         (lambda ()
           ($ '("genhtml reports/lcov/*.info --output-directory reports/html &> /dev/null")))
         (lambda (key . args)
           #f)))

(define (deploy)
  "Deploy the project's documentation."
  (docs)
  (remkdir-p (~ "~a/api-docs/~a" deploy-api-docs-dir project-name))
  (mv "doc/api-dist/*"
      (~ "~a/api-docs/~a" deploy-api-docs-dir project-name))
  (delete-file-recursively "doc"))

(define (docs)
  "Generate technical API documentation."
  (delete-file-recursively "doc")
  (time-machine-manifest-shell (list (~ "documenta api ./src/~a && "
                                        project-name)
                                     (~
                                      "texi2any -v --html --css-ref=~a -o index_html"
                                      api-docs-css-url) "./doc/api/index.texi")
                               #:verbose? #t)
  (mv "./index_html" "./doc/api-dist"))
