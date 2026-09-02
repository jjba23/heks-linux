(define dock-auto-hide? #t)

(define dock-show-when-clear? #t)

(define dock-position 'bottom)

(define dock-icon-size 48)

(define dock-theme 'vanilla)

(define dock-monitor 'all)

(define dock-exclude-apps '("warp-taskbar"))

(define dock-enable-repl? #t)

(define dock-hover-animate? #t)

(define dock-track-windows? #t)

(define dock-items
  (append
   (preset-launchers-for
    'alacritty
    'google-chrome
    'spotify-flatpak
    'nautilus
    'nyxt-flatpak
    'gnome-calendar
    'gnome-calculator
    'zapzap-flatpak)
   (list (separator-item))
   (preset-launchers-for 'emacs 'intellij 'bruno-flatpak)
   (list (separator-item))
   (preset-launchers-for 'btop 'pavucontrol 'onepassword)
   (list (separator-item))
   (preset-launchers-for 'ram 'cpu 'cpu-temp 'battery)))

