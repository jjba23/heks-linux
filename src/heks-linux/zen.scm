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
;; Renders @file{user.js} into every Zen Browser profile it can find.
;;
;; Zen is a Firefox fork, so its configuration is the Firefox one: a
;; @file{user.js} in the profile is read on every start and overrides whatever
;; the previous session stored in @file{prefs.js}.  That is exactly what makes a
;; declarative browser configuration possible - and exactly why a setting changed
;; in Zen's own settings page comes back after a restart.
;;
;; The profiles are not at a fixed path.  A native install keeps them under
;; @file{~/.zen}, the Flatpak build under
;; @file{~/.var/app/app.zen_browser.zen/.zen} (with some versions using
;; @file{.../zen}), and every profile has a random prefix such as
;; @code{abc123.Default (release)}.  Rather than guess, @code{zen-profile-dirs}
;; scans those roots for directories that contain a @file{prefs.js}, which is
;; the file Firefox itself creates when it starts a profile for the first time.
;; A machine that has never launched Zen therefore has nothing to configure, and
;; the installer says so instead of inventing a profile Zen would ignore.
;;
;; This module only states the deltas.  Zen ships a @file{prefs/privatefox}
;; set that already locks telemetry, studies and crash upload off, disables its
;; AI features, and turns off sponsored suggestions; those are not repeated
;; here.  What is added is the layout Heks wants (vertical tabs), the prefs Zen
;; leaves open (tracking protection, no prefetching or speculative connections),
;; the Browser Toolbox (with an opt-in external source editor), and the two
;; prefs that let a side-loaded extension start enabled.
;;
;; The two prefs that are known to break real sites - Firefox's fingerprinting
;; protection and HTTPS-Only mode - are available but off: this is a daily
;; driver, and a blank page or an unreachable site is worse than a fingerprint.
;;
;; uBlock Origin is installed by dropping the signed AMO build into
;; @file{<profile>/extensions/uBlock0@@raymondhill.net.xpi}.  Firefox treats an
;; XPI in the profile as a side-loaded add-on; @code{extensions.autoDisableScopes}
;; is set to @code{0} so it is enabled on the next start instead of arriving
;; disabled behind a prompt.  A @file{policies.json} would be the other way to
;; install it, but the Flatpak ships its own read-only policy file next to the
;; binary, so the profile is the one place both installs share.
;;
;; The Browser Toolbox prefs (@code{devtools.chrome.enabled} and
;; @code{devtools.debugger.remote-enabled}) are powerful and slightly risky:
;; the connection prompt is deliberately left on, and the devtools theme follows
;; the active palette.  The external source editor is opt-in: Firefox would
;; launch the path from inside its own process, and the Flatpak sandbox has its
;; own @file{/usr} and no permission to start host programs, so a host
;; @command{emacsclient} only works for a native install.
;;
;; Because this is a @file{user.js}, local changes belong in
;; @file{$XDG_CONFIG_HOME/heks-linux/zen-settings.scm}; @code{zen-extra-prefs}
;; is appended last and wins over every generated preference.

;;; Code:

(define-module (heks-linux zen)
  #:declarative? #t
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (heks-linux palette)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:use-module (scriba scriba)
  #:use-module (scriba auto)
  #:export (zen-profile-roots zen-user-js-filename
                              zen-adblock-extension-id
                              zen-adblock-install-url
                              zen-external-editor
                              zen-compact-mode?
                              zen-hardening?
                              zen-fingerprinting-protection?
                              zen-https-only?
                              zen-devtools?
                              zen-adblock?
                              zen-extra-prefs
                              serialize-zen-value
                              zen-pref-line
                              heks-linux-zen-settings
                              zen-user-js
                              zen-profile-dirs
                              install-zen-config))

(define s
  (scriba-auto-logger))

;; --- Parameters ---

