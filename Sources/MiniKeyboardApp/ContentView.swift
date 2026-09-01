import SwiftUI
import UniformTypeIdentifiers
import MiniKeyboardKit

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showingImporter = false
    @State private var showingExporter = false

    var body: some View {
        VStack(spacing: 0) {
            DeviceBar(model: model)
            Divider()

            switch model.status {
            case .connected:
                HSplitView {
                    // The pad can be taller than the window on 16-key variants,
                    // so it scrolls rather than clipping.
                    ScrollView {
                        VStack(spacing: 16) {
                            LayerPicker(selection: $model.selectedLayer)
                            PadView(model: model)
                            Spacer(minLength: 0)
                        }
                        .padding(20)
                    }
                    .frame(minWidth: 440)

                    InspectorView(model: model)
                        .frame(minWidth: 300, idealWidth: 340)
                }
            case .disconnected, .error:
                EmptyStateView(model: model)
            }
        }
        .overlay(alignment: .bottom) { ToastView(model: model) }
        .toolbar {
            ToolbarItemGroup {
                Button { showingImporter = true } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open a profile")

                Button { showingExporter = true } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save this profile as JSON")

                Spacer()

                Button { model.readFromDevice() } label: {
                    Label("Read", systemImage: "arrow.down.circle")
                }
                .help("Read the pad's current configuration")
                .disabled(!model.isConnected)

                Button { model.apply() } label: {
                    Label("Apply", systemImage: "arrow.up.circle.fill")
                }
                .help("Write this profile to the pad")
                .disabled(!model.isConnected)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                model.load(from: url)
            }
        }
        .fileExporter(isPresented: $showingExporter,
                      document: ProfileDocument(profile: model.profile),
                      contentType: .json,
                      defaultFilename: model.profile.name) { result in
            if case .success(let url) = result { model.toast = "Saved \(url.lastPathComponent)." }
        }
    }
}

// MARK: - Device bar

struct DeviceBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            if let geo = model.geometry {
                Text("Connected").fontWeight(.medium)
                Text("· \(geo.describe)").foregroundStyle(.secondary)
            } else {
                Text("No pad connected").foregroundStyle(.secondary)
            }

            Spacer()

            if let busy = model.busyMessage {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary).font(.callout)
            } else if model.hasUnsavedChanges {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .labelStyle(DotLabelStyle())
                    .foregroundStyle(Theme.brass)
            }

            Button("Reconnect") { model.connect() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .font(.callout)
        .background(.bar)
    }
}

/// A tiny dot instead of a full icon, for inline status.
struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

// MARK: - Layers

struct LayerPicker: View {
    @SwiftUI.Binding var selection: Int

    var body: some View {
        Picker("Layer", selection: $selection) {
            ForEach(0..<Wire.layerCount, id: \.self) { i in
                Text("Layer \(i + 1)").tag(i)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("The pad stores three independent layers; switch layers on the device itself.")
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("No macro pad connected")
                .font(.title3.weight(.medium))

            if case .error(let message) = model.status {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Text("Plug in a pad and it will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Try Again") { model.connect() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toast

struct ToastView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
                .shadow(radius: 8, y: 2)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { model.toast = nil }
                }
        }
    }
}

// MARK: - Export

struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var profile: Profile

    init(profile: Profile) { self.profile = profile }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        profile = try JSONDecoder().decode(Profile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Profile.encoder.encode(profile))
    }
}
