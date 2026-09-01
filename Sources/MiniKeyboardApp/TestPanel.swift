import SwiftUI
import AppKit
import MiniKeyboardKit

/// One event seen while the tester was listening.
struct CapturedEvent: Identifiable {
    let id = UUID()
    let at: Date
    let symbol: String
    /// What was pressed, in the same wording a keycap uses.
    let label: String
    /// The binding text that would produce it.
    let token: String?
}

/// Press a key on the pad and see exactly what reached the Mac.
///
/// The pad is a keyboard as far as macOS is concerned, so there is no way to
/// ask it what it just sent. Watching the events it produces is the only way to
/// confirm a binding does what you meant, which is why this exists.
struct TestPanel: View {
    /// Closing is the parent's call, since this lives inside the main window.
    let close: () -> Void

    @State private var events: [CapturedEvent] = []
    @State private var typed = ""
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                typingArea
                Divider()
                eventLog
            }
        }
        .frame(height: 210)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text("Listening").font(.caption.weight(.semibold))
            Text("· press a key or turn a knob on the pad")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { events.removeAll(); typed = "" }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close the tester")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }

    private var typingArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $typed)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
                .overlay(alignment: .topLeading) {
                    if typed.isEmpty {
                        Text("Anything the pad types lands here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(12)
        .frame(minWidth: 220)
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Events").font(.caption.weight(.semibold))
                Spacer()
                Text("\(events.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            row(event).id(event.id)
                        }
                    }
                }
                .onChange(of: events.count) {
                    if let last = events.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
            .overlay {
                if events.isEmpty {
                    Text("Nothing yet.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 240)
    }

    private func row(_ event: CapturedEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.symbol)
                .font(.system(size: 10))
                .frame(width: 16)
                .foregroundStyle(Theme.brass)
            Text(event.label)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 6)
            if let token = event.token {
                Text(token)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Capture

    private func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.keyDown, .scrollWheel,
                                           .otherMouseDown, .systemDefined]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            if let captured = Self.describe(event) { record(captured) }
            return event   // never swallow it; the text area still needs it
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func record(_ event: CapturedEvent) {
        events.append(event)
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }

    /// Turns an AppKit event into the same wording the rest of the app uses.
    static func describe(_ event: NSEvent) -> CapturedEvent? {
        switch event.type {
        case .keyDown:
            guard let chord = KeyRecorder.Coordinator.chord(from: event) else { return nil }
            return CapturedEvent(at: .now, symbol: "keyboard",
                                 label: chord.displayLabel, token: chord.displayName)

        case .scrollWheel:
            // A knob turn arrives as a wheel event; Shift means it is panning.
            let horizontal = event.modifierFlags.contains(.shift)
                || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            let delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
            guard delta != 0 else { return nil }
            let action: KeyAction = horizontal
                ? .mouse(modifiers: .leftShift, buttons: 0, wheel: delta > 0 ? -1 : 1)
                : .mouse(buttons: 0, wheel: delta > 0 ? 1 : -1)
            return CapturedEvent(at: .now, symbol: "computermouse",
                                 label: action.displayLabel, token: action.displayName)

        case .otherMouseDown:
            let action = KeyAction.mouse(buttons: 0x04, wheel: 0)
            return CapturedEvent(at: .now, symbol: "computermouse",
                                 label: action.displayLabel, token: action.displayName)

        case .systemDefined:
            // Media keys arrive as subtype 8 with the key packed into data1.
            guard event.subtype.rawValue == 8 else { return nil }
            let keyCode = Int32((event.data1 & 0xFFFF_0000) >> 16)
            let isDown = ((event.data1 & 0x0000_FF00) >> 8) == 0x0A
            guard isDown, let usage = mediaUsage(forSystemKey: keyCode) else { return nil }
            let action = KeyAction.media(usage)
            return CapturedEvent(at: .now, symbol: "playpause",
                                 label: action.displayLabel, token: action.displayName)

        default:
            return nil
        }
    }

    /// NX_KEYTYPE_* codes to the consumer usages this library speaks.
    private static func mediaUsage(forSystemKey code: Int32) -> UInt16? {
        switch code {
        case 0:  return 0x00E9   // sound up
        case 1:  return 0x00EA   // sound down
        case 2:  return 0x006F   // brightness up
        case 3:  return 0x0070   // brightness down
        case 7:  return 0x00E2   // mute
        case 16: return 0x00CD   // play/pause
        case 17: return 0x00B5   // next
        case 18: return 0x00B6   // previous
        default: return nil
        }
    }
}
