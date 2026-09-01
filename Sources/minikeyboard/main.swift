import Foundation
import MiniKeyboardKit

let usage = """
minikeyboard — configure CH57x-family USB macro pads natively on Apple Silicon

USAGE
  minikeyboard list                       Show connected pads and their geometry
  minikeyboard read [--layer N]           Read the pad's current config as JSON
  minikeyboard apply <profile.json>       Write a profile to the pad
  minikeyboard set <key> <action> [--layer N]
                                          Program a single key
  minikeyboard clear                      Clear every key on every layer
  minikeyboard led <mode> [--color C] [--layer N]
                                          Set the backlight. Mode is a number
                                          0-5 or a name; colour is 1-7 or a name
  minikeyboard led --list                 Show the modes and colours
  minikeyboard led-layers                 Give each layer its own colour, so the
                                          pad shows which layer is live
  minikeyboard validate <profile.json>    Parse a profile without touching hardware
  minikeyboard keys                       List every key name the parser accepts
  minikeyboard presets                    List built-in shortcut sets
  minikeyboard presets <app>              Show one app's shortcuts
  minikeyboard preset <app> [--layer N]   Write an app's shortcuts to the pad
  minikeyboard cheatsheet [app]           Print a Markdown cheatsheet

ACTIONS
  ctrl+shift+a          a chord
  "ctrl+c, ctrl+v"      a macro, up to \(Wire.maxMacroSteps) steps
  media:volumeup        consumer keys (see `minikeyboard keys`)
  mouse:left            mouse buttons; also mouse:wheelup / mouse:wheeldown
  none                  clear the key

EXAMPLES
  minikeyboard presets zoom
  minikeyboard preset lightroom --layer 1
  minikeyboard cheatsheet > CHEATSHEET.md
  minikeyboard set 1 cmd+c
  minikeyboard set 3 "media:playpause" --layer 1
  minikeyboard read > mypad.json && minikeyboard apply mypad.json
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
        print("  " + (MouseUsage.buttons.keys.sorted() + ["wheelup", "wheeldown"])
                        .joined(separator: " "))
        print("\nModifiers:")
        print("  ctrl shift alt/option cmd/win  (prefix with r for right-hand)")

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
                    let hex = r.prefix(20).map { String(format: "%02X", $0) }
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
            let width = app.shortcuts.map(\.label.count).max() ?? 0
            for s in app.shortcuts {
                let action = (try? KeyAction.parse(s.action))?.displayLabel ?? s.action
                print("  \(s.label.padding(toLength: width, withPad: " ", startingAt: 0))"
                      + "   \(action)   [\(s.action)]")
            }
            print("\n  \(app.shortcuts.count) shortcuts. "
                  + "Write them with: minikeyboard preset \(app.id)")
        } else {
            for category in PresetLibrary.categories {
                print(category)
                for app in AppAvailability.sorted(PresetLibrary.apps(in: category)) {
                    let id = app.id.padding(toLength: 12, withPad: " ", startingAt: 0)
                    let mark = app.isUniversal ? " "
                             : (AppAvailability.location(of: app) != nil ? "\u{2713}" : " ")
                    print(" \(mark) \(id) \(app.name)  (\(app.shortcuts.count) shortcuts)")
                }
                print()
            }
            print("\u{2713} marks an app found on this Mac.")
            print("Show one with: minikeyboard presets <id>")
        }

    case "preset":
        guard let name = args.first else { fail("preset needs an app id") }
        args.removeFirst()
        let layer = flagValue("--layer", in: &args, default: 0)
        guard let app = PresetLibrary.app(id: name) else {
            fail("no preset named \"\(name)\". Run `minikeyboard presets`.")
        }
        let pad = try MacroPad.connect()
        defer { pad.close() }
        let geo = try pad.queryGeometry()
        let profile = try Profile(filling: app, layer: layer, geometry: geo)
        try pad.apply(profile)
        print("Wrote \(profile.assignments.count) \(app.name) shortcuts "
              + "to layer \(layer + 1).")
        if let note = app.note { print("Note: \(note)") }
        if app.shortcuts.count > geo.totalBindings {
            print("The pad has \(geo.totalBindings) bindings, so "
                  + "\(app.shortcuts.count - geo.totalBindings) shortcut(s) "
                  + "did not fit.")
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
                print("| Action | Shortcut | Binding |")
                print("|---|---|---|")
                for s in app.shortcuts {
                    let shown = (try? KeyAction.parse(s.action))?.displayLabel ?? s.action
                    print("| \(s.label) | \(shown) | `\(s.action)` |")
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
                  + "  [\(a.action.displayName)]")
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
        guard let key = Int(args[0]) else { fail("key index must be a number") }
        let action = try KeyAction.parse(args[1])
        let pad = try MacroPad.connect()
        defer { pad.close() }
        try pad.queryGeometry()
        var profile = Profile()
        profile.set(action, key: key, layer: layer)
        try pad.apply(profile)
        print("Key \(key) on layer \(layer) -> \(action.displayLabel)")

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
