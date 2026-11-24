;; heks-linux
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Commentary:
;;
;; The screen a machine shows before it can show anything else: plymouth's
;; splash, and the box that opens an encrypted disk.
;;
;; Three things make this worth a module rather than a theme copied from the
;; distribution underneath.  The theme is *text*, drawn by plymouth's script
;; plugin from strings, so there is no artwork in this tree to keep in step with
;; the palette and nothing of Void's can appear on a Heks boot screen.  The
;; password box asks its own question: dracut hands it `Password (/dev/sda3)'
;; and no setting changes that, so a theme that draws the string it is given is
;; a box with a device path in it - this one ignores the argument and says what
;; to type.  And the splash has to be taken away again: plymouthd starts in the
;; initramfs and nothing on runit quits it, which is a login prompt drawn
;; underneath a logo.  @code{plymouth-quit-service} is that half.
;;
;; What this tree decides about it: the daemon stays off by default.  A splash
;; that cannot draw is a black screen with a question on it - on a virtual
;; machine, and on any graphics plymouth has no driver for - and a person who
;; cannot see the passphrase box types a passphrase into nothing.  The console
;; asks the same question and always arrives, so @code{plymouth.enable=0} is
;; what the installer writes into the kernel command line, and @code{splash} on
;; the command line is how a machine asks for the theme instead.  Everything
;; below is what that machine then gets: on a machine whose graphics plymouth
;; cannot draw on it still falls back to the console's own question.
;;
;;; Code:

(define-module (heks-linux boot)
  #:declarative? #t
  #:use-module (ice-9 format)
  #:use-module (heks-linux identity)
  #:export (plymouth-theme-name
            plymouth-theme
            plymouth-script
            plymouth-config
            plymouth-quit-service
            plymouth-kernel-argument
            plymouth-packages))

;; The directory @file{/usr/share/plymouth/themes} spells the theme's name with:
;; one word, because it is a directory name, a plugin lookup and a value in
;; @file{/etc/plymouth/plymouthd.conf} at once.
(define plymouth-theme-name
  "heks")

;; Plymouth picks the theme from the command line, its configuration or this
;; file, and a theme that cannot draw is not a boot that stops: the daemon does
;; not start and dracut asks on the console.
(define (plymouth-theme)
  "Return the theme's @file{.plymouth} file, as text.

It names the script plugin and the two files the plugin reads, which is the
whole of what plymouth needs to know about a theme that ships no artwork."
  (format #f "[Plymouth Theme]
Name=Heks
Description=Heks GNU/Linux on a dark screen, and the box that opens the disk.
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/~a
ScriptFile=/usr/share/plymouth/themes/~a/~a.script
"
          plymouth-theme-name plymouth-theme-name plymouth-theme-name))

(define (plymouth-script)
  "Return the theme's script, in plymouth's own language.

Every image is drawn from a string with @code{Image.Text}: the name, a rule, the
line that changes between starting up and asking for the passphrase, the
asterisks that count the keystrokes, and the messages dracut sends.  The
callback signatures are the ones plymouth calls, and the plugin ignores a
function it is not given.

The palette is the one the wizards and the login prompt use - green ink on a
dark screen, bright where the eye should land - written as the fractions
plymouth takes rather than the hex this tree writes everywhere else."
  (format #f "# ~a: the splash, and the box that opens an encrypted disk.
#
# plymouth's script plugin.  Every image here is drawn from a string, so the
# theme is these two files and nothing else - no artwork, and nothing of the
# distribution this system is built on.

Window.SetBackgroundTopColor(0.02, 0.03, 0.02);
Window.SetBackgroundBottomColor(0.00, 0.00, 0.00);

# green ink, bright where the eye should land
ink_red = 0.28;
ink_green = 0.50;
ink_blue = 0.38;
bright_red = 0.55;
bright_green = 0.85;
bright_blue = 0.65;
dim_red = 0.18;
dim_green = 0.30;
dim_blue = 0.22;

# --- the name (the one thing that never changes) ------------------------------
title_image = Image.Text(\"~a\", bright_red, bright_green, bright_blue);
title_image = title_image.Scale(title_image.GetWidth() * 2, title_image.GetHeight() * 2);
title_sprite = Sprite(title_image);

rule_image = Image.Text(\"----------------------------\", ink_red, ink_green, ink_blue);
rule_sprite = Sprite(rule_image);

status_sprite = Sprite();
status_y = 0;

hint_image = Image.Text(\"A wrong passphrase asks again.\", dim_red, dim_green, dim_blue);
hint_sprite = Sprite(hint_image);
hint_sprite.SetOpacity(0);

message_sprite = Sprite();
message_sprite.SetOpacity(0);

# The asterisks that count a passphrase: a fixed row, shown as far as it has
# been typed.  32 is longer than the passphrases this system asks for and keeps
# the layout still.
bullet_image = Image.Text(\"*\", bright_red, bright_green, bright_blue);
bullet_count = 32;
bullet_spacing = bullet_image.GetWidth() + 4;

fun place_sprites ()
  {
    global.title_sprite.SetPosition(Window.GetX() + Window.GetWidth() / 2 - global.title_image.GetWidth() / 2,
                                    Window.GetY() + Window.GetHeight() * 0.36,
                                    10);
    global.rule_sprite.SetPosition(Window.GetX() + Window.GetWidth() / 2 - global.rule_image.GetWidth() / 2,
                                   Window.GetY() + Window.GetHeight() * 0.36 + global.title_image.GetHeight() + 10,
                                   10);
    global.status_y = Window.GetY() + Window.GetHeight() * 0.52;
    global.hint_sprite.SetPosition(Window.GetX() + Window.GetWidth() / 2 - global.hint_image.GetWidth() / 2,
                                   Window.GetY() + Window.GetHeight() * 0.62,
                                   20);
    global.message_sprite.SetPosition(Window.GetX() + 12, Window.GetY() + Window.GetHeight() - 24, 30);
  }

fun set_status (text)
  {
    global.status_image = Image.Text(text, ink_red, ink_green, ink_blue);
    global.status_sprite.SetImage(global.status_image);
    global.status_sprite.SetPosition(Window.GetX() + Window.GetWidth() / 2 - global.status_image.GetWidth() / 2,
                                     global.status_y,
                                     20);
  }

fun hide_bullets ()
  {
    for (index = 0; index < bullet_count; index++)
      {
        if (global.bullet[index])
          {
            global.bullet[index].sprite.SetOpacity(0);
          }
      }
  }

fun show_bullets (typed)
  {
    global.bullet_left = Window.GetX() + Window.GetWidth() / 2 - (bullet_count * bullet_spacing) / 2;
    global.bullet_y = Window.GetY() + Window.GetHeight() * 0.57;
    for (index = 0; index < bullet_count; index++)
      {
        if (!global.bullet[index])
          {
            global.bullet[index].sprite = Sprite(bullet_image);
            global.bullet[index].sprite.SetPosition(global.bullet_left + index * bullet_spacing,
                                                    global.bullet_y,
                                                    20);
          }
        if (index < typed)
          {
            global.bullet[index].sprite.SetOpacity(1);
          }
        else
          {
            global.bullet[index].sprite.SetOpacity(0);
          }
      }
  }

# --- what plymouth calls ------------------------------------------------------
fun on_startup ()
  {
    place_sprites();
    set_status(\"starting up\");
  }

# A session is about to draw, or the question was answered: the box goes away.
fun display_normal_callback ()
  {
    set_status(\"starting up\");
    hide_bullets();
    global.hint_sprite.SetOpacity(0);
  }

# The disk is locked.  `prompt' is dracut's own line - Password (/dev/sda3) and
# nothing changes it - so it is not drawn: the question is asked in words.
fun display_password_callback (prompt, typed)
  {
    set_status(\"Enter your disk passphrase, then press Enter.\");
    global.hint_sprite.SetOpacity(1);
    show_bullets(typed);
  }

fun display_message_callback (text)
  {
    global.message_sprite.SetImage(Image.Text(text, dim_red, dim_green, dim_blue));
    global.message_sprite.SetPosition(Window.GetX() + 12, Window.GetY() + Window.GetHeight() - 24, 30);
    global.message_sprite.SetOpacity(1);
  }

fun hide_message_callback (text)
  {
    global.message_sprite.SetOpacity(0);
  }

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);
Plymouth.SetDisplayMessageFunction(display_message_callback);
Plymouth.SetHideMessageFunction(hide_message_callback);

