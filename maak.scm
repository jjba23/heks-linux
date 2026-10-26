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
  #:use-module (maak maak)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1))

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

;; The revision of nix-jointhefreeworld this configuration installs its Nix
;; packages from, pinned the way channels.scm pins the Guix side of the same
;; collection.  `maak install-heks-toon' installs from it, so two machines that
;; run this file get the same build instead of whatever trunk happens to be.
;; Kept at the release channels.scm pins - heks-toon 0.3.2, lambdock 0.12.0,
;; maak 0.14.0, veritas 0.9.0 and scriba 0.4.5 - so the Nix-installed half of the
;; collection is not a release behind the Guix-installed half.
(define nix-jointhefreeworld-revision
  "a8378d7e538248bec7d1e4f80cc270ad27164ab6")

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

;; The surfaces whose contents embed palette colours, as (module function) pairs
;; naming each `install-FUNCTION-config'.
;;
;; The GTK surfaces are listed apart from the rest because they are written as a
;; pass of their own, with the dconf keys applied in between.  See
;; `render-configs' for why that split is what makes the icons follow a switch.
(define theme-gtk-surfaces
  '((gtk gtk3)
    (gtk gtk4)
    (gtk gtk-dconf)))

(define theme-other-surfaces
  '((dconf dconf)
    (niri niri)
    (waybar waybar)
    (mako mako)
    (rofi rofi)
    (wezterm wezterm)
    (zen zen)
    (btop btop)
    (lambdock lambdock)
    (wallpaper wallpaper)
    ;; The bridge is how Emacs learns the theme and the fonts.  It belongs here
    ;; because a palette switch that repaints the desktop and leaves Emacs
    ;; reading yesterday's file is a switch that only half happened.
    (bridges heks-linux-to-emacs-bridge)))

;; Every surface a palette switch re-renders, in the order it is written.
(define theme-surfaces
  (append theme-gtk-surfaces
          theme-other-surfaces))

;; The files a home reconfigure writes that a palette does not touch.  Together
;; with `theme-surfaces' this is the whole of `maak home-reconfigure'.
(define home-surfaces
  '((gif gif)
    (git git)
    (fastfetch fastfetch)
    (fontconfig fontconfig)
    (rmpc rmpc)
    (toon toon)
    (containers containers-registries)
    (containers containers-policy)
    (bridges heks-linux-to-bash-bridge)))

