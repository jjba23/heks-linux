;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The two distribution lists, compared against each other.
;;
;; `packages-spec' asks each backend whether it can answer about its own names.
;; This file asks the harder question: whether the two lists describe the *same
;; desktop*.  They cannot be compared as sets - Void's `mesa-dri' is Debian's
;; `libgl1-mesa-dri', `fd' is `fd-find', `guile' is `guile-3.0' - so the
;; comparison is a table of requirements, each row naming the package that
;; satisfies it on each target.
;;
;; What that buys is the failure this file exists for: a package added to one
;; list and not the other.  A machine installed from the Void list would have a
;; screen recorder and a Debian machine would not, and nothing would say so until
;; somebody pressed the key.  The coverage case is what makes it impossible to
;; add a name silently: every name in either list has to appear in a row, and a
;; row has to say either what the other target calls it or why the other target
;; does not carry it.
;;
;; The table is also where the *gaps* get filled.  Some entries below are here
;; because writing the table made it obvious that neither list had them:
;; `xdg-utils' (every launcher reaches for `xdg-open'), `xdg-user-dirs' (the
;; screenshots setting assumes a Pictures directory exists), and `unzip' and
;; `zip' (a machine that can open a .7z and not a .zip is a machine somebody will
;; curse).  They are in both lists now, and this file keeps them there.

;;; Code:

(define-module (veritas unit packages-parity-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux packages)
  #:use-module (heks-linux packages apt)
  #:use-module (heks-linux packages xbps)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (spec))

;; Rows are (WHAT-IT-IS VOID-NAME DEBIAN-NAME).  A row means both lists must
;; carry their name: the desktop needs the thing on both targets, whatever each
;; distribution calls the package that provides it.
(define shared-requirements
  '(("the message bus and its tools" dbus dbus)
    ("the policy kit" polkit polkitd)
    ("the realtime kit" rtkit rtkit)
    ("the network manager" NetworkManager network-manager)
    ("the sound server" pipewire pipewire)
    ("the sound session manager" wireplumber wireplumber)
    ("the portal broker" xdg-desktop-portal xdg-desktop-portal)
    ("the GTK portal" xdg-desktop-portal-gtk xdg-desktop-portal-gtk)
    ("the GNOME portal" xdg-desktop-portal-gnome xdg-desktop-portal-gnome)
    ("the EGL loader" mesa libegl1)
    ("the Mesa drivers" mesa-dri libgl1-mesa-dri)
    ("the compositor" niri niri)
    ("the floating session" labwc labwc)
    ("the X11 satellite" xwayland-satellite xwayland)
    ("the wallpaper engine" swaybg swaybg)
    ("the idle daemon" swayidle swayidle)
    ("the input event reader" wev wev)
    ("the clipboard" wl-clipboard wl-clipboard)
    ("the backlight" brightnessctl brightnessctl)
    ("the terminal" kitty kitty)
    ("the dialogs" zenity zenity)
    ("the login prompt" greetd greetd)
    ("the prompt's window" tuigreet tuigreet)
    ("the music visualiser" cava cava)
    ("the music server" mpd mpd)
    ("the editor" emacs emacs)
    ("the video tools" ffmpeg ffmpeg)
    ("the screenshot program" grim grim)
    ("the region picker" slurp slurp)
    ("the screen recorder" wf-recorder wf-recorder)
    ("the screenshot annotator" satty satty)
    ("the media player" mpv mpv)
    ("the mixer" pavucontrol pavucontrol)
    ("the media keys" playerctl playerctl)
    ("7z archives" "7zip" "7zip")
    ("a pager for a person" bat bat)
    ("the monitor" btop btop)
    ("the terminal toy" cmatrix cmatrix)
    ("the editor every machine has" ed ed)
    ("the fetch" fastfetch fastfetch)
    ("the file finder" fd fd-find)
    ("the fuzzy finder" fzf fzf)
    ("the GIF optimiser" gifsicle gifsicle)
    ("the console monitor" htop htop)
    ("JSON from the shell" jq jq)
    ("the pager" less less)
    ("Emacs on a console" mg mg)
    ("the search" ripgrep ripgrep)
    ("YAML from the shell" yq yq)
    ("the C toolchain" gcc gcc)
    ("the Rust compiler" rust rustc)
    ("the Rust build tool" cargo cargo)
    ("the Guile interpreter" guile guile-3.0)
    ("the C and C++ front end" llvm clang)
    ("make" make make)
    ("pkg-config" pkg-config pkg-config)
    ("the Ninja build backend" ninja ninja-build)
    ("the version control" git git)
    ("the downloaders" wget wget)
    ("the TLS and signing tools" gnupg gnupg)
    ("the HTTP client" curl curl)
    ("the document converter" pandoc pandoc)
    ("the containers" podman podman)
    ("the application sandbox" flatpak flatpak)
    ("the JVM build tool" gradle gradle)
    ("the store and its daemon" nix nix-bin)
    ("the desktop fonts" dejavu-fonts-ttf fonts-dejavu)
    ("the metric fonts" liberation-fonts-ttf fonts-liberation)
    ("the Noto text families" noto-fonts-ttf fonts-noto-core)
    ("the colour emoji face" noto-fonts-emoji fonts-noto-color-emoji)
    ("the CJK faces" noto-fonts-cjk fonts-noto-cjk)
    ("the launcher's xdg-open" xdg-utils xdg-utils)
    ("the user directories" xdg-user-dirs xdg-user-dirs)
    ;; The six a first boot is judged by: a mixer, the codec profiles and the
    ;; audio DSP firmware behind a laptop's speakers, the two commands that say
    ;; what hardware this is, and Bluetooth.  Both targets call them the same
    ;; thing except the firmware, which Debian signs and names after the project.
    ("the mixer" alsa-utils alsa-utils)
    ("the codec profiles" alsa-ucm-conf alsa-ucm-conf)
    ("the audio DSP firmware" sof-firmware firmware-sof-signed)
    ("what is on the PCI bus" pciutils pciutils)
    ("what is on the USB bus" usbutils usbutils)
    ("Bluetooth" bluez bluez)
    ;; Documentation that is on the machine rather than in a browser: the
    ;; reader is the same program on both, and the pages are what each
    ;; distribution calls its set.
    ("the manual reader" man-db man-db)
    ("the manual pages" man-pages manpages)
    ("zip archives" zip zip)
    ("unzip archives" unzip unzip)))

