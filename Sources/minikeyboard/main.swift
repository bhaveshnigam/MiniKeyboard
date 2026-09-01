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
  minikeyboard validate <profile.json>    Parse a profile without touching hardware
  minikeyboard keys                       List every key name the parser accepts

ACTIONS
  ctrl+shift+a          a chord
  "ctrl+c, ctrl+v"      a macro, up to \(Wire.maxMacroSteps) steps
  media:volumeup        consumer keys (see `minikeyboard keys`)
  mouse:left            mouse buttons; also mouse:wheelup / mouse:wheeldown
  none                  clear the key

EXAMPLES
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
            print("  layer \(a.layer) key \(a.key): \(a.action.displayName)")
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
        print("Key \(key) on layer \(layer) -> \(action.displayName)")

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
    fail("\(error)")
}
