import SwiftUI
import AppKit
import MiniKeyboardKit

/// Browse the built-in shortcut sets and put them on the pad.
///
/// Apps found on this Mac are listed first and carry their own icon. The rest
/// stay available — you might be setting up a pad for another machine.
struct PresetBrowser: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selected: AppPreset.ID?
    @State private var search = ""

    private var groups: [(category: String, apps: [AppPreset])] {
        PresetLibrary.categories.compactMap { category in
            let apps = AppAvailability.sorted(PresetLibrary.apps(in: category))
                .filter { matches($0) }
            return apps.isEmpty ? nil : (category, apps)
        }
    }

    private func matches(_ app: AppPreset) -> Bool {
        guard !search.isEmpty else { return true }
        if app.name.localizedCaseInsensitiveContains(search) { return true }
        return app.shortcuts.contains { $0.label.localizedCaseInsensitiveContains(search) }
    }

    private var current: AppPreset? {
        PresetLibrary.apps.first { $0.id == selected }
    }

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(width: 780, height: 540)
        .onAppear {
            if selected == nil { selected = AppAvailability.sorted().first?.id }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(groups, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.apps) { app in
                            AppRow(preset: app).tag(app.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 230, idealWidth: 250)
        .searchable(text: $search, placement: .sidebar, prompt: "Search apps and actions")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let app = current {
            VStack(alignment: .leading, spacing: 0) {
                header(app)
                Divider()
                shortcutList(app)
                Divider()
                footer(app)
            }
            .frame(minWidth: 420)
        } else {
            Text("Pick an app.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ app: AppPreset) -> some View {
        HStack(spacing: 12) {
            AppIcon(preset: app, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.title3.weight(.semibold))
                Text("\(app.shortcuts.count) shortcuts")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !app.isUniversal && AppAvailability.location(of: app) == nil {
                Text("Not installed")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func shortcutList(_ app: AppPreset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let note = app.note {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.brass.opacity(0.08))
                }
                ForEach(Array(app.shortcuts.enumerated()), id: \.element.id) { index, s in
                    ShortcutRow(shortcut: s,
                                isEven: index.isMultiple(of: 2),
                                canAssign: model.selection != nil) {
                        model.assign(s)
                    }
                }
            }
        }
    }

    private func footer(_ app: AppPreset) -> some View {
        HStack {
            Text("Assigning replaces whatever is on layer \(model.selectedLayer + 1).")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Close") { dismiss() }
            Button("Fill Layer \(model.selectedLayer + 1)") {
                model.fillLayer(with: app)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .help("Put these shortcuts on every key of this layer, in order")
        }
        .padding(12)
    }
}

// MARK: - Rows

private struct AppRow: View {
    let preset: AppPreset

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(preset: preset, size: 18)
            Text(preset.name).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(preset.shortcuts.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: ShortcutPreset
    let isEven: Bool
    let canAssign: Bool
    let assign: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(shortcut.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(shortcut.parsed?.displayLabel ?? shortcut.action)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Assign", action: assign)
                .controlSize(.small)
                .opacity(hovering && canAssign ? 1 : 0)
                .disabled(!canAssign)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isEven ? Color.primary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if canAssign { assign() } }
        .help(shortcut.action)
    }
}

/// The app's own icon when it is installed, a neutral placeholder otherwise.
private struct AppIcon: View {
    let preset: AppPreset
    let size: CGFloat

    var body: some View {
        if let url = AppAvailability.location(of: preset) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: preset.isUniversal ? "square.grid.2x2" : "app.dashed")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
