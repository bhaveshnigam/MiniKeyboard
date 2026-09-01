import SwiftUI
import AppKit
import MiniKeyboardKit

/// The pad, drawn to match the geometry the device reported.
struct PadView: View {
    @Bindable var model: AppModel

    private var keyBindings: [PadBinding] {
        model.bindings.filter { if case .key = $0.kind { true } else { false } }
    }
    private var knobCount: Int { model.geometry?.knobCount ?? 0 }

    /// Physical arrangement per variant. A 12-key pad is four across and three
    /// down, which is what the vendor's own app draws — not three across.
    private static let gridColumns: [Int: Int] = [
        3: 3, 4: 4, 5: 5, 6: 3, 8: 4, 9: 3,
        11: 4, 12: 4, 15: 5, 16: 4,
    ]

    private var columns: Int {
        let n = keyBindings.count
        guard n > 0 else { return 1 }
        if let known = Self.gridColumns[n] { return known }
        if n % 4 == 0 { return 4 }
        if n % 3 == 0 { return 3 }
        return min(n, 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let source = model.layerSource() {
                LayerSourceBadge(source: source) { model.clearLayerSource() }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 74),
                                                   spacing: Theme.capSpacing),
                               count: columns),
                spacing: Theme.capSpacing
            ) {
                ForEach(keyBindings) { binding in
                    KeyCapView(binding: binding,
                               action: model.action(for: binding),
                               purpose: model.purpose(for: binding),
                               isSelected: model.selection == binding.index)
                        .onTapGesture { model.selection = binding.index }
                }
            }

            if knobCount > 0 {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(0..<knobCount, id: \.self) { i in
                        DialView(model: model, knobIndex: i)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .background(Theme.housing, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.07))
        }
    }
}

// MARK: - Keycap

/// One key, drawn as a physical cap: a skirt with a face sitting on top.
struct KeyCapView: View {
    let binding: PadBinding
    let action: KeyAction
    /// What the binding is for, when a preset supplied it.
    var purpose: String?
    let isSelected: Bool
    var compact = false

    @State private var isHovering = false

    private var isEmpty: Bool { action == .none }

