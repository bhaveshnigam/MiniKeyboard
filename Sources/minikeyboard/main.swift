import Foundation
import MiniKeyboardKit

let usage = """
minikeyboard — configure CH57x-family USB macro pads natively on Apple Silicon

USAGE
  Device
    list                          Show connected pads and their geometry
    read [--layer N]              Read the pad's current config as JSON
    apply <profile.json>          Write a profile to the pad
    set <key> <action> [--layer N] [--delay MS]
                                  Program one key. --delay is the gap between
                                  macro keystrokes, 0-\(Wire.maxDelay) ms
    clear                         Clear every key on every layer

  Lighting
    led <mode> [--color C] [--layer N]
                                  Set the backlight. Mode is 0-5 or a name,
                                  colour is 1-7 or a name
    led --list                    Show every effect and colour
    led-layers                    Give each layer its own colour, so the pad
                                  shows which layer is live

  Presets
    presets                       List built-in shortcut sets
    presets <app>                 Show one app's shortcuts
    preset <app> [--layer N]      Write an app's shortcuts to a layer
    preset <app> --export         Print it as a profile instead of writing
    cheatsheet [app]              Print a Markdown cheatsheet

  Offline
    validate <profile.json>       Parse a profile without touching hardware
    keys                          List every key name the parser accepts

  Diagnostics
    doctor                        Show HID interfaces and dump raw traffic
    variant [<keys> <knobs>]      Show or set the pad's declared model
    raw <hex...> [--commit]       Send a raw report, for protocol work

ACTIONS
  ctrl+shift+a          a chord
  "ctrl+c, ctrl+v"      a macro, up to \(Wire.maxMacroSteps) steps
  media:volumeup        consumer keys (see `minikeyboard keys`)
  mouse:left            mouse buttons; also mouse:wheelup / mouse:wheeldown
  ctrl+mouse:wheelup    a modifier held with the wheel
  none                  clear the key

  Modifiers are ctrl, shift, alt/option and cmd/win. Prefix with r for the
  right-hand variant, as in rshift+a.

EXAMPLES
  minikeyboard read > mypad.json          # back up before experimenting
  minikeyboard apply mypad.json           # and restore it
  minikeyboard set 1 cmd+c
  minikeyboard set 5 "cmd+c, cmd+v" --delay 200
  minikeyboard set 3 media:playpause --layer 1
  minikeyboard presets zoom
  minikeyboard preset lightroom --layer 1
  minikeyboard led solid --color green
  minikeyboard led-layers
  minikeyboard cheatsheet > CHEATSHEET.md
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func flagValue(_ name: String, in args: inout [String], default def: Int) -> Int {
    guard let i = args.firstIndex(of: name) else { return def }
    guard i + 1 < args.count, let v = Int(args[i + 1]) else {
        fail("\(name) needs a number")
    }
    args.removeSubrange(i...(i + 1))
    return v
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

do {
    switch command {
    case "-h", "--help", "help":
        print(usage)

    case "keys":
        print("Keyboard keys:")
        print("  " + HIDUsage.byName.keys.sorted().joined(separator: " "))
        print("\nMedia (prefix with media:):")
        print("  " + MediaUsage.byName.keys.sorted().joined(separator: " "))
        print("\nMouse (prefix with mouse:):")
        print("  " + (MouseUsage.buttons.keys.sorted() + MouseUsage.wheelNames)
                        .joined(separator: " "))
        print("\nModifiers:")
        print("  ctrl shift alt/option cmd/win  (prefix with r for right-hand)")

    case "variant":
        let pad = try MacroPad.connect()
        defer { pad.close() }
        let current = try pad.queryGeometry()
        if args.count < 2 {
            print("Reported: \(current.describe)")
            print("\nKnown variants (keys + knobs):")
            for v in Packet.knownVariants {
                let mark = v == current ? " <- current" : ""
                print("  \(v.keyCount) + \(v.knobCount)\(mark)")
            }
            print("\nSet with: minikeyboard variant <keys> <knobs>")
            print("Only do this if the pad reports itself wrong; telling it it "
                  + "has keys it does not have makes it claim keys that are not there.")
            break
        }
        guard let k = Int(args[0]), let n = Int(args[1]) else {
            fail("variant needs two numbers: keys and knobs")
        }
        let wanted = Geometry(keyCount: k, knobCount: n)
        try pad.setVariant(wanted)
        print("Told the pad it is \(wanted.describe). Replug it to re-enumerate.")

    case "raw":
        var commit = false
        if let i = args.firstIndex(of: "--commit") { commit = true; args.remove(at: i) }
        let bytes = args.joined(separator: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .compactMap { UInt8($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
        guard !bytes.isEmpty else { fail("raw needs hex bytes, e.g. 03 FE B0 01 08") }
        guard bytes.count <= Wire.outputReportLength else {
            fail("a report is at most \(Wire.outputReportLength) bytes")
        }
        var report = bytes
        report.append(contentsOf:
            [UInt8](repeating: 0, count: Wire.outputReportLength - report.count))
        let t = try IOKitTransport.open()
        defer { t.close() }
        try t.write(report)
        if commit { try t.write(Packet.commit()) }
        print("Sent \(bytes.count) byte(s)"
              + (commit ? " plus commit" : "") + ": "
              + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))

    case "doctor":
        let interfaces = IOKitTransport.interfaces()
        guard !interfaces.isEmpty else {
            print("No matching HID interface for vendor 0x1189.")
            exit(1)
        }
        print("Matching HID interfaces:")
        for i in interfaces { print("  " + i.describe) }

        for i in interfaces where i.isVendorDefined {
            print("\nProbing \(i.describe)")
            let t = try IOKitTransport.open(i)
            defer { t.close() }
            try t.write(Packet.queryGeometry())
            if let response = try t.read(timeout: 1.0) {
                let hex = response.prefix(16)
                    .map { String(format: "%02X", $0) }.joined(separator: " ")
                print("  response (\(response.count) bytes): \(hex) …")
                for (n, b) in response.prefix(8).enumerated() where b != 0 {
                    print("    byte[\(n)] = \(b) (0x\(String(format: "%02X", b)))")
                }
            } else {
                print("  no response within 1s")
            }

            for layer in 0..<Wire.layerCount {
                print("  -- layer \(layer + 1) dump --")
                try t.write(Packet.readLayer(layer))
                var n = 0
                while let r = try t.read(timeout: 0.4) {
                    n += 1
                    let hex = r.prefix(26).map { String(format: "%02X", $0) }
                        .joined(separator: " ")
                        + "  …  "
                        + r.dropFirst(44).prefix(8).map { String(format: "%02X", $0) }
                            .joined(separator: " ")
                    print("    [\(n)] \(hex)")
                    if n > 40 { break }
                }
                if n == 0 { print("    (no records)") }
            }
        }

    case "presets":
        if let name = args.first {
            guard let app = PresetLibrary.app(id: name) else {
                fail("no preset named \"\(name)\". Run `minikeyboard presets`.")
            }
            print("\(app.name)  (\(app.category))")
            if let note = app.note { print("  Note: \(note)") }
            print()
            let all = app.shortcuts + app.knobs.flatMap(\.inOrder)
            let width = all.map(\.label.count).max() ?? 0
            func row(_ s: ShortcutPreset, prefix: String = "  ") {
                let action = (try? KeyAction.parse(s.action))?.displayLabel ?? s.action
                print("\(prefix)\(s.label.padding(toLength: width, withPad: " ", startingAt: 0))"
                      + "   \(action)   [\(s.action)]")
            }
            print("Keys")
            for s in app.shortcuts { row(s) }
            if !app.knobs.isEmpty {
                for (i, knob) in app.knobs.enumerated() {
                    print("\nKnob \(i + 1) — \(knob.name)")
                    row(knob.counterClockwise, prefix: "  \u{21BA} ")
                    row(knob.press,            prefix: "  \u{25CF} ")
                    row(knob.clockwise,        prefix: "  \u{21BB} ")
                }
            }
            print("\n  \(app.shortcuts.count) keys, \(app.knobs.count) knobs. "
                  + "Write them with: minikeyboard preset \(app.id)")
        } else {
            for category in PresetLibrary.categories {
                print(category)
                for app in AppAvailability.sorted(PresetLibrary.apps(in: category)) {
                    let id = app.id.padding(toLength: 12, withPad: " ", startingAt: 0)
                    let mark = app.isUniversal ? " "
                             : (AppAvailability.location(of: app) != nil ? "\u{2713}" : " ")
                    print(" \(mark) \(id) \(app.name)"
                          + "  (\(app.shortcuts.count) keys, \(app.knobs.count) knobs)")
                }
                print()
            }
            print("\u{2713} marks an app found on this Mac.")
            print("Show one with: minikeyboard presets <id>")
        }

    case "preset":
        guard let name = args.first else { fail("preset needs an app id") }
        args.removeFirst()
        var exporting = false
        if let i = args.firstIndex(of: "--export") { exporting = true; args.remove(at: i) }
        let layer = flagValue("--layer", in: &args, default: 0)
        guard let app = PresetLibrary.app(id: name) else {
            fail("no preset named \"\(name)\". Run `minikeyboard presets`.")
        }
        // Exporting needs no hardware, so a profile can be prepared anywhere.
        if exporting {
            let geo = (try? MacroPad.connect().queryGeometry())
                ?? Geometry(keyCount: 12, knobCount: 2)
            let profile = try Profile(filling: app, layer: layer, geometry: geo)
            print(try profile.jsonString())
            break
        }
        let pad = try MacroPad.connect()
        defer { pad.close() }
        let geo = try pad.queryGeometry()
        let profile = try Profile(filling: app, layer: layer, geometry: geo)
        try pad.apply(profile)
        print("Wrote \(profile.assignments.count) \(app.name) shortcuts "
              + "to layer \(layer + 1).")
        if let note = app.note { print("Note: \(note)") }
        if app.shortcuts.count > geo.keyCount {
            print("The pad has \(geo.keyCount) keys, so "
                  + "\(app.shortcuts.count - geo.keyCount) key shortcut(s) did not fit.")
        }
        if app.knobs.count > geo.knobCount {
            print("The pad has \(geo.knobCount) knob(s), so "
                  + "\(app.knobs.count - geo.knobCount) knob set(s) did not fit.")
        }

    case "cheatsheet":
        let selected = args.first.flatMap { PresetLibrary.app(id: $0) }
        if args.first != nil && selected == nil {
            fail("no preset named \"\(args[0])\". Run `minikeyboard presets`.")
        }
        let apps = selected.map { [$0] } ?? PresetLibrary.apps
        print("# Macro pad shortcut cheatsheet\n")
        print("Bindings you can program with `minikeyboard set` or paste into a profile.")
        print("Shortcuts are macOS defaults; apps let you rebind them, so check anything")
        print("that does not work.\n")
        for category in PresetLibrary.categories {
            let inCategory = apps.filter { $0.category == category }
            guard !inCategory.isEmpty else { continue }
            print("## \(category)\n")
            for app in inCategory {
                print("### \(app.name)\n")
                if let note = app.note { print("> \(note)\n") }
                func line(_ s: ShortcutPreset, _ where_: String) {
                    let shown = (try? KeyAction.parse(s.action))?.displayLabel ?? s.action
                    print("| \(where_) | \(s.label) | \(shown) | `\(s.action)` |")
                }
                print("| Where | Action | Shortcut | Binding |")
                print("|---|---|---|---|")
                for (i, s) in app.shortcuts.enumerated() { line(s, "Key \(i + 1)") }
                for (i, knob) in app.knobs.enumerated() {
                    line(knob.counterClockwise, "Knob \(i + 1) left")
                    line(knob.press,            "Knob \(i + 1) press")
                    line(knob.clockwise,        "Knob \(i + 1) right")
                }
                print()
            }
        }

    case "list":
        let devices = IOKitTransport.discoverAll()
        if devices.isEmpty {
            print("No supported pad found (looking for USB vendor 0x1189).")
            exit(1)
        }
        print("Found \(devices.count) matching HID interface(s).")
        let pad = try MacroPad.connect()
        defer { pad.close() }
        let geo = try pad.queryGeometry()
        print("Connected pad: \(geo.describe) — \(geo.totalBindings) bindings x \(Wire.layerCount) layers")

    case "read":
        let layer = flagValue("--layer", in: &args, default: -1)
        let pad = try MacroPad.connect()
        defer { pad.close() }
        var profile = try pad.readProfile()
        if layer >= 0 {
            profile.assignments = profile.assignments.filter { $0.layer == layer }
        }
        profile.name = "Read from device"
        print(try profile.jsonString())

    case "validate":
        guard let path = args.first else { fail("validate needs a profile path") }
        let profile = try Profile.load(from: URL(fileURLWithPath: path))
        print("OK — \(profile.assignments.count) assignment(s) across \(Wire.layerCount) layers")
        for a in profile.assignments.sorted(by: { ($0.layer, $0.key) < ($1.layer, $1.key) }) {
            print("  layer \(a.layer) key \(a.key): \(a.action.displayLabel)"
                  + "  [\(a.action.displayName)]"
                  + (a.delay.map { "  delay \($0)ms" } ?? ""))
        }

    case "apply":
        guard let path = args.first else { fail("apply needs a profile path") }
        let profile = try Profile.load(from: URL(fileURLWithPath: path))
        let pad = try MacroPad.connect()
        defer { pad.close() }
        try pad.queryGeometry()
        try pad.apply(profile) { done, total in
            print("\rwriting \(done)/\(total)", terminator: "")
            fflush(stdout)
        }
        print("\rApplied \(profile.assignments.count) assignment(s).")

    case "set":
        guard args.count >= 2 else { fail("set needs a key index and an action") }
        let layer = flagValue("--layer", in: &args, default: 0)
        let delay = flagValue("--delay", in: &args, default: -1)
        guard delay <= Wire.maxDelay else {
            fail("--delay must be 0-\(Wire.maxDelay) milliseconds")
        }
        guard let key = Int(args[0]) else { fail("key index must be a number") }
        let action = try KeyAction.parse(args[1])
        let pad = try MacroPad.connect()
        defer { pad.close() }
        try pad.queryGeometry()
        var profile = Profile()
        profile.set(action, key: key, layer: layer, delay: delay >= 0 ? delay : nil)
        try pad.apply(profile)
        print("Key \(key) on layer \(layer) -> \(action.displayLabel)"
              + (delay >= 0 ? "  (delay \(delay) ms)" : ""))

    case "led":
        if args.contains("--list") {
            print("Modes:")
            for (i, name) in LedSetting.modeNames.enumerated() {
                print("  \(i)  \(name)")
            }
            print("\nColours:")
            for i in LedSetting.colorRange {
                print("  \(i)  \(LedSetting.colorNames[i] ?? "")")
            }
            print("\nOff and Rainbow ignore the colour.")
            break
        }
        guard let modeArg = args.first else {
            fail("led needs a mode, 0-\(LedSetting.modeRange.upperBound) or a name."
                 + " Run `minikeyboard led --list`.")
        }
        guard let mode = Int(modeArg) ?? LedSetting.mode(named: modeArg) else {
            fail("unknown mode \"\(modeArg)\". Run `minikeyboard led --list`.")
        }
        args.removeFirst()
        // Colour accepts a name or a number.
        var color = 5
        if let i = args.firstIndex(of: "--color"), i + 1 < args.count {
            let raw = args[i + 1]
            guard let c = Int(raw) ?? LedSetting.color(named: raw) else {
                fail("unknown colour \"\(raw)\". Run `minikeyboard led --list`.")
            }
            color = c
            args.removeSubrange(i...(i + 1))
        }
        let ledLayer = flagValue("--layer", in: &args, default: 0)
        guard LedSetting.modeRange.contains(mode) else {
            fail("mode must be \(LedSetting.modeRange.lowerBound)-\(LedSetting.modeRange.upperBound)")
        }
        guard LedSetting.colorRange.contains(color) else {
            fail("colour must be \(LedSetting.colorRange.lowerBound)-\(LedSetting.colorRange.upperBound)")
        }
        let setting = LedSetting(mode: mode, color: color)
        let pad = try MacroPad.connect()
        defer { pad.close() }
        try pad.queryGeometry()
        try pad.setLed(setting, layer: ledLayer)
        print("Backlight on layer \(ledLayer + 1): \(setting.describe) "
              + "(byte 0x\(String(format: "%02X", setting.packed)))")

    case "led-layers":
        let pad = try MacroPad.connect()
        defer { pad.close() }
        try pad.queryGeometry()
        try pad.applyLayerColorCoding()
        print("Colour-coded the layers:")
        for layer in 0..<Wire.layerCount {
            print("  Layer \(layer + 1): \(LedSetting.defaultForLayer(layer).describe)")
        }

    case "clear":
        let pad = try MacroPad.connect()
        defer { pad.close() }
        try pad.queryGeometry()
        try pad.clearAll()
        print("Cleared all keys.")

    default:
        fail("unknown command \"\(command)\". Run `minikeyboard help`.")
    }
} catch {
    fail(readableMessage(for: error))
}
