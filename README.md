# Sirca Shell

I wanted my KDE desktop to look like glass, and I could not get there with Plasma's own panels, so I wrote my own. Sirca Shell
is a top bar and a dock for KDE Plasma 6 on Wayland. The popups (quick settings, launcher, notifications, the media player)
grow out of the bar and the dock instead of floating next to them. KWin is still your compositor and your apps do not
change. Only Plasma's panels get replaced, and one command brings them back.

https://github.com/user-attachments/assets/1a73bd3d-5c41-4f6a-a333-6b80d5c2df79

## Read this first

I use this every day, but on exactly one computer: Ubuntu 26.04, Plasma 6.6, an NVIDIA card and one ultrawide screen. It is
the work of one person. On your machine something will probably be off, and I would rather tell you now than have you find
out the hard way.

- While the shell is on, Plasma's panels are off. Your panel layout is saved first, and `sirca-shell-switch off` puts it back
  exactly as it was. If the shell crashes five times within a minute, Plasma's panels come back by themselves.
- It takes over some shortcuts while it runs: Meta, Meta+Space, Meta+V, Meta+A, Print, Meta+Shift+S and R, Ctrl+Alt+Del and
  Alt+Tab. You get them back when you switch it off.
- The blur and the glass edges come from a KWin effect plugin. It is optional and needs sudo. A compositor plugin runs inside
  KWin, so a bug in it can take your whole session down with it. It is also built for the exact KWin you have. After a
  Plasma upgrade KWin will refuse to load it until you run `./install.sh` again. Until then everything still works, it just
  looks flat.
- The app themes change your settings: KDE colour scheme, GTK 3 and 4 css, icon theme. Every step makes a backup and has a
  revert. The Qt style and window decoration (optional, sudo) replace the Darkly style plugin if you have Darkly. The
  original is kept next to it as `darkly6.so.orig-glass`.
- Only Plasma on Wayland. No X11, no Hyprland, Sway or GNOME.
- Several screens: every screen gets the wallpaper; the bar and the dock are on the primary screen unless you put them
  elsewhere in edit mode (Screens). Popups and shortcuts open on the primary. I have only tested this with two virtual
  screens, never on real hardware, so tell me what you see.
- I have never run it on AMD or Intel graphics. It should work. If it does not, I want to hear about it.
- No telemetry. It sends nothing anywhere.
- There is no warranty (GPL-3.0-or-later).

The installer goes through all of this with you before it touches anything, checks your system and says what will not work
on it, and lets you pick only the parts you want. `./install.sh --dry-run` prints every command and changes nothing.

### If something breaks

Open an issue and tell me what you ran and what happened. I will go through it with you until it works or until we know why
it cannot. I mean that: this has only ever run on my machine, so your problem is most likely a bug I have not seen yet, not
something you did wrong. Your Plasma version, your GPU and the output of `./install.sh --dry-run` are the most useful
things to include. If you cannot log in properly or your panels are gone, run `sirca-shell-switch off` from a terminal
first, then write to me.

## What it looks like

| | |
|:--:|:--:|
| ![Quick settings](screenshots/quick-settings.png) | ![Launcher](screenshots/launcher.png) |
| Quick settings: network, Bluetooth, audio, brightness, Do Not Disturb, colour themes | The launcher comes out of the dock. Meta+Space searches apps, files and settings, and does sums and unit conversions |
| ![Notifications](screenshots/notifications.png) | ![Now playing](screenshots/media.png) |
| Notifications with history, grouped per app, with replies and progress | What is playing, in the bar, with a level meter and a player popup |

![Window previews above the dock](screenshots/dock-previews.png)

The dock shows window previews when you hover an app, a small pill per open window and unread badges. Drag icons to reorder.

![Edit mode: the bar and the dock with their settings next to them](screenshots/edit-mode.jpg)

Right-click the bar or the dock to edit them in place. You can drag widgets around, resize things, and set blur, tint and
haze for each surface. There is also a tile picker (Meta+A), screenshots and screen recording (Meta+Shift+S and R) and
a clipboard history with pinning (Meta+V).

### Light, dark and seven colours

One switch changes the shell, KDE and GTK apps, the icons and the wallpaper at the same time, in one cross-fade. The
wallpapers in the pictures are the ones in `wallpapers/`, so what you install looks like this.