;; Rows are (WHAT-IT-IS NAME WHY-THE-OTHER-TARGET-DOES-NOT-CARRY-IT).  The name
;; is asserted present on its own target and absent from the other, so the day
;; the other target gains the package this row fails and asks to become a shared
;; one.
(define void-only
  '(("the seat, the session id and loginctl" elogind
     "Debian runs systemd, whose logind provides the same interface")
    ("the administer command" sudo
     "Debian's installer creates its user in the sudo group and installs sudo with it; Void's base-system carries neither, so this image installs both")
    ("Void's syslog for runit" socklog-void
     "Debian's log is the journal, which is part of systemd")
    ("Void's non-free repository" void-repo-nonfree
     "Debian has no repository to enable: contrib and non-free-firmware are named in the medium's configuration")
    ("the MPD client" rmpc
     "no Debian package; build it from its own source, or use another client")
    ("the second wallpaper renderer" wbg
     "no Debian package; the wallpaper engine falls back to swaybg")
    ("Source Serif 4" font-adobe-source-serif-pro
     "no package in Debian 13's main or contrib: install the face from its own release, or let the fontconfig fallbacks answer")))

(define debian-only
  '(("the linker and the LLVM debugger" lld
     "Void's single llvm package carries clang, lld and lldb together")
    ("the LLVM debugger" lldb
     "Void's single llvm package carries clang, lld and lldb together")
    ("the Nix systemd unit and store setup" nix-setup-systemd
     "Void's nix package ships the runit service and the store's directories")
    ("the PulseAudio-compatible server" pipewire-pulse
     "Void's pipewire package ships pipewire-pulse in the same package")))

(define (void-names)
  "Return the names the Void backend installs."
  (map (lambda (package)
         (package-backend-package-name xbps-backend package))
       (package-backend-packages xbps-backend)))

(define (apt-names)
  "Return the names the Debian backend installs."
  (map (lambda (package)
         (package-backend-package-name apt-backend package))
       (package-backend-packages apt-backend)))

(define (as-string name)
  "Return @var{name} as a string.

The table is written with symbols - `dbus', `niri' - because that is how a
package name reads in Scheme, and the backends hand back strings, because that is
how a package name reaches a command line.  This is the one place the two meet."
  (if (symbol? name) (symbol->string name) name))

