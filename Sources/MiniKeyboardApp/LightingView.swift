import SwiftUI
import MiniKeyboardKit

/// Backlight controls for the selected layer.
///
/// The pad never reports its current lighting back, so this shows what the app
/// last set rather than what the hardware is doing. Changes are written
/// straight to the device, since lighting is the one setting you judge by
/// looking at it.
struct LightingView: View {
    @Bindable var model: AppModel

    private var setting: LedSetting? { model.profile.led(layer: model.selectedLayer) }

    static func swatch(_ color: Int) -> Color { swatches[color] ?? .gray }

    static let swatches: [Int: Color] = [
        1: Color(red: 0.93, green: 0.20, blue: 0.20),   // Red
        2: Color(red: 0.98, green: 0.55, blue: 0.14),   // Orange
        3: Color(red: 0.97, green: 0.83, blue: 0.20),   // Yellow
        4: Color(red: 0.25, green: 0.79, blue: 0.35),   // Green
        5: Color(red: 0.25, green: 0.82, blue: 0.85),   // Cyan
        6: Color(red: 0.24, green: 0.51, blue: 0.94),   // Blue
        7: Color(red: 0.68, green: 0.36, blue: 0.92),   // Purple
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lighting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if setting != nil {
                    Button("Reset") { model.clearLed() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Effect", selection: Binding(
                get: { setting?.mode ?? 1 },
                set: { model.setLed(mode: $0) }
            )) {
                ForEach(Array(LedSetting.modeNames.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(i)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            // Off and Rainbow ignore the colour, so don't offer a choice that
            // would do nothing.
            if setting?.usesColor ?? true {
                HStack(spacing: 7) {
                    ForEach(LedSetting.colorRange, id: \.self) { c in
                        let isSelected = setting?.color == c
                        Circle()
                            .fill(Self.swatch(c))
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? Theme.brass : Color.primary.opacity(0.15),
                                    lineWidth: isSelected ? 2.5 : 1)
                            }
                            .scaleEffect(isSelected ? 1.12 : 1)
                            .animation(.easeOut(duration: 0.12), value: isSelected)
                            .onTapGesture { model.setLed(color: c) }
                            .help(LedSetting.colorNames[c] ?? "")
                            .accessibilityLabel(LedSetting.colorNames[c] ?? "Colour \(c)")
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected]
                                                               : .isButton)
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 8) {
                Button("Colour-code layers") { model.applyLayerColorCoding() }
                    .controlSize(.small)
                    .help("Green, blue and red for layers 1, 2 and 3, so the pad "
                          + "shows which layer is live")
                if model.profile.isLayerColorCoded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.brass)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }

            Text(setting.map { "Layer \(model.selectedLayer + 1): \($0.describe)" }
                 ?? "Not set for this layer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07))
        }
    }
}
