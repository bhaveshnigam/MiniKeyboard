import SwiftUI
import AppKit
import MiniKeyboardKit

/// Editor for the currently selected binding.
struct InspectorView: View {
    @Bindable var model: AppModel
    @State private var text = ""
    @State private var parseError: String?
    @State private var isRecording = false

    private var binding: Binding? {
        model.bindings.first { $0.index == model.selection }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let binding {
                    header(binding)
                    editor(binding)
                    presets(binding)
                } else {
                    Text("Select a key to edit it.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selection) { syncFromModel() }
        .onChange(of: model.selectedLayer) { syncFromModel() }
        .onAppear { syncFromModel() }
    }

    // MARK: - Sections

    private func header(_ binding: Binding) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(binding.accessibilityLabel)
                .font(.title3.weight(.semibold))
            Text("Layer \(model.selectedLayer + 1)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func editor(_ binding: Binding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("e.g. ctrl+shift+a", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { commit(binding) }
                .disabled(isRecording)

            if let parseError {
                Label(parseError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button(isRecording ? "Stop" : "Record…") {
                    isRecording.toggle()
                }
                .help("Press a shortcut on your Mac keyboard to capture it")

                Button("Apply") { commit(binding) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text == model.action(for: binding).displayName)

                Spacer()

                Button("Clear") {
                    text = "none"
                    commit(binding)
                }
            }

            if isRecording {
                Text("Listening — press any shortcut.")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            Text("""
                Chords like `cmd+c`, macros like `cmd+c, cmd+v` \
                (up to \(Wire.maxMacroSteps) steps), `media:volumeup`, or `mouse:left`.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(KeyRecorder(isRecording: $isRecording) { chord in
            text = chord.displayName
            isRecording = false
            commit(binding)
        })
    }

    private func presets(_ binding: Binding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Common")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let common = [
                ("Copy", "cmd+c"), ("Paste", "cmd+v"), ("Undo", "cmd+z"),
                ("Screenshot", "cmd+shift+4"), ("Mission Control", "ctrl+up"),
                ("Play / Pause", "media:playpause"), ("Mute", "media:mute"),
                ("Volume Up", "media:volumeup"), ("Volume Down", "media:volumedown"),
            ]
            FlowLayout(spacing: 6) {
                ForEach(common, id: \.1) { label, value in
                    Button(label) {
                        text = value
                        commit(binding)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Editing

    private func syncFromModel() {
        guard let binding else { text = ""; return }
        text = model.action(for: binding).displayName
        parseError = nil
        isRecording = false
    }

    private func commit(_ binding: Binding) {
        do {
            let action = try KeyAction.parse(text)
            model.setAction(action, for: binding)
            text = action.displayName
            parseError = nil
        } catch {
            parseError = "\(error)"
        }
    }
}

/// Captures one real key press from the Mac keyboard and turns it into a `Chord`.
struct KeyRecorder: NSViewRepresentable {
    @SwiftUI.Binding var isRecording: Bool
    let onCapture: (Chord) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.isRecording = isRecording
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var isRecording = false
        var onCapture: ((Chord) -> Void)?
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                guard let chord = Self.chord(from: event) else { return nil }
                self.onCapture?(chord)
                return nil   // swallow the event so it does not reach the text field
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { remove() }

        /// Maps an `NSEvent` to the pad's HID usage plus modifier bitmask.
        static func chord(from event: NSEvent) -> Chord? {
            var mods: Modifiers = []
            if event.modifierFlags.contains(.control) { mods.insert(.leftControl) }
            if event.modifierFlags.contains(.shift)   { mods.insert(.leftShift) }
            if event.modifierFlags.contains(.option)  { mods.insert(.leftOption) }
            if event.modifierFlags.contains(.command) { mods.insert(.leftCommand) }

            guard let usage = usageForVirtualKey(event.keyCode) else { return nil }
            return Chord(modifiers: mods, usage: usage)
        }

        /// Carbon virtual key code -> HID usage (page 0x07).
        private static let virtualKeyMap: [UInt16: UInt8] = [
            0x00: 0x04, 0x0B: 0x05, 0x08: 0x06, 0x02: 0x07, 0x0E: 0x08, 0x03: 0x09,
            0x05: 0x0A, 0x04: 0x0B, 0x22: 0x0C, 0x26: 0x0D, 0x28: 0x0E, 0x25: 0x0F,
            0x2E: 0x10, 0x2D: 0x11, 0x1F: 0x12, 0x23: 0x13, 0x0C: 0x14, 0x0F: 0x15,
            0x01: 0x16, 0x11: 0x17, 0x20: 0x18, 0x09: 0x19, 0x0D: 0x1A, 0x07: 0x1B,
            0x10: 0x1C, 0x06: 0x1D,
            0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x17: 0x22, 0x16: 0x23,
            0x1A: 0x24, 0x1C: 0x25, 0x19: 0x26, 0x1D: 0x27,
            0x24: 0x28, 0x35: 0x29, 0x33: 0x2A, 0x30: 0x2B, 0x31: 0x2C,
            0x1B: 0x2D, 0x18: 0x2E, 0x21: 0x2F, 0x1E: 0x30, 0x2A: 0x31,
            0x29: 0x33, 0x27: 0x34, 0x32: 0x35, 0x2B: 0x36, 0x2F: 0x37, 0x2C: 0x38,
            0x39: 0x39,
            0x7A: 0x3A, 0x78: 0x3B, 0x63: 0x3C, 0x76: 0x3D, 0x60: 0x3E, 0x61: 0x3F,
            0x62: 0x40, 0x64: 0x41, 0x65: 0x42, 0x6D: 0x43, 0x67: 0x44, 0x6F: 0x45,
            0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B, 0x75: 0x4C, 0x77: 0x4D, 0x79: 0x4E,
            0x7C: 0x4F, 0x7B: 0x50, 0x7D: 0x51, 0x7E: 0x52,
        ]

        static func usageForVirtualKey(_ code: UInt16) -> UInt8? { virtualKeyMap[code] }
    }
}

/// Wraps buttons onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