(define (in? names name)
  "Return @code{#t} when @var{name} is one of @var{names}."
  (if (member (as-string name) names) #t #f))

(define (table-names rows position)
  "Return the names at @var{position} in @var{rows}, as strings."
  (map (lambda (row)
         (as-string (list-ref row position)))
       rows))

(define (shared-cases)
  (suite "Both Targets Carry The Same Desktop"
    (test "Every Requirement Is A Package On Both"
      (let ((void (void-names))
            (apt (apt-names)))
        (assert-equal #:expect '()
          #:got (filter-map (lambda (requirement)
                              (let ((what (car requirement))
                                    (void-name (cadr requirement))
                                    (apt-name (caddr requirement)))
                                (cond
                                  [(not (in? void void-name))
                                   (format #f "~a: ~a is not in the Void list" what void-name)]
                                  [(not (in? apt apt-name))
                                   (format #f "~a: ~a is not in the Debian list" what apt-name)]
                                  [else #f])))
                            shared-requirements)
          #:name "A desktop missing a program on one target is this row")))
    (test "A Program One Target Lacks Is Named, With The Reason"
      ;; The asymmetry rows are how the two lists are allowed to differ, and
      ;; each one is a sentence a person can read rather than a silence.
      (let ((void (void-names))
            (apt (apt-names)))
        (assert-equal #:expect '()
          #:got (filter-map (lambda (row)
                              (let ((name (cadr row)))
                                (cond
                                  [(not (in? void name))
                                   (format #f "~a is not in the Void list" name)]
                                  [(in? apt name)
                                   (format #f "~a is in both lists: make it a shared row" name)]
                                  [else #f])))
                            void-only)
          #:name "Every Void-only package is Void's alone")
        (assert-equal #:expect '()
          #:got (filter-map (lambda (row)
                              (let ((name (cadr row)))
                                (cond
                                  [(not (in? apt name))
                                   (format #f "~a is not in the Debian list" name)]
                                  [(in? void name)
                                   (format #f "~a is in both lists: make it a shared row" name)]
                                  [else #f])))
                            debian-only)
          #:name "And every Debian-only package is Debian's alone")))))

(define (coverage-cases)
  (suite "Nothing Is Installed Without Being Asked For"
    ;; The point of the whole file: a package added to a list and not to the
    ;; table fails here, which is what stops the two desktops drifting.
    (test "Every Void Package Appears In The Table"
      (assert-equal #:expect '()
        #:got (lset-difference string=?
                               (void-names)
                               (append (table-names shared-requirements 1)
                                       (table-names void-only 1)))
        #:name "A name in the xbps list is a name this table knows"))
    (test "Every Debian Package Appears In The Table"
      (assert-equal #:expect '()
        #:got (lset-difference string=?
                               (apt-names)
                               (append (table-names shared-requirements 2)
                                       (table-names debian-only 1)))
        #:name "A name in the apt list is a name this table knows"))
    (test "The Table Names No Package That Is Not Declared"
      ;; The other direction: a row that outlives its package is a claim about a
      ;; list nobody checked.
      (let ((void (void-names))
            (apt (apt-names)))
        (assert-equal #:expect '()
          #:got (remove (lambda (name) (in? void name))
                        (table-names shared-requirements 1))
          #:name "Every shared Void name is installed on Void")
        (assert-equal #:expect '()
          #:got (remove (lambda (name) (in? apt name))
                        (table-names shared-requirements 2))
          #:name "Every shared Debian name is installed on Debian")))))

(define (gap-cases)
  (suite "The Gaps The Table Filled"
    ;; These four are in both lists because writing the table found them missing
    ;; from both, and each one is something a person reaches for on their first
    ;; day: a launcher that cannot open a file, a screenshot directory that does
    ;; not exist, and a .zip that will not open.
    (test "A Machine Can Open A Link, A Zip And Its Own Pictures"
      (let ((void (void-names))
            (apt (apt-names)))
        (for-each (lambda (name)
                    (assert-true (in? void name)
                      #:name (string-append name " is on Void"))
                    (assert-true (in? apt name)
                      #:name (string-append name " is on Debian")))
                  '("xdg-utils" "xdg-user-dirs" "zip" "unzip"))))
    (test "The Music Client Has A Server On Both"
      ;; rmpc without mpd is a window with nothing in it; Debian had the server
      ;; and Void did not until this table was written.
      (assert-true (in? (void-names) "mpd")
        #:name "Void installs the server the client talks to"))
    (test "PulseAudio Clients Have A Server On Both"
      ;; Void's pipewire ships the PulseAudio-compatible server; Debian's splits
      ;; it into a package of its own, and without it an application that speaks
      ;; libpulse is an application with no sound.
      (assert-true (in? (apt-names) "pipewire-pulse")
        #:name "Debian's PulseAudio compatibility is named"))))

(define (spec)
  (veritas-run (shared-cases) (coverage-cases) (gap-cases)))