on_startup();
"
          heks-name heks-name))

(define (plymouth-config)
  "Return @file{/etc/plymouth/plymouthd.conf}, as text.

@code{Theme} is the whole of it: plymouthd's own default is the distribution's
@code{fade-in}, and this is the file that says otherwise.
@code{ShowDelay} is the seconds plymouth waits before drawing anything, and the
default of five is longer than this system takes to ask for a passphrase - the
box would come up on a black screen and the splash would arrive after it."
  "[Daemon]
Theme=heks
ShowDelay=0
")

(define (plymouth-quit-service)
  "Return @file{/etc/sv/plymouth-quit/run}, the service that ends the splash.

plymouthd is started by the initramfs, before the root filesystem exists, and it
holds the console until something tells it to stop.  A machine with systemd has
a @code{plymouth-quit} unit for that; a runit machine has this service, enabled
like any other, which quits once and then sleeps - a service whose program exits
is a service runsv starts again.

It is enabled on every machine and does nothing on one that turned the daemon
off with @code{plymouth.enable=0}: @command{plymouth --quit} fails there, and
the failure is the answer.  A machine that asks for the splash gets the rest of
it from this file, which is why the two travel together."
  "#!/bin/sh
# ====== Heks-Linux: the splash ends here ======
#
# auto-generated file, DO NOT EDIT!
#
# plymouthd starts in the initramfs and keeps the console until it is told to
# stop.  Nothing else on this machine tells it: without this, the login prompt
# is drawn underneath the boot logo.
plymouth --quit 2>/dev/null || true
# runsv restarts a service whose program exits, and this one has finished.
exec sleep infinity
")

;; What the installer writes into the command line about the splash: the daemon
;; stays off, and the passphrase is asked on the console.  `splash' here instead
;; is the whole of what a machine does to get the theme - the package, the
;; theme's four files and the service that ends it are already in the image.
(define plymouth-kernel-argument
  "plymouth.enable=0")

(define plymouth-packages
  '("plymouth" "plymouth-data"))
