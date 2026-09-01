import SwiftUI
import MiniKeyboardKit

/// The physical pad, drawn to match whatever geometry the device reported.
struct PadView: View {
    @Bindable var model: AppModel

    private var keyBindings: [Binding] {
        model.bindings.filter { if case .key = $0.kind { true } else { false } }
    }
    private var knobIndices: [Int] {
        guard let geo = model.geometry else { return [] }
        return Array(0..<geo.knobCount)
    }

    /// Pads in this family are laid out three across (3/6/9/12 keys), except
    /// the 4- and 16-key variants which are square.
    private var columns: Int {
        let n = keyBindings.count
        if n == 0 { return 1 }
        if n % 4 == 0 && n % 3 != 0 { return 4 }
        return min(n, 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !keyBindings.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 72), spacing: 10),
                                   count: columns),
                    spacing: 10
                ) {
                    ForEach(keyBindings) { binding in
                        KeyCapView(binding: binding,
                                   action: model.action(for: binding),
                                   isSelected: model.selection == binding.index)
                            .onTapGesture { model.selection = binding.index }
                    }
                }
            }

            if !knobIndices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Knobs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(knobIndices, id: \.self) { i in
                            KnobView(model: model, knobIndex: i)
                        }
                    }
                }
            }
        }
    }
}

/// One rotary encoder: turn left, press, turn right.
struct KnobView: View {
    @Bindable var model: AppModel
    let knobIndex: Int

    private var directions: [Binding] {
        model.bindings.filter {
            if case .knob(let i, _) = $0.kind { i == knobIndex } else { false }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(directions) { binding in
                    KeyCapView(binding: binding,
                               action: model.action(for: binding),
                               isSelected: model.selection == binding.index,
                               compact: true)
                        .onTapGesture { model.selection = binding.index }
                }
            }
            Text("Knob \(knobIndex + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A single key cap showing its binding.
struct KeyCapView: View {
    let binding: Binding
    let action: KeyAction
    let isSelected: Bool
    var compact = false

    private var isEmpty: Bool { action == .none }

    var body: some View {
        VStack(spacing: 3) {
            Text(binding.label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(isEmpty ? "—" : action.displayName)
                .font(.system(size: compact ? 10 : 12, weight: .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEmpty ? .secondary : .primary)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 52 : 68)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16)
                                 : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(binding.accessibilityLabel)
        .accessibilityValue(isEmpty ? "unassigned" : action.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