    var body: some View {
        ZStack {
            // Skirt — the moulding that gives the cap its depth.
            RoundedRectangle(cornerRadius: Theme.capRadius)
                .fill(Theme.capSkirt)

            // Face, inset and lifted.
            RoundedRectangle(cornerRadius: Theme.capRadius - 2)
                .fill(Theme.capFace)
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .padding(.bottom, Theme.capSkirtDepth + 2)
                .overlay(alignment: .top) {
                    // A hairline of light along the top edge reads as a bevel.
                    RoundedRectangle(cornerRadius: Theme.capRadius - 2)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .padding(.horizontal, 2)
                        .padding(.top, 2)
                        .padding(.bottom, Theme.capSkirtDepth + 2)
                        .blendMode(.softLight)
                }

            legend
                .padding(.horizontal, 5)
                .padding(.bottom, Theme.capSkirtDepth)
        }
        .frame(height: compact ? 54 : 70)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.capRadius)
                .strokeBorder(Theme.brass, lineWidth: isSelected ? 2.5 : 0)
        }
        .shadow(color: .black.opacity(isHovering ? 0.22 : 0.14),
                radius: isHovering ? 5 : 3, y: isHovering ? 3 : 2)
        .scaleEffect(isHovering && !isSelected ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onHover { isHovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: Theme.capRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(binding.accessibilityLabel)
        .accessibilityValue(isEmpty ? "unassigned" : action.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var legend: some View {
        VStack(spacing: 1) {
            Text(binding.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.legend.opacity(0.45))

            // What it does leads; the shortcut that does it follows, because
            // "Mute" is the thing you scan the pad for, not "shift+cmd+m".
            if let purpose, !isEmpty {
                Text(purpose)
                    .font(.system(size: compact ? 10 : 11.5, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.legend)
                Text(action.displayLabel)
                    .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.legend.opacity(0.5))
            } else {
                Text(action.displayLabel)
                    .font(.system(size: compact ? 10.5 : 12, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isEmpty ? Theme.legend.opacity(0.3) : Theme.legend)
            }
        }
    }
}

// MARK: - Knob

/// A rotary encoder, drawn as a dial with a legend.
///
/// Cramming three bindings inside the ring makes all three unreadable, so the
/// ring carries selection state and direction while the legend below carries
/// the text. Both are clickable.
struct DialView: View {
    @Bindable var model: AppModel
    let knobIndex: Int

    private static let order: [PadBinding.Kind.Knob] = [.counterClockwise, .press, .clockwise]

    private func binding(_ dir: PadBinding.Kind.Knob) -> PadBinding? {
        model.bindings.first {
            if case .knob(let i, let d) = $0.kind { i == knobIndex && d == dir } else { false }
        }
    }
    private func isSelected(_ dir: PadBinding.Kind.Knob) -> Bool {
        guard let b = binding(dir) else { return false }
        return model.selection == b.index
    }
    private func action(_ dir: PadBinding.Kind.Knob) -> KeyAction {
        guard let b = binding(dir) else { return .none }
        return model.action(for: b)
    }
    private func select(_ dir: PadBinding.Kind.Knob) {
        if let b = binding(dir) { model.selection = b.index }
    }

    private func purpose(_ dir: PadBinding.Kind.Knob) -> String? {
        guard let b = binding(dir) else { return nil }
        return model.purpose(for: b)
    }

    private func symbol(_ dir: PadBinding.Kind.Knob) -> String {
        switch dir {
        case .counterClockwise: "arrow.counterclockwise"
        case .press:            "circle.fill"
        case .clockwise:        "arrow.clockwise"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            dial
            legend
        }
        .frame(width: 168)
    }

    // MARK: - Ring

    private var dial: some View {
        ZStack {
            sector(.counterClockwise, from: 188, to: 352)
            sector(.clockwise, from: 8, to: 172)

            Circle()
                .fill(isSelected(.press) ? Theme.brass.opacity(0.20) : Theme.capFace)
                .overlay {
                    Circle().strokeBorder(
                        isSelected(.press) ? Theme.brass : Color.primary.opacity(0.12),
                        lineWidth: isSelected(.press) ? 2.5 : 1)
                }
                .overlay {
                    Image(systemName: "circle.and.line.horizontal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.legend.opacity(0.55))
                }
                .padding(24)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .contentShape(Circle().inset(by: 24))
                .onTapGesture { select(.press) }
                .accessibilityElement()
                .accessibilityLabel("Knob \(knobIndex + 1) press")
                .accessibilityValue(action(.press).displayName)

            Text("\(knobIndex + 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .offset(y: 34)
        }
        .frame(width: 96, height: 96)
    }

    private func sector(_ dir: PadBinding.Kind.Knob, from: Double, to: Double) -> some View {
        let selected = isSelected(dir)
        let shape = AnnularSector(startAngle: from, endAngle: to, thickness: 18)
        let midAngle = (from + to) / 2 - 90
        let radius: CGFloat = 39
        return shape
            .fill(selected ? Theme.brass.opacity(0.24) : Theme.capSkirt)
            .overlay { shape.stroke(selected ? Theme.brass : Color.clear, lineWidth: 2.5) }
            .overlay {
                Image(systemName: symbol(dir))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selected ? Theme.brass : Theme.legend.opacity(0.55))
                    .offset(x: cos(midAngle * .pi / 180) * radius,
                            y: sin(midAngle * .pi / 180) * radius)
            }
            .contentShape(shape)
            .onTapGesture { select(dir) }
            .accessibilityElement()
            .accessibilityLabel("Knob \(knobIndex + 1) "
                                + (dir == .clockwise ? "turn right" : "turn left"))
            .accessibilityValue(action(dir).displayName)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(spacing: 3) {
            ForEach(Self.order, id: \.self) { dir in
                let selected = isSelected(dir)
                let a = action(dir)
                HStack(spacing: 6) {
                    Image(systemName: symbol(dir))
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 11)
                        .foregroundStyle(selected ? Theme.brass : .secondary)
                    // Prefer what the binding is for, when a preset said so.
                    Text(purpose(dir) ?? a.displayLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(a == .none ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Theme.brass.opacity(0.16) : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onTapGesture { select(dir) }
                // The tooltip carries the token you would type or store.
                // The tooltip carries the token you would type or store.
                .help(a == .none ? "Unassigned"
                                 : (purpose(dir).map { "\($0) — \(a.displayName)" }
                                    ?? a.displayName))
            }
        }
    }
}


/// Says whose shortcuts a layer is carrying.
struct LayerSourceBadge: View {
    let source: Profile.LayerSource
    let clear: () -> Void

    private var preset: AppPreset? { PresetLibrary.app(id: source.appID) }

    var body: some View {
        HStack(spacing: 8) {
            if let preset, let url = AppAvailability.location(of: preset) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(Theme.brass)
            }
            Text(source.inferred ? "Looks like \(source.appName)"
                                 : "\(source.appName) shortcuts")
                .font(.caption.weight(.medium))
            Spacer(minLength: 0)
            Button("Clear labels", action: clear)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(source.inferred
                      ? "Recognised from the bindings, not set by you. Keep them, drop the labels"
                      : "Keep the bindings, drop the preset labelling")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.brass.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.brass.opacity(0.35))
        }
    }
}
