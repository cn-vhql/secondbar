# SecondBar

A small menu bar item that folds rarely used status icons into a second bar, and
lets you click them from there.

Built for macOS 27, where the menu bar became a single window and every divider
trick stopped working. Hiding here uses the system's own assessment mode
(`MenuBarClientCore`, private framework), so nothing is faked with screenshots or
overlays.

## What it does

- One `»` item in the menu bar.
- Click it: a popover lists the folded icons. Click one and its own menu opens.
- ⌥-click it, or right-click → 管理收起的应用…: a window where each app's fold
  state is a switch.
- ⌥-click an icon inside the popover: keep that app in the menu bar for good.
- Right-click → 开机启动: launch at login (`SMAppService`, with a LaunchAgent as
  fallback for an unsigned build).

## Requirements

- macOS 27 or later.
- Accessibility permission, needed to read and press other apps' status items. The
  app asks once and waits; granting does not require a relaunch.

## Build and install

```sh
./make-identity.sh   # once: a stable self-signed identity, so the permission survives rebuilds
./build.sh           # -> build/SecondBar.app
./install.sh         # -> /Applications/SecondBar.app, then launches it
```

`make-identity.sh` matters: TCC remembers the permission by signing identity, and
an ad-hoc signature has none, so an ad-hoc build has to be re-authorised after
every rebuild. The app must live in `/Applications` — otherwise macOS hides its
own icon too.

## Self-tests

The app can be driven deterministically, which is how it was verified (a
screenshot of an auto-hiding menu bar proves very little):

```sh
SecondBar --dump-ui /tmp/ui.png      # render the manager window offscreen
SecondBar --show-ui                  # show it, printing its screen rect
SecondBar --probe-press <bundle>     # is an item pressable, and does a menu open
SECOND_BAR_DEBUG=1 SECOND_BAR_DEBUG_FILE=/tmp/cmd /Applications/SecondBar.app/Contents/MacOS/SecondBar
```

Debug commands, one per line in that file: `open:<bundle>`, `toggle:<bundle>`,
`restore:<bundle>`, `collapse`, `expand`, `panel`, `close`, `manager`.

## Limitations

macOS decides these, not this app:

- **Per app, not per icon.** One app's icons fold and unfold together.
- **System items cannot be folded.** Clock, Wi-Fi, battery, Control Center are not
  third-party items and stay put.
- **Some apps ignore `AXPress`.** Measured on macOS 27: WireGuard, UURemote and
  Lumen open their menu; WeChat, QQ, CC Switch and the weather extra report
  success and open nothing, even when fully visible. Synthetic mouse events do not
  work on other apps' status items either, so those apps get brought to the front
  instead of showing a broken click.
- **Assessment mode suppresses the microphone and camera indicators** while it is
  active. Hiding is released on quit.

## Layout

```
Sources/
  main.swift          entry point and the self-test flags
  AppDelegate.swift   status item, expand/collapse, opening a folded icon
  Sections.swift      which apps are folded (stored by bundle identifier)
  Hiding.swift        wraps the assessment-mode assertion
  Shim.h / Shim.m     dlopen + objc_msgSend, since the framework is private
  AXReader.swift      reading and pressing status items
  Panel.swift         the popover
  ManageWindow.swift  the manager window
  LoginItem.swift     launch at login
  SampleApps.swift    stand-in rows for --dump-ui
tools/makeicon.swift  draws the app icon
```

Log: `~/Library/Logs/SecondBar.log`.
