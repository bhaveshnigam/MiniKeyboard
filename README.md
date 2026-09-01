# MiniKeyboard

A native macOS app and CLI for configuring the cheap CH57x-based USB macro pads
(3/4/6/9/12/16 keys, plus rotary knobs) sold under a hundred different names.

The configurator these pads ship with is a 38 MB Qt app built for Intel only, so
it needs Rosetta — which is going away in macOS 28. This is a ground-up
rewrite: Swift, SwiftUI, IOKit, no third-party dependencies, 904 KB.

<img src="Resources/screenshot.png" width="760" alt="MiniKeyboard configuring a 12-key, 2-knob pad">

## What it does

- Reads your pad's current layout off the device
- Edits all three layers, every key and every knob direction
- Chords (`cmd+c`), macros up to 18 steps (`cmd+c, cmd+v`), media keys, mouse buttons and wheel
- Adjustable gap between macro keystrokes, for apps that drop input sent at full speed
- Records a shortcut by pressing it on your Mac keyboard
- Backlight control: six effects, seven colours, set per layer — including
  one-click colour coding so the pad shows which layer is live
- Ready-made shortcut sets for Slack, Teams, Zoom, Lightroom Classic, Photoshop,
  Final Cut, VS Code and more — sorted so apps you actually have come first
- Saves layouts as readable JSON you can keep in a dotfiles repo
- Ships as both an app and a CLI

## Install

```sh
git clone https://github.com/<you>/MiniKeyboard.git
cd MiniKeyboard
make install          # app into /Applications, CLI into /usr/local/bin
```

Or build the pieces separately:

```sh
make build            # library, CLI and app for this Mac
make app              # dist/MiniKeyboard.app
make universal        # arm64 + x86_64
make test             # 30 tests, no hardware required
```

## CLI

```sh
minikeyboard list                      # show connected pads and geometry
minikeyboard read > mypad.json         # dump the current layout
minikeyboard apply mypad.json          # write a layout
minikeyboard set 1 cmd+c               # program a single key
minikeyboard set 3 media:playpause --layer 1
minikeyboard clear                     # wipe every key on every layer
minikeyboard led solid --color green   # backlight; also `led --list`
minikeyboard led reactive --layer 1    # light only the key being pressed
minikeyboard led-layers                # green/blue/red for layers 1/2/3
minikeyboard set 5 "cmd+c, cmd+v" --delay 200   # macro with a 200 ms gap
minikeyboard variant                   # show the pad's declared model
minikeyboard validate mypad.json       # check a file without touching hardware
minikeyboard keys                      # list every accepted key name
minikeyboard doctor                    # dump raw HID traffic, for debugging
```

### Presets

```sh
minikeyboard presets                   # list built-in sets, ✓ marks installed apps
minikeyboard presets zoom              # show one app's shortcuts
minikeyboard preset lightroom --layer 1  # write a whole set to a layer
minikeyboard cheatsheet > CHEATSHEET.md  # generate a Markdown guide
```

[docs/CHEATSHEET.md](docs/CHEATSHEET.md) is the generated guide, covering every
built-in set.

In the app, **Presets** opens a browser: apps installed on this Mac are listed
first with their own icons, and everything else stays available — you might be
setting up a pad for another machine. Assign one shortcut to the selected key,
or fill the whole layer at once.

Shortcuts are macOS defaults at the time of writing. Apps let people rebind
their own, and vendors change defaults between versions, so treat a preset as a
starting point. `PresetLibrary` is a plain Swift table if you want to add your
own, and a test asserts every entry parses.

### Actions

| Form | Example |
|------|---------|
| Chord | `ctrl+shift+a`, `cmd+c` |
| Macro | `"cmd+c, cmd+v"` (up to 18 steps) |
| Media | `media:volumeup`, `media:playpause`, `media:calculator` |
| Mouse | `mouse:left`, `mouse:wheelup` |
| Clear | `none` |

Modifiers are `ctrl`, `shift`, `alt`/`option`, `cmd`/`win`. Prefix with `r` for
the right-hand variant (`rshift+a`).

### Profiles

```json
{
  "name" : "Editing",
  "geometry" : { "keyCount" : 12, "knobCount" : 2 },
  "assignments" : [
    { "key" : 1,  "layer" : 0, "action" : "cmd+c" },
    { "key" : 4,  "layer" : 0, "action" : "cmd+c, cmd+v" },
    { "key" : 16, "layer" : 0, "action" : "media:volumedown" }
  ]
}
```

Keys are 1-based. Layers are 0-based. Knobs live at fixed slots starting at 16:
knob *n* occupies `16 + 3n` (turn left), `17 + 3n` (press), `18 + 3n` (turn right).

## Supported hardware

USB vendor `0x1189`, products `0x8840`, `0x8842`, `0x8830`–`0x8833`, `0x8850`,
`0x8851`. Verified against a 12-key / 2-knob pad (`1189:8842`).

If `minikeyboard list` finds nothing, run `minikeyboard doctor` — it prints every
matching HID interface and the raw bytes the pad returns.

## Protocol

The pad speaks HID output reports on its vendor-defined interface
(usage page `0xFF00`). Reports are 65 bytes: a `0x03` prefix and 64 bytes of body.

| Command | Packet | Meaning |
|---------|--------|---------|
| Query | `03 FB FB FB` | Reply carries key count at byte 2, knob count at byte 3 |
| Read | `03 FA 0F 03 <layer>` | Pad streams back every record for that layer |
| Program | `03 <50-byte record>` | Set one key |
| Commit | `03 FD FE FF` | Close the transaction |
| Backlight | `03 FE B0 <layer> 08 …` | Set the lighting for one layer |
| Bootloader | `03 EF EF` | Enter firmware update mode — destructive |

