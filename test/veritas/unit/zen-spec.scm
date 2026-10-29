;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; Unit tests for (heks-linux zen).
;;
;; A @file{user.js} is only useful if Firefox can parse it, so the tests check
;; the exact shape of the lines: a @code{user_pref} call with a quoted name, a
;; JavaScript literal and a semicolon.  The rest of the suite is about the
;; promise of the parameters - vertical tabs are always declared, the hardening,
;; compact-mode, devtools and adblock blocks appear only when their parameter is
;; on, and the local override list really is rendered last, because that is what
;; makes a later line win over an earlier one.

;;; Code:

(define-module (veritas unit zen-spec)
  #:use-module (veritas veritas)
  #:use-module (heks-linux zen)
  #:use-module (heks-linux user-settings)
  #:export (spec))

(define (zen-conf-occurs? fragment)
  (not (eq? #f
            (string-contains (zen-user-js) fragment))))

(define (value-serialization-suite)
  (suite "Value Serialization"
         (test "Scalars Render As JavaScript Literals"
               (assert-equal #:expect "true"
                             #:got (serialize-zen-value #t)
                             #:name "Booleans render unquoted")
               (assert-equal #:expect "false"
                             #:got (serialize-zen-value #f)
                             #:name "False renders unquoted")
               (assert-equal #:expect "0"
                             #:got (serialize-zen-value 0)
                             #:name "Zero is a pref value, not an absence")
               (assert-equal #:expect "300"
                             #:got (serialize-zen-value 300)
                             #:name
                             "Integers render without Scheme punctuation"))
         (test "Strings Are Quoted And Escaped"
               (assert-equal #:expect "\"dark\""
                             #:got (serialize-zen-value "dark")
                             #:name "A plain string is double-quoted")
               (assert-equal #:expect "\"a \\\"quoted\\\" path\""
                             #:got (serialize-zen-value "a \"quoted\" path")
                             #:name "A quote inside the value is escaped")
               (assert-equal #:expect "\"C:\\\\tmp\""
                             #:got (serialize-zen-value "C:\\tmp")
                             #:name "A backslash inside the value is escaped"))
         (test "Preference Lines Are user_pref Calls"
               (assert-equal #:expect
                             "user_pref(\"zen.tabs.vertical\", true);"
                             #:got (zen-pref-line "zen.tabs.vertical" #t)
                             #:name
                             "A boolean pref keeps its name and literal")
               (assert-equal #:expect
                "user_pref(\"zen.view.sidebar-expanded.max-width\", 300);"
                #:got (zen-pref-line "zen.view.sidebar-expanded.max-width" 300)
                #:name "A numeric pref has no quotes"))))

(define (generated-file-suite)
  (suite "Generated File"
         (test "The File Is Self-Describing"
               (assert-true (zen-conf-occurs?
                             "// ====== Heks-Linux Zen Browser configuration ======")
                            #:name "The file carries a generated-file header")
               (assert-true (zen-conf-occurs? "DO NOT EDIT!")
                            #:name "The header says not to edit the file")
               (assert-true (zen-conf-occurs? "src/heks-linux/zen.scm")
                            #:name "The header names the source of truth"))
         (test "Vertical Tabs Are Declared"
               (assert-true (zen-conf-occurs?
                             "user_pref(\"zen.tabs.vertical\", true);")
                            #:name "The tab bar is vertical")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"zen.tabs.vertical.right-side\", false);")
                            #:name "The tab bar stays on the left")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"zen.view.sidebar-expanded\", true);")
                            #:name "The sidebar starts expanded")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"zen.view.sidebar-expanded.max-width\", 300);")
                            #:name "The sidebar has a laptop-friendly width"))
         (test "The Browser Toolbox Is Enabled With A Prompt"
               (assert-true (zen-conf-occurs?
                             "user_pref(\"devtools.chrome.enabled\", true);")
                            #:name "Chrome debugging is available")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"devtools.debugger.remote-enabled\", true);")
                            #:name "Remote debugging is available")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"devtools.debugger.prompt-connection\", true);")
                            #:name "Connecting still asks for confirmation")
               (assert-equal #:expect #f
                             #:got (zen-conf-occurs?
                                    "user_pref(\"view_source.editor.external\", true);")
                             #:name "The external editor is off by default"))
         (test "The DevTools Theme Follows The Palette"
               (assert-true (zen-conf-occurs?
                             "user_pref(\"devtools.theme\", \"dark\");")
                            #:name "A dark palette asks for the dark theme")
               (parameterize ((heks-linux-palette 'modus-operandi))
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"devtools.theme\", \"light\");")
                              #:name
                              "A light palette asks for the light theme")))
         (test "uBlock Origin Is Allowed To Start Enabled"
               (assert-true (zen-conf-occurs?
                             "user_pref(\"extensions.autoDisableScopes\", 0);")
                            #:name "Side-loaded extensions are not disabled")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"extensions.enabledScopes\", 15);")
                            #:name "The profile scope is enabled"))))

(define (parameter-suite)
  (suite "Parameters"
         (test "Tracking Protection Is On By Default"
               (assert-true (zen-conf-occurs?
                             "user_pref(\"browser.contentblocking.category\", \"custom\");")
                #:name
                "The custom ETP category keeps the individual prefs in charge")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"privacy.trackingprotection.enabled\", true);")
                            #:name "Tracking protection is on")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"privacy.trackingprotection.cryptomining.enabled\", true);")
                            #:name "Cryptominer blocking is on")
               (assert-true (zen-conf-occurs?
                             "user_pref(\"network.prefetch-next\", false);")
                            #:name "Link prefetching is off"))
         (test "The Site-Breaking Prefs Are Opt-In"
               (assert-true (zen-conf-occurs?
                             "user_pref(\"privacy.fingerprintingProtection\", false);")
                            #:name
                            "Fingerprinting protection is off, and says so")
               (parameterize ((zen-fingerprinting-protection? #t))
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"privacy.fingerprintingProtection\", true);")
                              #:name "It is rendered when asked for")
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"privacy.trackingprotection.fingerprinting.enabled\", true);")
                              #:name
                              "The fingerprinting blocker travels with it"))
               (assert-true (zen-conf-occurs?
                             "user_pref(\"dom.security.https_only_mode\", false);")
                            #:name "HTTPS-Only mode is off, and says so")
               (parameterize ((zen-https-only? #t))
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"dom.security.https_only_mode\", true);")
                              #:name "It is rendered when asked for"))
               (assert-true (zen-conf-occurs?
                             "user_pref(\"network.http.referer.XOriginTrimmingPolicy\", 0);")
                #:name "A trimmed profile is put back to Firefox's own policy"))
         (test "Hardening Can Be Turned Off"
               (parameterize ((zen-hardening? #f))
                 (assert-equal #:expect #f
                               #:got (zen-conf-occurs?
                                      "user_pref(\"privacy.trackingprotection.enabled\", true);")
                               #:name "Turning hardening off drops the block")
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"zen.tabs.vertical\", true);")
                              #:name "The layout is still declared")))
         (test "Compact Mode Is Opt-In"
               (assert-equal #:expect #f
                             #:got (zen-conf-occurs?
                                    "user_pref(\"zen.view.compact.enable-at-startup\", true);")
                             #:name "Compact mode is off by default")
               (parameterize ((zen-compact-mode? #t))
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"zen.view.compact.enable-at-startup\", true);")
                              #:name
                              "Turning it on adds the master preference")
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"zen.view.compact.hide-toolbar\", false);")
                              #:name "The address bar stays visible")))
         (test "DevTools Can Be Turned Off"
               (parameterize ((zen-devtools? #f))
                 (assert-equal #:expect #f
                               #:got (zen-conf-occurs?
                                      "user_pref(\"devtools.chrome.enabled\", true);")
                               #:name "The Toolbox prefs disappear together"))
               (parameterize ((zen-external-editor "/usr/bin/other-editor"))
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"view_source.editor.external\", true);")
                  #:name "The external editor is enabled by its parameter")
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"view_source.editor.path\", \"/usr/bin/other-editor\");")
                              #:name "The editor path follows its parameter")
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"view_source.editor.args\", \"+%LINE%\");")
                              #:name "The editor receives the line number"))
               (assert-equal #:expect #f
                             #:got (zen-conf-occurs?
                                    "user_pref(\"view_source.editor.path\", \"/usr/bin/other-editor\");")
                             #:name
                             "The editor prefs disappear once it is unset"))
         (test "Adblock Prefs Can Be Turned Off"
               (parameterize ((zen-adblock? #f))
                 (assert-equal #:expect #f
                               #:got (zen-conf-occurs?
                                      "user_pref(\"extensions.autoDisableScopes\", 0);")
                               #:name "The sideload scopes disappear")))
         (test "Local Overrides Are Rendered Last"
               (parameterize ((zen-extra-prefs (list (cons "zen.tabs.vertical"
                                                      #f))))
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"zen.tabs.vertical\", false);")
                              #:name "The override line is present")
                 (assert-true (zen-conf-occurs?
                               "user_pref(\"zen.tabs.vertical\", true);")
                  #:name
                  "The generated line stays, so the override wins on load")))))

(define (spec)
  (veritas-run (value-serialization-suite)
               (generated-file-suite)
               (parameter-suite)))
