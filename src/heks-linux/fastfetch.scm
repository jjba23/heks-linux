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

(define-module (heks-linux fastfetch)
  #:declarative? #t
  #:use-module (json)
  #:use-module (ice-9 string-fun)
  #:use-module (heks-linux prelude)
  #:use-module (heks-linux user-settings)
  #:export (fastfetch-conf install-fastfetch-config
                           heks-linux-fastfetch-ascii-banner))

(define heks-linux-fastfetch-ascii-banner
  (make-parameter "
                                     ......
     .,cdxxxoc,.               .:kKMMMNWMMMNk:.
    cKMMN0OOOKWMMXo.          ;0MWk:'      ':OMMk.
  ;WMK;'       'lKMMNM,     :NMK'             'OMW;
 cMW;             WMMMN   ,XMK'                 oMM.
.MMc             ''^*~l. xMN:                    KM0
'MM.                   .NMO                      oMM
.MM,                 .kMMl                       xMN
 KM0               .kMM0' .dl>~,.               .WMd
 'XM0.           ,OMMK'    OMMM7'              .XMK
   *WMO:.    .;xNMMk'       NNNMKl.          .xWMx
     ^ONMMNXMMMKx;             'xNMWKkxllox0NMWk'
         '''''                    ':dOOXXKOxl'
"))

(define* (fastfetch-conf #:key clone-dir)
  `(($schema . "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json")
    (logo (type . auto)
          (source unquote
                  (string-replace-substring (format #f
                                             "~a/resources/varesa-avatar-small2.png"
                                             (heks-linux-clone-dir)) "~/"
                                            (format #f "~a/" (getenv "HOME"))))
          (padding
          (top . 1)
          (left . 2)
          (right . 2)
          (bottom . 1 ))
          )
    (modules . #(title separator os host kernel uptime packages shell display wm wmtheme theme icons terminal cpu gpu memory disk battery locale break colors))))

(define* (install-fastfetch-config)
  (with-output-to-file (format #f "~a/.config/fastfetch/ascii-banner"
                               (getenv "HOME"))
    (lambda ()
      (display (heks-linux-fastfetch-ascii-banner))))
  (with-output-to-file (format #f "~a/.config/fastfetch/config.jsonc"
                               (getenv "HOME"))
    (lambda ()
      (display (scm->json-string (fastfetch-conf #:clone-dir (heks-linux-clone-dir))
                                 #:pretty #t)))))
