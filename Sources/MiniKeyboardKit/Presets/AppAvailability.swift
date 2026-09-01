import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Finds out which of the preset apps are actually installed, so the library
/// can lead with the ones you can use today.
///
/// Presets for apps you do not have stay visible and stay usable — you might be
/// setting up a pad for another machine, or installing the app next. This only
/// affects ordering and labelling. Nothing is looked up over the network and no
/// permissions are required: it asks LaunchServices, then falls back to reading
/// the standard Applications folders.
public enum AppAvailability {

    /// Where an app is installed, or nil if it is not.
    public static func location(of preset: AppPreset) -> URL? {
        #if canImport(AppKit)
        for id in preset.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        #endif
        if let prefix = preset.namePrefix {
            return scanApplications(matching: prefix)
        }
        return nil
    }

    public static func isInstalled(_ preset: AppPreset) -> Bool {
        preset.isUniversal || location(of: preset) != nil
    }

    /// Presets ordered so installed apps come first, then universal ones, then
    /// the rest — each group keeping its catalog order.
    public static func sorted(_ presets: [AppPreset] = PresetLibrary.apps) -> [AppPreset] {
        var installed: [AppPreset] = []
        var universal: [AppPreset] = []
        var others: [AppPreset] = []
        for preset in presets {
            if preset.isUniversal {
                universal.append(preset)
            } else if location(of: preset) != nil {
                installed.append(preset)
            } else {
                others.append(preset)
            }
        }
        return installed + universal + others
    }

    /// Bundle-versioned apps like Adobe's change their identifier between
    /// releases, so fall back to a name match.
    private static func scanApplications(matching prefix: String) -> URL? {
        let fm = FileManager.default
        var roots = [URL(fileURLWithPath: "/Applications")]
        if let home = fm.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(home)
        }
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else { continue }

            // Adobe nests the app one level down: /Applications/Adobe X/Adobe X.app
            for entry in entries {
                let name = entry.deletingPathExtension().lastPathComponent
                if entry.pathExtension == "app", name.hasPrefix(prefix) { return entry }
                if entry.hasDirectoryPath, name.hasPrefix(prefix),
                   let inner = try? fm.contentsOfDirectory(
                       at: entry, includingPropertiesForKeys: nil,
                       options: [.skipsHiddenFiles]),
                   let app = inner.first(where: {
                       $0.pathExtension == "app"
                       && $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix)
                   }) {
                    return app
                }
            }
        }
        return nil
    }
}