(define* (run-heks-install-config-scripts surfaces #:key verbose?)
  "Render every surface in @var{surfaces} inside one Guile process.

@var{surfaces} is a list of @code{(module function)} pairs, each naming the
@code{install-FUNCTION-config} procedure of that module.  Entering the pinned
manifest shell once for thirteen files is what makes a palette switch feel like
a click; entering it thirteen times is what made it feel like a build."
  (let ((calls (string-join (map (lambda (surface)
                                   (format #f
                                           "((@(heks-linux ~a) install-~a-config))"
                                           (car surface)
                                           (cadr surface)))
                                 surfaces)
                            "\n       ")))
    (time-machine-manifest-shell
     (list "guile" "-L" "./src" "-c"
           (format #f "'(begin ~a)'" calls))
     #:verbose? verbose?)))

(define* (render-configs surfaces #:key verbose?)
  "Render @var{surfaces}, with the GTK pass and its dconf keys first.

@var{surfaces} is every surface to write, as @code{(module function)} pairs; the
GTK ones are rendered first and skipped in the second pass, so a caller can pass
the whole list it has - @code{theme-surfaces}, or that plus
@code{home-surfaces}.

The order is not cosmetic.  GTK is where the icon theme comes from, and a
running surface rebuilds itself when its own file is rewritten - lambdock
re-resolves every launcher icon about 150ms after its settings file changes.  A
switch that rewrote the dock in the same pass as everything else applied the
dconf keys seconds later, so the dock rebuilt its launchers from the icon theme
of the palette being *left* and kept them until the next switch.  Writing the
GTK files first, applying dconf, and only then rewriting the surfaces that
reload themselves is what makes the icons follow the palette."
  (run-heks-install-config-scripts theme-gtk-surfaces #:verbose? verbose?)
  (apply-dconf-settings)
  (run-heks-install-config-scripts (lset-difference equal?
                                                   surfaces
                                                   theme-gtk-surfaces)
                                   #:verbose? verbose?))

(define (apply-dconf-settings)
  "Write the GTK and Heks Linux dconf keys from the current settings.

Both writers are generated scripts, and both are called by absolute path rather
than by name: a palette picker started from a session whose PATH has no
@file{~/.local/bin} would miss them, and `#:allow-failure?' swallows that
silently.  A switch that repaints every dotfile and leaves the icon theme where
it was is exactly what that looked like from the outside."
  (run (list (~ "~a/.local/bin/write-gtk-dconf-settings" home))
       #:allow-failure? #t #:verbose? #t)
  (run (list (~ "~a/.local/bin/write-heks-linux-dconf-settings" home))
       #:allow-failure? #t #:verbose? #t))

(define (reload-surfaces)
  "Ask the running surfaces to read their configuration again.

Waybar and Mako both keep their file in memory but both can be told to reread
it, so a palette change reloads them instead of killing and restarting them -
no flicker, no lost bar state, and a surface that was not running is started.
Niri watches its own config and reloads as soon as the file is written.

Waybar exits when the configuration it reloads is malformed, which would leave a
session with no bar at all, so the reload is followed by a liveness check rather
than trusted.

Lambdock is deliberately not in this list: it watches its own configuration
directory and rebuilds its launchers when the renderer rewrites it, which is why
`render-configs' applies the icon theme before that happens rather than asking
the dock to start over here."
  ($ '("pkill -SIGUSR2 waybar || true; sleep 0.4; pgrep -x waybar >/dev/null || (setsid waybar >/dev/null 2>&1 &)")
     #:allow-failure? #t)
  ($ '("makoctl reload || (setsid mako >/dev/null 2>&1 &)")
     #:allow-failure? #t))

;; How many `guild compile' workers one compile may run at once.  Measured
;; rather than guessed: on twelve cores, eight workers took 2.6s and twelve took
;; 1.9s, because each worker parses its file and the modules it imports from
;; scratch.  The cap only keeps a very wide machine from starting a Guile per
;; core for twenty-odd files.
(define compile-worker-limit
  16)

(define (compile-source-files)
  "Return the project's module files, sorted, as paths from the project root."
  (map (lambda (name)
         (~ "./src/heks-linux/~a" name))
       (scandir "src/heks-linux"
                (lambda (name)
                  (string-suffix? ".scm" name)))))

(define (split-into-groups files groups)
  "Split @var{files} into at most @var{groups} contiguous groups of equal size.
A group is one worker's queue: the worker compiles its files in that order, so
the split is contiguous rather than round-robin to keep related modules together."
  (let ((size (ceiling (/ (length files) groups))))
    (let loop ((rest files) (acc '()))
      (if (null? rest) (reverse acc)
          (let ((count (min size (length rest))))
            (loop (drop rest count)
                  (cons (take rest count) acc)))))))

(define (compile-script groups)
  "Return a POSIX shell script that compiles @var{groups} in parallel.

Each group is one worker with a bytecode cache of its own, under a temporary
directory, and it compiles its files one `guild compile' at a time.

Both details are load-bearing.  A compiling Guile *loads* the modules it
imports while other workers may be writing their bytecode, and a worker reading
a half-written @file{.go} fails the run; a private cache makes every read see
either a finished file or no file at all.  One file per invocation, rather than
one invocation per group, is what keeps a worker from compiling a module in the
same call that loads it: `guild compile a.scm b.scm' where one depends on the
other is the other way to get an unbound-variable error out of a cold cache.

The script merges what the workers produced into the shared cache before it
exits, so the tree is still compiled for everything that runs afterwards, and it
exits non-zero if any worker did."
  (let* ((workers (let loop ((rest groups) (index 1) (acc '()))
                    (if (null? rest) (reverse acc)
                        (loop (cdr rest)
                              (+ index 1)
                              (cons (format #f
                                            "compile_group \"$work/~a\" ~a & pid~a=$!"
                                            index
                                            (string-join (car rest) " ")
                                            index)
                                    acc)))))
         (waited (map (lambda (index)
                        (format #f "wait $pid~a || fail=1" index))
                      (iota (length groups) 1))))
    (string-join (append (list "work=$(mktemp -d)"
                               "cache=${XDG_CACHE_HOME:-$HOME/.cache}/guile/ccache"
                               ;; The cache mirrors the source tree without its
                               ;; leading slash, so the script needs the project
                               ;; root in that form to find what to merge.
                               "project=$(pwd -P)"
                               "project=${project#/}"
                               "fail=0"
                               "compile_group() {"
                               "  dir=$1"
                               "  shift"
                               "  for file in \"$@\"; do"
                               "    XDG_CACHE_HOME=\"$dir\" guild compile -L ./src -W3 \"$file\" || return 1"
                               "  done"
                               "}")
                         workers
                         waited
                         (list "for dir in \"$work\"/*/; do"
                               "  for abi in \"$dir\"guile/ccache/*/; do"
                               "    [ -d \"$abi$project/src\" ] || continue"
                               "    name=${abi%/}"
                               "    name=${name##*/}"
                               "    mkdir -p \"$cache/$name/$project/src\""
                               "    cp -a \"$abi$project/src/.\" \"$cache/$name/$project/src/\""
                               "  done"
                               "done"
                               "rm -rf \"$work\""
                               "exit $fail"))
                 "\n")))

(define (compile)
  "Compile all project source code, in parallel workers.

A compile used to be a single @code{guild compile} over the whole tree, and it
was the slowest step of a reconfigure, ahead of rendering everything the
reconfigure writes.  Every file goes through a compiler that parses it and its
imports from scratch - work that splits cleanly - so the files are cut into
groups and compiled side by side, and the task fails if any worker did."
  (let* ((files (compile-source-files))
         (workers (max 1
                       (min compile-worker-limit
                            (current-processor-count)
                            (length files))))
         (groups (split-into-groups files workers)))
    (time-machine-manifest-shell
     (list "sh" "-c" (format #f "'~a'" (compile-script groups))))))

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

(define (install-toon)
  "Retire the HTML pages heks-toon replaces.
heks-toon is a program of its own (see `install-heks-toon'), so the pages left
only one thing to do: remove the launchers and the generated keyboard reference
they installed, so a machine that had the pages does not keep scripts that open
documents nothing writes any more."
  (mkdir-p (~ "~a/.local/bin" home))
  (run-heks-install-config-script 'toon))

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
  "Install GTK config files and apply them.
The three GTK surfaces of @code{theme-gtk-surfaces} are written by one Guile
process instead of three, and the dconf keys are applied straight afterwards:
the files on disk only take effect once dconf has them, and the icon theme is
one of those keys."
  (run-heks-install-config-scripts theme-gtk-surfaces #:verbose? #t)
  (apply-dconf-settings))

(define (install-fontconfig)
  "Install the font rendering rules.

This is the file that decides text is smoothed in grey, hinted lightly and left
alone by the LCD filter - the Mac's rendering - rather than rendered as subpixel
text.  It sits beside the surfaces that choose fonts rather than with them: it is
read by every fontconfig client on the machine, not by one program."
  (mkdir-p (~ "~a/.config/fontconfig" home))
  (run-heks-install-config-script 'fontconfig))

(define (install-heks-toon)
  "Install heks-toon, the window behind the keyboard, wallpaper and palette views.

It is installed from nix-jointhefreeworld rather than from the distribution:
heks-toon is part of the jointhefreeworld collection, `nix profile' is how this
configuration puts that collection's programs on the machine (`maak' itself
comes from there), and the flake pins the set at one revision instead of
tracking a branch.  The revision is `nix-jointhefreeworld-revision', at the top
of this file, and channel.scm pins the Guix half of the same collection.

heks-toon is installed, not configured: it reads the palette from
~/.config/heks-linux/local-settings.scm, the wallpapers from the collection
`maak install-wallpaper-files' clones, and asks `heks-rofi-theme-menu' and
`heks-wallpaper' - both of which this configuration already installs - to do the
switching."
  ;; `nix profile install' refuses a package the profile already has, and what
  ;; this task promises is the *pinned* build, so the old copy goes first.
  (run (list "nix" "profile" "remove" "heks-toon")
       #:allow-failure? #t)
  (run (list "nix" "profile" "install"
             (~ "git+https://codeberg.org/jjba23/nix-jointhefreeworld?rev=~a#heks-toon"
                nix-jointhefreeworld-revision))
       #:verbose? #t))

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
  "Update Guix packages.

The upgrade runs through @code{pulled-guix}, not through whatever @code{guix} is
first on @file{PATH}.  On a foreign distribution that is the installer's guix,
which knows only the default channels: asked to upgrade, it answers that
lambdock and skeu-icons no longer exist and upgrades nothing that comes from the
jointhefreeworld channel - the packages this configuration is built from.  The
pull still uses PATH's guix, because pulling is what writes the profile that
@code{pulled-guix} then names."
  (guix-pull)
  (run (list (pulled-guix) "upgrade")
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

;; ====== The live image ======

;; A description, a build directory and a log, all under `dist/', which git
;; already ignores: an image is an artefact, not a source file.
(define image-description-dir
  "dist/image")

(define image-build-target-dir
  "dist/iso")

(define image-build-log
  "dist/image-build.log")

;; What the build needs around it.  The number is generous on purpose - the
;; chroot, the unpacked image and the ISO all exist at once - because a build
;; that dies of a full disk at ninety percent is an hour spent to learn a number
;; that `df' prints in a second.
(define image-minimum-free-gigabytes
  25)

(define (image-build-tooling-installed?)
  "Return @code{#t} when @command{kiwi-ng} is on the PATH."
  (zero? (system* "sh" "-c" "command -v kiwi-ng >/dev/null 2>&1")))

(define (image-build-space-adequate? directory)
  "Return @code{#t} when @var{directory}'s filesystem has room for a build.

An unreadable answer counts as adequate: `df' failing is not a reason to refuse
to build, and the build itself will say so if it runs out."
  (zero?
   (system* "sh" "-c"
            (~ "avail=$(df -BG --output=avail '~a' 2>/dev/null | tail -1 | tr -dc '0-9')
               [ -z \"$avail\" ] || [ \"$avail\" -ge ~a ]"
               directory image-minimum-free-gigabytes))))

(define (image-render)
  "Render the image description into `dist/image'.

No root, no network, no build: five files - the KIWI description, its two build
scripts, and the re-render tool and unit it installs - written into
`dist/image', where they can be read, diffed and validated.  That is what a
change to the image has to be reviewable as, before a build that costs a couple
of hours and a dozen gigabytes."
  (time-machine-manifest-shell
   (list "guile" "-L" "./src" "-c"
         (~ "'((@(heks-linux image) install-image-config) #:dir \"~a\")'"
            image-description-dir))
   #:verbose? #t))

(define (image-check)
  "Check the rendered description without building it.

KIWI's own reader validates the description and resolves its package list, which
takes seconds and catches the things that cost an hour: a package name that does
not exist on this distribution, or an element the schema wants elsewhere.  No
root, and the same tooling the build needs."
  (image-render)
  (unless (image-build-tooling-installed?)
    (error (string-append "kiwi-ng is not installed on this machine.  On Slowroll:"
                          " sudo zypper install python3-kiwi kiwi-systemdeps-iso-media")))
  (run (list "kiwi-ng" "image" "info"
             "--description" image-description-dir)
       #:verbose? #t))

(define (image)
  "Build the Heks-Linux images with KIWI.

Two artefacts from one description: a live ISO you can boot, and an OEM image
plus an install ISO you can put on a disk.  KIWI is a system package on openSUSE
rather than one of this project's Guix dependencies - it mounts filesystems and
writes a raw disk image - so the build runs on the host, through sudo, after the
description has been rendered in the pinned shell.  On Slowroll:

  sudo zypper install python3-kiwi kiwi-systemdeps-iso-media

What the build does inside the image is the point of it: `config.sh' installs the
desktop's Guix and Nix stores, renders every dotfile, and refuses to finish if
any of it is missing.  The result is `dist/iso/heks-linux-<version>-live.iso'
and `dist/iso/heks-linux-<version>-install.raw'."
  (image-render)
  (unless (image-build-tooling-installed?)
    (error (string-append "kiwi-ng is not installed on this machine.  On Slowroll:"
                          " sudo zypper install python3-kiwi kiwi-systemdeps-iso-media")))
  (unless (image-build-space-adequate? ".")
    (error (~ "an image build needs about ~a GB free beside the checkout"
              image-minimum-free-gigabytes)))
  (run (list "kiwi-ng"
             "--logfile" image-build-log
             "system" "build"
             "--description" image-description-dir
             "--target-dir" image-build-target-dir)
       #:sudo? #t #:verbose? #t))

(define (update-nix)
  "Update Nix packages.
Both kinds of profile are updated: the classic `nix-env' ones, and the ones
`nix profile' manages, which is where `install-heks-toon' puts its package.
A machine whose profile has already been taken over by `nix profile' has no
classic one left, and `nix-env --upgrade' then fails with an answer rather than
an error - that is why its failure is allowed, and why the `nix profile' upgrade
is the one whose result matters."
  (run (list "nix-env" "--upgrade")
       #:allow-failure? #t
       #:verbose? #t)
  (run (list "nix" "profile" "upgrade" "--all")
       #:allow-failure? #t)
  (gc-nix))

(define (gc-nix)
  "Garbage collect Nix."
  (run (list "nix-env" "--delete-generations" "old")
       #:verbose? #t)
  (run (list "nix-store" "--gc")
       #:verbose? #t))

(define (pulled-guix)
  "The guix that `guix pull' installed, which is the one that knows the channels.
On a foreign distribution /usr/local/bin/guix comes first on PATH and belongs to
the installer, so it carries only the default channels: `guix install
skeu-icons' there answers ``unknown package'' even after `maak guix-pull'.  The
pulled binary lives at ~/.config/guix/current and is what this returns; a
machine where no pull has happened yet falls back to whatever PATH finds."
  (let ((pulled (~ "~a/.config/guix/current/bin/guix" home)))
    (if (file-exists? pulled) pulled "guix")))

(define (install-skeu-icons)
  "Install the Skeu Icons theme and every accent variant from the Guix channel.
The palettes derive their icon theme from their own accent, so all the variants
have to be present: they are symlink trees that inherit from the base theme and
only resolve while they sit beside it.

The package is part of the jointhefreeworld channel pinned in channels.scm, so
`guix install skeu-icons' puts all thirty themes under
~/.guix-profile/share/icons -- already on the session's XDG_DATA_DIRS -- and
`maak update-guix' brings new artwork in with everything else, at the revision
the repository pins rather than at whatever a clone happens to hold.

A machine that installed the themes the old way still carries them in
~/.local/share/icons, which GTK searches before the profile: that copy, and the
clone it was installed from, are removed here so the profile is the one
answering and cannot fall a release behind."
  (delete-file-recursively (~ "~a/.config/skeu-icons-theme" home)
                           #:verbose? #f)
  (let ((local (~ "~a/.local/share/icons" home)))
    (when (file-exists? local)
      (for-each (lambda (name)
                  (when (and (>= (string-length name) 10)
                             (string-prefix? "skeu-icons" name))
                    (delete-file-recursively (~ "~a/~a" local name)
                                             #:verbose? #f)))
                (scandir local (lambda (name)
                                 (not (member name '("." ".."))))))))
  (run (list (pulled-guix) "install" "skeu-icons")
       #:verbose? #t))

(define (install-whitesur-cursors)
  "Install WhiteSur cursors.
These are the last WhiteSur artwork in use: every palette names their pointer
set as its cursor theme, while the icons come from Skeu Icons."
  (let ((dest (~ "~a/.config/whitesur-cursor-theme" home)))
    (delete-file-recursively dest)
    (git-clone "https://github.com/vinceliuice/WhiteSur-cursors.git"
               #:directory dest)
    (with-directory dest
      (lambda ()
        (run (list "./install.sh"))))))

(define (install-icon-files)
  "Install icon packs."
  (install-skeu-icons)
  (install-whitesur-cursors))

(define (install-wallpaper-files)
  "Install wallpaper files and images."
  (mkdir-p (~ "~a/.local/bin" home))
  (let ((dest (~ "~a/.config/digital-art-dreams" home)))
    (delete-file-recursively dest)
    (git-clone "https://codeberg.org/jjba23/digital-art-dreams.git"
               #:directory dest)))

(define (enable-wallpaper-timer)
  "Install the wallpaper rotation timer and re-apply the wallpaper on record.
Separate from @code{install-wallpapers} so a home reconfigure can render the
wallpaper configuration with the other surfaces and still start the timer: this
half only needs the unit files to exist, so it runs alongside the other
finishing steps."
  (run (list "systemctl" "--user" "daemon-reload"))
  (run (list "systemctl" "--user" "enable" "--now" "heks-wallpaper.timer"))
  ;; Re-apply what is on record, so the engine's first act is not to wait for
  ;; the rotation timer.  It discovers the Wayland socket itself, so this works
  ;; from a task runner that has no session environment.
  (run (list (~ "~a/.local/bin/heks-wallpaper" home) "restore")
       #:allow-failure? #t))

(define (install-wallpapers)
  "Install the wallpaper engine and the rotation timer, then re-apply the
wallpaper that is on record."
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
  (enable-wallpaper-timer))

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

(define (install-home-config)
  "Render every dotfile a home reconfigure writes.

The surfaces are rendered by two Guile processes rather than one per file: the
pinned manifest shell costs more than any of the files it renders, and a
reconfigure used to enter it twenty-one times.  @code{render-configs} splits it
in two because the GTK pass has to land in dconf before the surfaces that reload
themselves are rewritten."
  (render-configs (append theme-surfaces
                          home-surfaces)
                  #:verbose? #t))

(define (home-reconfigure)
  "Complete home reconfigure."
  (setenv "SCRIBA_LOGGER" "color-console")
  ;; Compile first: the renderer reads the bytecode cache this fills, and the two
  ;; would race for it if they ran together.
  (compile)
  (install-home-config)
  ;; Everything below reads what the renderer wrote and nothing else, so the
  ;; wallpaper timer comes up while the bar and the notifications reload.
  (run-tasks-parallel '(reload-surfaces enable-wallpaper-timer))
  (run (list "fyi" "-i" "emblem-success"
             "Succesfully completed home-reconfigure on heks-linux")
       #:allow-failure? #t))

(define (install-theme)
  "Re-render every palette-dependent configuration file.

This is the entry point behind the palette picker: after the palette is written
to ~/.config/heks-linux/local-settings.scm, this task regenerates the dotfiles
that embed colours and reloads the surfaces that keep their own copy in memory.

The GTK files are rendered first and their dconf keys applied straight away, so
the new icon theme is in place before the dock is told its settings changed -
see `render-configs'.  Everything else follows in one Guile process, and the
surfaces are reloaded with signals rather than restarted, so a palette change
lands in about a second and nothing flickers while it does.  Emacs is the one
exception: the Rofi palette picker loads the new theme into the running daemon
itself, because only that script knows which Emacs theme the palette maps to."
  (setenv "SCRIBA_LOGGER" "color-console")
  (render-configs theme-surfaces #:verbose? #t)
  (reload-surfaces)
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
