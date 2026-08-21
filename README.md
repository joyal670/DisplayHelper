# DisplayHelper

A macOS menu-bar utility that keeps the display awake and the system marked active
while you are away. Toggle it from the menu bar.

When **ON**, every 30 seconds it checks the system idle time. Past a 4-minute idle
threshold it posts a no-op `F15` keypress — which does nothing on a normal keyboard —
to reset the idle timer, and holds a `caffeinate` process so the display and system
will not sleep. When **OFF** it does nothing at all.

## Build

```sh
swiftc -O main.swift -o DisplayHelper
```

To produce the app bundle installed at `~/Applications/DisplayHelper.app`
(bundle id `local.displayhelper`), place the compiled binary at
`DisplayHelper.app/Contents/MacOS/DisplayHelper`.

## Tuning

Constants at the top of `main.swift`:

| Constant | Default | Meaning |
|---|---|---|
| `IDLE_THRESHOLD` | `240` | seconds idle before nudging |
| `CHECK_EVERY` | `30` | how often to check, in seconds |
| `F15_KEYCODE` | `113` | key code posted as the no-op nudge |

## Permissions

Posting synthetic key events requires **Accessibility** access:
System Settings → Privacy & Security → Accessibility.