Each key is a 50-byte record:

```
[0]        0xFD command
[1]        key index, 1-based
[2]        layer, 1-based
[3]        mode: 1 keyboard, 2 media, 3 mouse
[9]        step count (or 4 for the mouse payload)
[10 + 2n]  modifier bitmask for step n
[11 + 2n]  HID usage for step n
```

Media bindings store a 16-bit HID Consumer usage little-endian across bytes 10
and 11 (`E9 00` is volume up). Mouse bindings put modifiers at 10, the button at
11, and a signed wheel delta at 14.

The backlight record lives in **slot 0** of each layer, which is why key records
start at index 1 and a layer read never returns it. Its mode byte is `8`, and
byte 11 packs the effect in the low nibble and the colour in the high nibble —
`0x41` is Solid Green.

| Effect | | Colour | |
|---|---|---|---|
| 0 | Off | 1 | Red |
| 1 | Solid | 2 | Orange |
| 2 | Wave | 3 | Yellow |
| 3 | Wave reverse | 4 | Green |
| 4 | Reactive (lights the pressed key) | 5 | Cyan |
| 5 | Rainbow (reads as white) | 6 | Blue |
| | | 7 | Purple |

Off and Rainbow ignore the colour.

### Colour-coded layers

The layer is switched on the pad itself and nothing on screen reflects it, so
which layer is live is the one bit of state that is genuinely easy to lose track
of. `minikeyboard led-layers`, or the button in the app, gives each layer its own
solid colour — green, blue, red — which turns the backlight into a layer
indicator. Green, blue and red are the most separable of the seven available and
differ in lightness as well as hue, so they stay distinguishable for the common
forms of colour blindness.

### Keystroke delay

A key holding a macro can carry a gap between its keystrokes, 0-6000 ms, which
matters because some apps drop input sent at full speed. It is a **separate
record**: mode 5 with the value at bytes 4 and 5, sent after the action record.
A mode 5 record that also contains an action stores the delay and discards the
action, so the order matters.

The firmware swaps those two bytes between paths — a value written low byte
first comes back high byte first. Writes stay little-endian to match the
original app; reads are decoded big-endian.

### Declared model

`03 FC FC <keys> <knobs>` tells the pad what model it is, and it accepts
fourteen geometries: 2+0, 3+1, 4+0, 4+1, 5+0, 6+0, 6+1, 6+2, 9+2, 9+3, 11+3,
12+2, 12+3, 15+3. `minikeyboard variant` shows the current one. This is only for
a pad that misreports itself, so it is CLI-only and not reachable from the app —
claiming keys the hardware does not have leaves the pad describing keys that are
not there.

### What the firmware does not expose

**Per-key colours are not possible on the stock firmware.** The LEDs are
individually addressable — the wave and reactive effects prove it — but that
addressing happens on the pad's own MCU. The host only ever sends one mode and
one colour for the whole layer.

This was tested, not assumed. Sending per-key colour bytes after byte 11 turns
the whole pad the colour of byte 11 and ignores the rest, and mode values 6-15
all fall back to Solid. The vendor's own app, the only other known client of
this firmware, exposes nothing but the six global effects and seven global
colours. Getting per-key colour would mean replacing the firmware.

`Sources/MiniKeyboardKit/Protocol/` is the reference implementation, and
`Tests/` pins it to bytes captured from real hardware.

## Parity with the original app

Every function in the original binary was walked and checked against this build.

| Original | Here |
|---|---|
| BaseKeys tab | Chords and macros |
| Ctrl Shift Alt tab | Modifiers, as part of a chord |
| MutiMedia tab | `media:` bindings |
| Mouse tab | `mouse:` bindings, including modified wheel |
| RGB LED tab | Lighting panel and `led` |
| DelaySetting tab | Keystroke gap |
| Layer 1/2/3 | Three layers |
| Reading Device | `read`, and on connect |
| Download | Apply |
| clear / Clear All | `clear` and Clear |
| Dialog1 pad-size picker | Not needed — geometry is read from the pad |
| Dialog2 alternate editor | Not needed — the view follows any geometry |
| Firmware update button | `enterBootloader` exists but is deliberately unreachable |
| English / Chinese toggle | **English only** |
| Windows drive-letter helper | Vestigial in the original; irrelevant on macOS |

Not in the original: JSON profiles, a CLI, app shortcut presets, colour-coded
layers, cheatsheet generation, and `doctor` / `raw` for protocol work.

## Development

```
Sources/MiniKeyboardKit/   protocol, IOKit transport, profiles, presets — no UI
Sources/minikeyboard/      CLI
Sources/MiniKeyboardApp/   SwiftUI app
Tests/                     57 tests, none needing a device
```

Device access sits behind a `Transport` protocol, so the driver is tested
against an in-memory fake. The packet encoder is pure, which is what lets the
whole wire format be verified without plugging anything in.

```sh
make check                     # tests plus a clean release build
make release VERSION=1.1.0     # verify, package, and tag
```

## Notes

- Requires macOS 14 or later.
- The app is ad-hoc signed. On first launch macOS may ask you to confirm it;
  right-click the app and choose Open if Gatekeeper objects.
- Back up before experimenting: `minikeyboard read > backup.json`.
- `enterBootloader` is deliberately unreachable from the UI. Once sent, the pad
  stops answering configuration commands until it is replugged or reflashed.

## License

MIT