| Dark | Light |
|:--:|:--:|
| ![Blue, dark](screenshots/dark-blue.jpg) | ![Blue, light](screenshots/light-blue.jpg) |
| ![Cyan, dark](screenshots/dark-cyan.jpg) | ![Cyan, light](screenshots/light-cyan.jpg) |
| ![Green, dark](screenshots/dark-green.jpg) | ![Green, light](screenshots/light-green.jpg) |
| ![Yellow, dark](screenshots/dark-yellow.jpg) | ![Yellow, light](screenshots/light-yellow.jpg) |
| ![Red, dark](screenshots/dark-red.jpg) | ![Red, light](screenshots/light-red.jpg) |
| ![Pink, dark](screenshots/dark-pink.jpg) | ![Pink, light](screenshots/light-pink.jpg) |
| ![Purple, dark](screenshots/dark-purple.jpg) | ![Purple, light](screenshots/light-purple.jpg) |

Click a picture to see it at 3440 × 1440.

KDE and GTK apps get the same glass, which is what you see in the pictures: Dolphin, a terminal and the Spotify mini
player. The Spotify theme, Firefox accent colours and Ghostty styling are optional extras.

## Install

```
git clone https://github.com/onuroluc/sirca-shell.git
cd sirca-shell
./install.sh
```

You can take just the shell (no root needed), the shell plus the look, or my whole setup with wallpapers and app themes.

```
sirca-shell-switch on      # saves your Plasma panels and takes over
sirca-shell-switch off     # your panels come back exactly as they were
./uninstall.sh             # removes what was installed, part by part
```

Keep the cloned folder if you install the light/dark switch. `glass-mode` and the theme generators run from it.

## What works and what does not

| | |
|---|---|
| KDE Plasma 6.6, Wayland, KWin | yes, this is what I use |
| KDE Plasma 6.7 | builds and runs against 6.7.5 in a headless test session (bar, dock, launcher, quick settings, the KWin effects). I do not use 6.7 day to day yet, so tell me what you see |
| Older Plasma 6 | maybe. The shell might miss things, and the KWin effect is picky about versions |
| X11, Hyprland, Sway, GNOME | no |
| One screen | yes |
| Several screens | wallpaper on all, bar and dock per screen from edit mode. Tested with two virtual screens only |
| Without the KWin effect | works, but flat: see-through surfaces with no blur and no lit edge |
| NVIDIA | yes, developed on it |
| AMD, Intel | untested. Please tell me how it goes |

## What is in here

| folder | what |
|---|---|
| `shell/` | the shell itself (C++ and QML). Its README lists every feature, the settings, scripting and the build dependencies |
| `kwin-effects/` | the glass KWin effect (blur, refraction, lit edge, shapes the shell describes to it) and Glass Key, which puts glass inside apps that paint opaque windows |
| `desktop/` | the look for everything else: KDE colour scheme, GTK 3 and 4, Qt style and window decoration, `glass-mode` (light, dark, colour themes), the lock screen and the app extras |
| `wallpapers/` | the wallpapers I use: one picture in seven colours, dark and light (5120 × 1440) |
| `setups/` | the colour themes, and my bar and dock layout as a file for `sirca-shell-setup import` |

## Licence and credits

Everything written for this project is GPL-3.0-or-later, see `LICENSE`. A lot of it stands on other people's work, and each
folder keeps their notices:

- `kwin-effects/` is a fork of **kwin-effects-glass** by 4v3ngR, itself a fork of KWin's blur effect (KDE) by way of Better Blur; GPL-3.0.
- `desktop/qt/darkly-fork/` is a fork of **Darkly** (itself a fork of Lightly / Breeze), GPL-2.0-or-later; see its `COPYING`.
- `desktop/third_party/adw-gtk3/` is **adw-gtk3** by lassekongo83, LGPL-2.1.
- `shell/qml/control/` derives from **Plasma Control Hub** by zayronxio; `shell/applets/` holds forks of KDE Plasma applets (their headers are kept).
- Fonts: **Outfit** and **Inter**, SIL Open Font License.
- Icons: **Papirus** (GPL-3) by the Papirus Development Team. Not bundled; the installer fetches it if you do not have it, and the folder colours follow the colour theme.

Thank you to all of them.