;; Directories that may hold Zen profiles.  A native tarball install uses
;; @file{~/.zen}; the Flatpak build has used both @file{.zen} and @file{zen} for
;; its persisted profile directory, so both are searched.  Entries that do not
;; exist are skipped.
(define zen-profile-roots
  (make-parameter (let ((home (or (getenv "HOME") "/tmp")))
                    (list (format #f "~a/.zen" home)
                          (format #f "~a/.var/app/app.zen_browser.zen/.zen"
                                  home)
                          (format #f "~a/.var/app/app.zen_browser.zen/zen"
                                  home)))))

;; The preference file Firefox reads from the profile at every start.
(define zen-user-js-filename
  (make-parameter "user.js"))

;; uBlock Origin's add-on id.  A side-loaded XPI has to be named after it.
(define zen-adblock-extension-id
  (make-parameter "uBlock0@raymondhill.net"))

;; The signed AMO build of uBlock Origin.  AMO's "latest" redirect always points
;; at the current release, so the XPI is fetched again only when it is missing.
(define zen-adblock-install-url
  (make-parameter
   "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"))

;;; The editor Firefox opens when you choose "View Source" from the page context
;; menu, or @code{#f} to keep Firefox's built-in source viewer.  Firefox needs an
;; absolute path to a program it can execute itself; a native Zen can reach the
;; host's @command{emacsclient}, while the Flatpak build only sees the runtime's
;; @file{/usr}, so the two prefs are emitted only when this is set.
(define zen-external-editor
  (make-parameter #f))

;; Whether to turn on Zen's compact mode at startup: the sidebar and the tab bar
;; hide, and hover over the window edge brings them back.  Off by default,
;; because it changes the shape of every window and is a matter of taste.
(define zen-compact-mode?
  (make-parameter #f))

;; Whether to add the balanced privacy prefs: tracking protection, no
;; speculative connections and prefetching, WebRTC address limiting, temporary
;; download directory and no leftover telemetry.  Zen's own defaults stop at
;; tracking protection, so this is a real change; set it to @code{#f} for a
;; stock-Zen privacy posture.
(define zen-hardening?
  (make-parameter #t))

;; Whether to turn on Firefox's fingerprinting protection, which randomises
;; canvas, fonts and other surfaces.  It is the strongest anti-fingerprinting
;; switch there is - and the one that breaks the most sites: logins, captcha
;; walls and embedded checkouts start failing.  Off by default on a daily
;; driver; @code{(zen-fingerprinting-protection? #t)} turns it on.
(define zen-fingerprinting-protection?
  (make-parameter #f))

;; Whether to upgrade every plain-HTTP navigation to HTTPS and refuse the site
;; when that fails.  It defeats sslstrip, but a page that only exists over HTTP,
;; or one with a broken certificate, becomes unreachable with no way through,
;; and the error page looks like the network is down.  Off by default.
(define zen-https-only?
  (make-parameter #f))

;; Whether to enable the Browser Toolbox and the Emacs source editor.  The
;; connection prompt stays on: the Toolbox can inspect and modify the browser
;; itself, so it should not be reachable without confirmation.
(define zen-devtools?
  (make-parameter #t))

;; Whether to install uBlock Origin into each profile.  Turning this off leaves
;; an already downloaded XPI alone; it only stops the installer from fetching a
;; missing one.
(define zen-adblock?
  (make-parameter #t))

;; Extra @code{(name . value)} prefs appended after every generated block, so a
;; later line wins over an earlier one.  Use this in the local override file to
;; change a single pref without replacing a whole category:
;;
;; @example
;; (zen-extra-prefs
;;  (list (cons "zen.view.sidebar-expanded.max-width" 240)
;;        (cons "privacy.trackingprotection.socialtracking.enabled" #f)))
;; @end example
(define zen-extra-prefs
  (make-parameter '()))

;; --- Values ---

(define (escape-zen-string value)
  "Return @var{value} with the characters a JavaScript string literal cannot
carry backslashed.

@example
(escape-zen-string \"a \\\"quoted\\\" path\")
@result{} a \\\"quoted\\\" path
@end example"
  (with-output-to-string (lambda ()
                           (string-for-each (lambda (c)
                                              (cond
                                                ((char=? c #\\)
                                                 (display "\\\\"))
                                                ((char=? c #\")
                                                 (display "\\\""))
                                                ((char=? c #\newline)
                                                 (display "\\n"))
                                                (else (display c)))) value))))

(define (serialize-zen-value value)
  "Return @var{value} as the JavaScript literal a @code{user_pref} call takes.

Booleans become @code{true} and @code{false}, numbers lose their Scheme
punctuation and strings are quoted.  Zen prefs are scalars only, so anything
else is a programming error rather than something to render.

@example
(serialize-zen-value #t)
@result{} true
@end example"
  (cond
    ((eq? value #t)
     "true")
    ((eq? value #f)
     "false")
    ((number? value)
     (number->string value))
    ((string? value)
     (format #f "\"~a\""
             (escape-zen-string value)))
    (else (error "serialize-zen-value: cannot render as a Zen pref:" value))))

(define (zen-pref-line name value)
  "Render one preference as a @code{user_pref} line, without its newline.

@example
(zen-pref-line \"zen.tabs.vertical\" #t)
@result{} user_pref(\"zen.tabs.vertical\", true);
@end example"
  (format #f "user_pref(\"~a\", ~a);" name
          (serialize-zen-value value)))

;; --- The preferences ---

(define (zen-vertical-tab-prefs)
  "Return the preferences that make the tab bar vertical and keep it expanded.

Zen is vertical by default, but stating it here means the layout survives a
profile whose @file{prefs.js} was changed in the UI.  The 300 pixel maximum is
narrower than Zen's 500 so more of the page stays visible on a laptop, and the
new-tab button stays inside the tab strip."
  '(("zen.tabs.vertical" . #t) ("zen.tabs.vertical.right-side" . #f)
    ("zen.view.sidebar-expanded" . #t)
    ("zen.view.sidebar-expanded.max-width" . 300)
    ("zen.tabs.show-newtab-vertical" . #t)
    ("zen.tabs.rename-tabs" . #t)
    ("zen.tabs.select-recently-used-on-close" . #t)))

(define (zen-compact-mode-prefs)
  "Return the preferences that start Zen in compact mode.

The toolbar is kept visible - it carries the address bar - while the tab bar
hides with the sidebar and both return on hover.  The master switch is Zen's
hidden @code{zen.view.compact.enable-at-startup}."
  '(("zen.view.compact.enable-at-startup" . #t)
    ("zen.view.compact.hide-toolbar" . #f)
    ("zen.view.compact.hide-tabbar" . #t)
    ("zen.view.compact.show-sidebar-and-toolbar-on-hover" . #t)))

(define (zen-hardening-prefs)
  "Return the privacy preferences that a daily browser can carry.

Tracking protection runs in normal and private windows and covers social,
cryptomining and email trackers; known tracking parameters are stripped from
links and Global Privacy Control is advertised.  Speculative DNS lookups, link
prefetching and the address bar's preconnects are off, WebRTC keeps working but
exposes only the default interface, downloads land in a temporary directory,
page scripts cannot move or resize the window, and the studies, rollout and
crash-report switches Zen does not already lock are off.

What is deliberately off is the part that breaks sites: Firefox fingerprinting
protection (@code{zen-fingerprinting-protection?}), HTTPS-Only mode
(@code{zen-https-only?}) and referrer trimming, which is put back to Firefox's
own cross-origin policy so a profile that was trimmed returning is relaxed.
DoH, Safe Browsing, DRM and WebRTC itself are left alone so captive portals,
streaming and calls keep working.

The content-blocking category is set to @code{custom} on purpose.  Firefox
re-applies the @code{standard} preset to the individual protection prefs at
startup, which would silently undo them; @code{custom} leaves the prefs below in
charge and still shows a working panel in the settings page."
  '(("browser.contentblocking.category" . "custom")
    ("privacy.trackingprotection.enabled" . #t)
    ("privacy.trackingprotection.pbmode.enabled" . #t)
    ("privacy.trackingprotection.socialtracking.enabled" . #t)
    ("privacy.trackingprotection.cryptomining.enabled" . #t)
    ("privacy.trackingprotection.emailtracking.enabled" . #t)
    ("privacy.query_stripping.enabled" . #t)
    ("privacy.query_stripping.enabled.pbmode" . #t)
    ("privacy.globalprivacycontrol.enabled" . #t)
    ("network.dns.disablePrefetch" . #t)
    ("network.dns.disablePrefetchFromHTTPS" . #t)
    ("network.prefetch-next" . #f)
    ("network.http.speculative-parallel-limit" . 0)
    ("browser.urlbar.speculativeConnect.enabled" . #f)
    ("browser.places.speculativeConnect.enabled" . #f)
    ("network.http.referer.XOriginTrimmingPolicy" . 0)
    ("media.peerconnection.ice.default_address_only" . #t)
    ("media.peerconnection.ice.proxy_only_if_behind_proxy" . #t)
    ("browser.download.start_downloads_in_tmp_dir" . #t)
    ("browser.helperApps.deleteTempFileOnExit" . #t)
    ("browser.download.manager.addToRecentDocs" . #f)
    ("dom.disable_window_move_resize" . #t)
    ("app.normandy.enabled" . #f)
    ("app.shield.optoutstudies.enabled" . #f)
    ("nimbus.rollouts.enabled" . #f)
    ("browser.tabs.crashReporting.sendReport" . #f)
    ("browser.crashReports.unsubmittedCheck.enabled" . #f)))

(define (zen-fingerprinting-protection-prefs enabled?)
  "Return the fingerprinting protection preferences for @var{enabled?}.

@code{privacy.fingerprintingProtection} randomises the surfaces a script can
read - canvas, fonts, screen metrics - in normal and private windows, and the
ETP fingerprinting category blocks the scripts that try.  This is the block that
makes some logins and captcha walls fail, so it is opt-in.

The value is written either way on purpose: a ~prefs.js~ keeps the last user
value, so removing these lines would leave a previously hardened profile
protected - and broken - instead of returning it to the default."
  `(("privacy.fingerprintingProtection" unquote enabled?)
    ("privacy.fingerprintingProtection.pbmode" unquote enabled?)
    ("privacy.trackingprotection.fingerprinting.enabled" unquote enabled?)))

(define (zen-https-only-prefs enabled?)
  "Return the HTTPS-Only mode preference for @var{enabled?}.

Every plain-HTTP navigation is upgraded to HTTPS, and a site that cannot serve
HTTPS is refused instead of loaded in the clear.  Opt-in, because an HTTP-only
page or a broken certificate then becomes unreachable with no way through.
Written as @code{false} when off for the same reason as the fingerprinting
block: the profile remembers the last user value."
  `(("dom.security.https_only_mode" unquote enabled?)))

(define (zen-devtools-prefs)
  "Return the Browser Toolbox and external-editor preferences.

@code{devtools.chrome.enabled} and @code{devtools.debugger.remote-enabled} are
what Zen needs before the Browser Toolbox can be opened; the confirmation
prompt is kept so a debugging port cannot be opened silently.  The DevTools
theme follows the palette, the console timestamps its messages, and the network
log survives reloads.

When @code{zen-external-editor} names an executable, view-source is handed to
it with @code{%LINE%} replaced by the source line, which is how an
@command{emacsclient} lands on the right line.  The three prefs are left out
otherwise, because a Flatpak build cannot execute a host editor."
  (append `(("devtools.chrome.enabled" . #t)
            ("devtools.debugger.remote-enabled" . #t)
            ("devtools.debugger.prompt-connection" . #t)
            ("devtools.theme" unquote
             (if (is-dark-palette (heks-linux-palette)) "dark" "light"))
            ("devtools.toolbox.host" . "window")
            ("devtools.webconsole.timestampMessages" . #t)
            ("devtools.netmonitor.persistlog" . #t))
          (if (zen-external-editor)
              `(("view_source.editor.external" . #t) ("view_source.editor.path"
                                                      unquote
                                                      (zen-external-editor))
                ("view_source.editor.args" . "+%LINE%"))
              '())))

(define (zen-adblock-prefs)
  "Return the preferences that let a side-loaded extension start enabled.

An XPI dropped into the profile is a side-loaded add-on; by default Firefox
installs it disabled.  A zero @code{extensions.autoDisableScopes} trusts every
sideloading scope, and @code{extensions.enabledScopes} @code{15} keeps the
profile scope switched on."
  '(("extensions.autoDisableScopes" . 0) ("extensions.enabledScopes" . 15)))

(define (heks-linux-zen-settings)
  "Return the full Zen configuration as a list of @code{(name . value)} pairs.

The layout is always present; the compact-mode, hardening, fingerprinting,
HTTPS-Only, devtools and adblock blocks are added according to their
parameters, and @code{zen-extra-prefs} comes last so a local override wins.

@example
(assoc-ref (heks-linux-zen-settings) \"zen.tabs.vertical\")
@result{} #t
@end example"
  (append (zen-vertical-tab-prefs)
          (if (zen-compact-mode?)
              (zen-compact-mode-prefs)
              '())
          (if (zen-hardening?)
              (zen-hardening-prefs)
              '())
          (zen-fingerprinting-protection-prefs (zen-fingerprinting-protection?))
          (zen-https-only-prefs (zen-https-only?))
          (if (zen-devtools?)
              (zen-devtools-prefs)
              '())
          (if (zen-adblock?)
              (zen-adblock-prefs)
              '())
          (zen-extra-prefs)))

(define (zen-user-js)
  "Return the @file{user.js} file for Zen as a string.

The file starts with a generated-file header, then one @code{user_pref} call per
setting, in the order of @code{heks-linux-zen-settings}."
  (mk-lines (append '("// ====== Heks-Linux Zen Browser configuration ======"
                      "//" "// auto-generated file, DO NOT EDIT!"
                      "// Source of truth: src/heks-linux/zen.scm"
                      "// Rendered by: maak install-zen" "")
                    (map (lambda (pref)
                           (zen-pref-line (car pref)
                                          (cdr pref)))
                         (heks-linux-zen-settings)))))

;; --- Installation ---

(define (zen-profile-dirs)
  "Return every existing Zen profile directory.

Each root in @code{zen-profile-roots} is scanned for directories that contain a
@file{prefs.js}; that file is the marker Firefox itself writes when a profile
has been started, so directories such as @file{storage} or
@file{Crash Reports} are skipped without needing a name convention."
  (append-map (lambda (root)
                (if (file-exists? root)
                    (filter (lambda (dir)
                              (file-exists? (format #f "~a/prefs.js" dir)))
                            (map (lambda (name)
                                   (format #f "~a/~a" root name))
                                 (scandir root
                                          (lambda (name)
                                            (not (member name
                                                         '("." "..")))))))
                    '()))
              (zen-profile-roots)))

(define (install-zen-adblock! profile-dir)
  "Fetch uBlock Origin into @var{profile-dir} when it is not there yet.

The XPI is named after the add-on id, which is how Firefox recognises a
side-loaded extension.  @code{curl --fail} means an error page is never saved as
an extension: a failed download is removed and logged instead."
  (let* ((extension-dir (format #f "~a/extensions" profile-dir))
         (destination (format #f "~a/~a.xpi" extension-dir
                              (zen-adblock-extension-id))))
    (unless (file-exists? destination)
      (ensure-directory-tree! extension-dir)
      (log-info s "Downloading uBlock Origin into ~a" extension-dir)
      (let ((status (system* "curl"
                             "--fail"
                             "--silent"
                             "--show-error"
                             "--location"
                             "--output"
                             destination
                             (zen-adblock-install-url))))
        (cond
          ((zero? status)
           (log-success s "Installed uBlock Origin for Zen Browser"))
          (else (log-warning s
                 "Could not download uBlock Origin (curl exited ~a)" status)
                (when (file-exists? destination)
                  (delete-file destination))))))))

(define (install-zen-config)
  "Install the Zen Browser configuration into every profile that exists.

Local overrides are read from
@file{$XDG_CONFIG_HOME/heks-linux/zen-settings.scm} first.  Each profile gets a
fresh @file{user.js}; when @code{zen-adblock?} is set, a missing uBlock Origin
XPI is downloaded as well.  A machine where Zen has never started has no profile
to write to, so the task logs that instead of creating one Zen would ignore."
  (log-info s "Installing Zen Browser configuration")
  (load-local-overrides '(heks-linux zen)
                        'zen-settings)
  (let ((profiles (zen-profile-dirs)))
    (if (null? profiles)
        (log-info s
         "No Zen Browser profile found; start Zen once (flatpak run app.zen_browser.zen) and run maak install-zen again")
        (for-each (lambda (dir)
                    (install-config-file! #:name (zen-user-js-filename)
                                          #:dir dir
                                          #:contents (zen-user-js))
                    (when (zen-adblock?)
                      (install-zen-adblock! dir))) profiles))
    (unless (null? profiles)
      (log-success s "Installed Zen Browser configuration"))))
