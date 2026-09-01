import Foundation

/// One programmable shortcut: what it does, and the binding that produces it.
public struct ShortcutPreset: Identifiable, Sendable, Hashable, Codable {
    /// What the shortcut does, in the app's own words.
    public let label: String
    /// The binding, in the same syntax profiles and the CLI use.
    public let action: String

    public var id: String { "\(label)|\(action)" }

    public init(_ label: String, _ action: String) {
        self.label = label
        self.action = action
    }

    /// The parsed binding, or nil if the catalog entry is malformed.
    public var parsed: KeyAction? { try? KeyAction.parse(action) }
}

/// What a rotary encoder does in a preset.
///
/// Rotation has to be something you can repeat — volume, scrolling, stepping
/// through photos. Filling knobs from the same flat list as the keys puts
/// things like "Search" on a turn, which is useless.
public struct KnobPreset: Sendable, Hashable, Codable {
    /// What the knob controls, e.g. "Volume".
    public let name: String
    public let counterClockwise: ShortcutPreset
    public let press: ShortcutPreset
    public let clockwise: ShortcutPreset

    public init(_ name: String,
                ccw: ShortcutPreset, press: ShortcutPreset, cw: ShortcutPreset) {
        self.name = name
        self.counterClockwise = ccw
        self.press = press
        self.clockwise = cw
    }

    /// In pad slot order: turn left, press, turn right.
    public var inOrder: [ShortcutPreset] { [counterClockwise, press, clockwise] }
}

/// A curated set of shortcuts for one application.
public struct AppPreset: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    public let category: String
    /// Anything the user needs to know before relying on these.
    public let note: String?
    /// Bundle identifiers this preset targets, used to detect whether the app
    /// is installed. Empty means the preset is not tied to one app.
    public let bundleIDs: [String]
    /// Fallback for apps whose bundle id changes between versions, matched
    /// against app names in the standard Applications folders.
    public let namePrefix: String?
    /// Shortcuts for the physical keys.
    public let shortcuts: [ShortcutPreset]
    /// What each knob does, in order.
    public let knobs: [KnobPreset]
    /// Backlight colour to set with the layer, picked to match the app's own
    /// branding so the pad says which app it is set up for at a glance.
    public let color: Int

    public init(id: String, name: String, category: String,
                note: String? = nil,
                bundleIDs: [String] = [],
                namePrefix: String? = nil,
                color: Int = 5,
                knobs: [KnobPreset] = [],
                shortcuts: [ShortcutPreset]) {
        self.id = id
        self.name = name
        self.category = category
        self.note = note
        self.bundleIDs = bundleIDs
        self.namePrefix = namePrefix
        self.color = LedSetting.clampColor(color)
        self.knobs = knobs
        self.shortcuts = shortcuts
    }

    /// Solid, in the app's colour.
    public var lighting: LedSetting { LedSetting(mode: 1, color: color) }

    /// Every binding this preset defines, keys then knobs.
    public var totalBindings: Int { shortcuts.count + knobs.count * Wire.slotsPerKnob }

    /// True when the preset is not tied to a specific installed app.
    public var isUniversal: Bool { bundleIDs.isEmpty && namePrefix == nil }
}

/// Ready-made shortcut sets for common apps.
///
/// These are the macOS defaults at the time of writing. Apps let users rebind
/// their own shortcuts, and vendors change defaults between versions, so treat
/// a preset as a starting point and check anything that does not work.
public enum PresetLibrary {

    public static let apps: [AppPreset] = [
        macOS, textEditing, slack, teams, zoom, meet, discord,
        lightroomClassic, photoshop, finalCut, davinci,
        vscode, browser, figma, excel, obs,
    ]

    public static func app(id: String) -> AppPreset? {
        apps.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// Categories in the order they should be listed.
    public static var categories: [String] {
        var seen = Set<String>()
        return apps.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    public static func apps(in category: String) -> [AppPreset] {
        apps.filter { $0.category == category }
    }

    // MARK: - System

    static let macOS = AppPreset(
        id: "macos", name: "macOS", category: "System",
                color: 5,
        knobs: [
            KnobPreset("Volume",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Mute", "media:mute"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
            KnobPreset("Brightness",
                       ccw: ShortcutPreset("Brightness down", "media:brightnessdown"),
                       press: ShortcutPreset("Play / pause", "media:playpause"),
                       cw: ShortcutPreset("Brightness up", "media:brightnessup")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
        ],
        shortcuts: [
            ShortcutPreset("Mission Control", "ctrl+up"),
            ShortcutPreset("Application windows", "ctrl+down"),
            ShortcutPreset("Move left a space", "ctrl+left"),
            ShortcutPreset("Move right a space", "ctrl+right"),
            ShortcutPreset("Spotlight", "cmd+space"),
            ShortcutPreset("Screenshot selection", "shift+cmd+4"),
            ShortcutPreset("Screenshot whole screen", "shift+cmd+3"),
            ShortcutPreset("Screen recording", "shift+cmd+5"),
            ShortcutPreset("Lock screen", "ctrl+cmd+q"),
            ShortcutPreset("Force quit", "alt+cmd+esc"),
            ShortcutPreset("Switch app", "cmd+tab"),
            ShortcutPreset("Quit app", "cmd+q"),
            ShortcutPreset("Hide app", "cmd+h"),
            ShortcutPreset("Full screen", "ctrl+cmd+f"),
            ShortcutPreset("Volume up", "media:volumeup"),
            ShortcutPreset("Volume down", "media:volumedown"),
            ShortcutPreset("Mute", "media:mute"),
            ShortcutPreset("Play / pause", "media:playpause"),
            ShortcutPreset("Next track", "media:next"),
            ShortcutPreset("Previous track", "media:previous"),
            ShortcutPreset("Brightness up", "media:brightnessup"),
            ShortcutPreset("Brightness down", "media:brightnessdown"),
        ])

    static let textEditing = AppPreset(
        id: "text", name: "Text editing", category: "System",
        note: "Works in almost any Mac app.",
                color: 5,
        knobs: [
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("History",
                       ccw: ShortcutPreset("Undo", "cmd+z"),
                       press: ShortcutPreset("Save", "cmd+s"),
                       cw: ShortcutPreset("Redo", "shift+cmd+z")),
            KnobPreset("Pan",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Click", "mouse:left"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
        ],
        shortcuts: [
            ShortcutPreset("Copy", "cmd+c"),
            ShortcutPreset("Cut", "cmd+x"),
            ShortcutPreset("Paste", "cmd+v"),
            ShortcutPreset("Paste and match style", "shift+alt+cmd+v"),
            ShortcutPreset("Copy then paste", "cmd+c, cmd+v"),
            ShortcutPreset("Undo", "cmd+z"),
            ShortcutPreset("Redo", "shift+cmd+z"),
            ShortcutPreset("Select all", "cmd+a"),
            ShortcutPreset("Save", "cmd+s"),
            ShortcutPreset("Find", "cmd+f"),
            ShortcutPreset("Bold", "cmd+b"),
            ShortcutPreset("Italic", "cmd+i"),
            ShortcutPreset("Underline", "cmd+u"),
        ])

    // MARK: - Meetings and chat

    static let slack = AppPreset(
        id: "slack", name: "Slack", category: "Meetings & chat",
        bundleIDs: ["com.tinyspeck.slackmacgap"],
                color: 7,
        knobs: [
            KnobPreset("Unread channels",
                       ccw: ShortcutPreset("Previous unread", "shift+alt+up"),
                       press: ShortcutPreset("Mark all read", "shift+esc"),
                       cw: ShortcutPreset("Next unread", "shift+alt+down")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Volume",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Mute", "media:mute"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
        ],
        shortcuts: [
            ShortcutPreset("Quick switcher", "cmd+k"),
            ShortcutPreset("Search", "cmd+g"),
            ShortcutPreset("Toggle mute in huddle", "shift+cmd+space"),
            ShortcutPreset("Toggle video in huddle", "shift+cmd+v"),
            ShortcutPreset("All unreads", "shift+cmd+a"),
            ShortcutPreset("Threads", "shift+cmd+t"),
            ShortcutPreset("Direct messages", "shift+cmd+k"),
            ShortcutPreset("Activity", "shift+cmd+m"),
            ShortcutPreset("Mark all read", "shift+esc"),
            ShortcutPreset("Next unread channel", "shift+alt+down"),
            ShortcutPreset("Previous unread channel", "shift+alt+up"),
            ShortcutPreset("Set a status", "shift+cmd+y"),
            ShortcutPreset("Toggle sidebar", "shift+cmd+d"),
            ShortcutPreset("New message", "cmd+n"),
        ])

    static let teams = AppPreset(
        id: "teams", name: "Microsoft Teams", category: "Meetings & chat",
        bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
                color: 7,
        knobs: [
            KnobPreset("Call",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Toggle mute", "shift+cmd+m"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Pan",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Click", "mouse:left"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
        ],
        shortcuts: [
            ShortcutPreset("Toggle mute", "shift+cmd+m"),
            ShortcutPreset("Toggle video", "shift+cmd+o"),
            ShortcutPreset("Share screen", "shift+cmd+e"),
            ShortcutPreset("Raise hand", "shift+cmd+k"),
            ShortcutPreset("Accept video call", "shift+cmd+a"),
            ShortcutPreset("Accept audio call", "shift+cmd+s"),
            ShortcutPreset("Decline call", "shift+cmd+d"),
            ShortcutPreset("Leave call", "shift+cmd+h"),
            ShortcutPreset("Background effects", "shift+cmd+p"),
            ShortcutPreset("Search", "cmd+e"),
            ShortcutPreset("Go to", "cmd+g"),
            ShortcutPreset("New chat", "cmd+n"),
        ])

    static let zoom = AppPreset(
        id: "zoom", name: "Zoom", category: "Meetings & chat",
        note: "Enable \"Use global shortcuts\" in Zoom to trigger these from any app.",
        bundleIDs: ["us.zoom.xos"],
                color: 6,
        knobs: [
            KnobPreset("Call",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Toggle mute", "shift+cmd+a"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Pan",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Click", "mouse:left"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
        ],
        shortcuts: [
            ShortcutPreset("Toggle mute", "shift+cmd+a"),
            ShortcutPreset("Toggle video", "shift+cmd+v"),
            ShortcutPreset("Start / stop share", "shift+cmd+s"),
            ShortcutPreset("Pause / resume share", "shift+cmd+t"),
            ShortcutPreset("Raise hand", "alt+y"),
            ShortcutPreset("Show / hide chat", "shift+cmd+h"),
            ShortcutPreset("Show participants", "cmd+u"),
            ShortcutPreset("Record to cloud", "shift+cmd+c"),
            ShortcutPreset("Record locally", "shift+cmd+r"),
            ShortcutPreset("Gallery view", "shift+cmd+w"),
            ShortcutPreset("Enter full screen", "shift+cmd+f"),
            ShortcutPreset("Invite", "cmd+i"),
            ShortcutPreset("End meeting", "cmd+w"),
        ])

    static let meet = AppPreset(
        id: "meet", name: "Google Meet", category: "Meetings & chat",
        note: "Browser shortcuts; Meet must be the focused tab.",
        bundleIDs: ["com.google.Chrome", "com.apple.Safari"],
                color: 4,
        knobs: [
            KnobPreset("Call",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Toggle mute", "cmd+d"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
        ],
        shortcuts: [
            ShortcutPreset("Toggle mute", "cmd+d"),
            ShortcutPreset("Toggle video", "cmd+e"),
            ShortcutPreset("Raise hand", "ctrl+cmd+h"),
            ShortcutPreset("Show captions", "shift+c"),
            ShortcutPreset("Show participants", "ctrl+cmd+p"),
            ShortcutPreset("Show chat", "ctrl+cmd+c"),
        ])

    static let discord = AppPreset(
        id: "discord", name: "Discord", category: "Meetings & chat",
        bundleIDs: ["com.hnc.Discord"],
                color: 6,
        knobs: [
            KnobPreset("Voice",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Toggle mute", "shift+cmd+m"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
        ],
        shortcuts: [
            ShortcutPreset("Toggle mute", "shift+cmd+m"),
            ShortcutPreset("Toggle deafen", "shift+cmd+d"),
            ShortcutPreset("Answer call", "cmd+enter"),
            ShortcutPreset("Decline call", "cmd+backspace"),
            ShortcutPreset("Quick switcher", "cmd+k"),
            ShortcutPreset("Mark server read", "shift+esc"),
            ShortcutPreset("Toggle sidebar", "cmd+b"),
        ])

    // MARK: - Creative

    static let lightroomClassic = AppPreset(
        id: "lightroom", name: "Lightroom Classic", category: "Creative",
        note: "Single-letter shortcuts only fire when the photo area has focus.",
        bundleIDs: ["com.adobe.LightroomClassicCC7"], namePrefix: "Adobe Lightroom Classic",
                color: 5,
        knobs: [
            KnobPreset("Photos",
                       ccw: ShortcutPreset("Previous photo", "left"),
                       press: ShortcutPreset("Flag as pick", "p"),
                       cw: ShortcutPreset("Next photo", "right")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Filmstrip",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Loupe view", "e"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
        ],
        shortcuts: [
            ShortcutPreset("Library module", "g"),
            ShortcutPreset("Develop module", "d"),
            ShortcutPreset("Loupe view", "e"),
            ShortcutPreset("Compare view", "c"),
            ShortcutPreset("Survey view", "n"),
            ShortcutPreset("Flag as pick", "p"),
            ShortcutPreset("Flag as reject", "x"),
            ShortcutPreset("Remove flag", "u"),
            ShortcutPreset("Rating 1", "1"),
            ShortcutPreset("Rating 2", "2"),
            ShortcutPreset("Rating 3", "3"),
            ShortcutPreset("Rating 4", "4"),
            ShortcutPreset("Rating 5", "5"),
            ShortcutPreset("Crop tool", "r"),
            ShortcutPreset("Spot removal", "q"),
            ShortcutPreset("Masking brush", "k"),
            ShortcutPreset("Graduated filter", "m"),
            ShortcutPreset("White balance", "w"),
            ShortcutPreset("Before / after", "backslash"),
            ShortcutPreset("Auto tone", "cmd+u"),
            ShortcutPreset("Copy settings", "shift+cmd+c"),
            ShortcutPreset("Paste settings", "shift+cmd+v"),
            ShortcutPreset("Reset develop", "shift+cmd+r"),
            ShortcutPreset("Export", "shift+cmd+e"),
            ShortcutPreset("Import", "shift+cmd+i"),
            ShortcutPreset("Next photo", "right"),
            ShortcutPreset("Previous photo", "left"),
            ShortcutPreset("Toggle panels", "tab"),
            ShortcutPreset("Lights out", "l"),
            ShortcutPreset("Full screen", "f"),
        ])

    static let photoshop = AppPreset(
        id: "photoshop", name: "Photoshop", category: "Creative",
        bundleIDs: ["com.adobe.Photoshop"], namePrefix: "Adobe Photoshop",
                color: 6,
        knobs: [
            KnobPreset("Brush size",
                       ccw: ShortcutPreset("Smaller", "leftbracket"),
                       press: ShortcutPreset("Brush tool", "b"),
                       cw: ShortcutPreset("Larger", "rightbracket")),
            KnobPreset("Zoom",
                       ccw: ShortcutPreset("Zoom out", "cmd+-"),
                       press: ShortcutPreset("Fit on screen", "cmd+0"),
                       cw: ShortcutPreset("Zoom in", "cmd+=")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
        ],
        shortcuts: [
            ShortcutPreset("Move tool", "v"),
            ShortcutPreset("Marquee", "m"),
            ShortcutPreset("Lasso", "l"),
            ShortcutPreset("Brush", "b"),
            ShortcutPreset("Eraser", "e"),
            ShortcutPreset("Clone stamp", "s"),
            ShortcutPreset("Healing brush", "j"),
            ShortcutPreset("Crop", "c"),
            ShortcutPreset("Zoom", "z"),
            ShortcutPreset("Hand", "h"),
            ShortcutPreset("Step backward", "alt+cmd+z"),
            ShortcutPreset("New layer", "shift+cmd+n"),
            ShortcutPreset("Merge down", "cmd+e"),
            ShortcutPreset("Stamp visible", "shift+alt+cmd+e"),
            ShortcutPreset("Free transform", "cmd+t"),
            ShortcutPreset("Deselect", "cmd+d"),
            ShortcutPreset("Levels", "cmd+l"),
            ShortcutPreset("Curves", "cmd+m"),
            ShortcutPreset("Decrease brush size", "leftbracket"),
            ShortcutPreset("Increase brush size", "rightbracket"),
            ShortcutPreset("Save as", "shift+cmd+s"),
        ])

    static let finalCut = AppPreset(
        id: "finalcut", name: "Final Cut Pro", category: "Creative",
        bundleIDs: ["com.apple.FinalCut"],
                color: 7,
        knobs: [
            KnobPreset("Playhead",
                       ccw: ShortcutPreset("Previous frame", "left"),
                       press: ShortcutPreset("Play / pause", "space"),
                       cw: ShortcutPreset("Next frame", "right")),
            KnobPreset("Timeline zoom",
                       ccw: ShortcutPreset("Zoom out", "cmd+-"),
                       press: ShortcutPreset("Fit timeline", "shift+z"),
                       cw: ShortcutPreset("Zoom in", "cmd+=")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
        ],
        shortcuts: [
            ShortcutPreset("Blade", "b"),
            ShortcutPreset("Select tool", "a"),
            ShortcutPreset("Trim tool", "t"),
            ShortcutPreset("Position tool", "p"),
            ShortcutPreset("Range select", "r"),
            ShortcutPreset("Zoom tool", "z"),
            ShortcutPreset("Play / pause", "space"),
            ShortcutPreset("Mark in", "i"),
            ShortcutPreset("Mark out", "o"),
            ShortcutPreset("Connect clip", "q"),
            ShortcutPreset("Insert clip", "w"),
            ShortcutPreset("Append clip", "e"),
            ShortcutPreset("Overwrite clip", "d"),
            ShortcutPreset("Delete", "backspace"),
            ShortcutPreset("Toggle snapping", "n"),
            ShortcutPreset("Detach audio", "ctrl+shift+s"),
            ShortcutPreset("Render selection", "ctrl+r"),
            ShortcutPreset("Next frame", "right"),
            ShortcutPreset("Previous frame", "left"),
        ])

    static let davinci = AppPreset(
        id: "resolve", name: "DaVinci Resolve", category: "Creative",
        bundleIDs: ["com.blackmagic-design.DaVinciResolve"], namePrefix: "DaVinci Resolve",
                color: 2,
        knobs: [
            KnobPreset("Playhead",
                       ccw: ShortcutPreset("Previous frame", "left"),
                       press: ShortcutPreset("Play / pause", "space"),
                       cw: ShortcutPreset("Next frame", "right")),
            KnobPreset("Timeline zoom",
                       ccw: ShortcutPreset("Zoom out", "cmd+-"),
                       press: ShortcutPreset("Fit timeline", "shift+z"),
                       cw: ShortcutPreset("Zoom in", "cmd+=")),
        ],
        shortcuts: [
            ShortcutPreset("Media page", "shift+2"),
            ShortcutPreset("Cut page", "shift+3"),
            ShortcutPreset("Edit page", "shift+4"),
            ShortcutPreset("Fusion page", "shift+5"),
            ShortcutPreset("Color page", "shift+6"),
            ShortcutPreset("Fairlight page", "shift+7"),
            ShortcutPreset("Deliver page", "shift+8"),
            ShortcutPreset("Blade", "cmd+b"),
            ShortcutPreset("Mark in", "i"),
            ShortcutPreset("Mark out", "o"),
            ShortcutPreset("Play / pause", "space"),
            ShortcutPreset("Add node", "alt+s"),
            ShortcutPreset("Grab still", "cmd+alt+g"),
        ])

    static let figma = AppPreset(
        id: "figma", name: "Figma", category: "Creative",
        bundleIDs: ["com.figma.Desktop"],
                color: 7,
        knobs: [
            KnobPreset("Zoom",
                       ccw: ShortcutPreset("Zoom out", "cmd+-"),
                       press: ShortcutPreset("Zoom to fit", "shift+1"),
                       cw: ShortcutPreset("Zoom in", "cmd+=")),
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Pan",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Click", "mouse:left"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
        ],
        shortcuts: [
            ShortcutPreset("Move tool", "v"),
            ShortcutPreset("Frame tool", "f"),
            ShortcutPreset("Rectangle", "r"),
            ShortcutPreset("Pen", "p"),
            ShortcutPreset("Text", "t"),
            ShortcutPreset("Comment", "c"),
            ShortcutPreset("Group", "cmd+g"),
            ShortcutPreset("Ungroup", "shift+cmd+g"),
            ShortcutPreset("Duplicate", "cmd+d"),
            ShortcutPreset("Toggle UI", "shift+backslash"),
            ShortcutPreset("Zoom to fit", "shift+1"),
            ShortcutPreset("Zoom to selection", "shift+2"),
        ])

    // MARK: - Work

    static let vscode = AppPreset(
        id: "vscode", name: "VS Code", category: "Work",
        bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92"],
                color: 6,
        knobs: [
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Editors",
                       ccw: ShortcutPreset("Previous editor", "shift+cmd+leftbracket"),
                       press: ShortcutPreset("Close editor", "cmd+w"),
                       cw: ShortcutPreset("Next editor", "shift+cmd+rightbracket")),
            KnobPreset("Pan",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Click", "mouse:left"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
        ],
        shortcuts: [
            ShortcutPreset("Command palette", "shift+cmd+p"),
            ShortcutPreset("Quick open", "cmd+p"),
            ShortcutPreset("Toggle terminal", "ctrl+grave"),
            ShortcutPreset("Toggle sidebar", "cmd+b"),
            ShortcutPreset("Toggle comment", "cmd+slash"),
            ShortcutPreset("Format document", "shift+alt+f"),
            ShortcutPreset("Go to definition", "f12"),
            ShortcutPreset("Rename symbol", "f2"),
            ShortcutPreset("Find in files", "shift+cmd+f"),
            ShortcutPreset("Split editor", "cmd+backslash"),
            ShortcutPreset("Save all", "alt+cmd+s"),
            ShortcutPreset("Next problem", "f8"),
        ])

    static let browser = AppPreset(
        id: "browser", name: "Chrome / Safari", category: "Work",
        bundleIDs: ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser"],
                color: 3,
        knobs: [
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Tabs",
                       ccw: ShortcutPreset("Previous tab", "ctrl+shift+tab"),
                       press: ShortcutPreset("New tab", "cmd+t"),
                       cw: ShortcutPreset("Next tab", "ctrl+tab")),
            KnobPreset("Zoom",
                       ccw: ShortcutPreset("Zoom out", "cmd+-"),
                       press: ShortcutPreset("Actual size", "cmd+0"),
                       cw: ShortcutPreset("Zoom in", "cmd+=")),
        ],
        shortcuts: [
            ShortcutPreset("New tab", "cmd+t"),
            ShortcutPreset("Close tab", "cmd+w"),
            ShortcutPreset("Reopen closed tab", "shift+cmd+t"),
            ShortcutPreset("Next tab", "ctrl+tab"),
            ShortcutPreset("Previous tab", "ctrl+shift+tab"),
            ShortcutPreset("Address bar", "cmd+l"),
            ShortcutPreset("Reload", "cmd+r"),
            ShortcutPreset("Hard reload", "shift+cmd+r"),
            ShortcutPreset("Developer tools", "alt+cmd+i"),
            ShortcutPreset("Bookmark page", "cmd+d"),
            ShortcutPreset("Zoom in", "cmd+="),
            ShortcutPreset("Zoom out", "cmd+-"),
            ShortcutPreset("Private window", "shift+cmd+n"),
        ])

    static let excel = AppPreset(
        id: "excel", name: "Excel", category: "Work",
        bundleIDs: ["com.microsoft.Excel"],
                color: 4,
        knobs: [
            KnobPreset("Scroll",
                       ccw: ShortcutPreset("Scroll down", "mouse:wheeldown"),
                       press: ShortcutPreset("Middle click", "mouse:middle"),
                       cw: ShortcutPreset("Scroll up", "mouse:wheelup")),
            KnobPreset("Pan",
                       ccw: ShortcutPreset("Scroll left", "mouse:scrollleft"),
                       press: ShortcutPreset("Click", "mouse:left"),
                       cw: ShortcutPreset("Scroll right", "mouse:scrollright")),
            KnobPreset("History",
                       ccw: ShortcutPreset("Undo", "cmd+z"),
                       press: ShortcutPreset("Edit cell", "f2"),
                       cw: ShortcutPreset("Redo", "shift+cmd+z")),
        ],
        shortcuts: [
            ShortcutPreset("Edit cell", "f2"),
            ShortcutPreset("Autosum", "shift+cmd+t"),
            ShortcutPreset("Insert row", "ctrl+shift+equal"),
            ShortcutPreset("Delete row", "ctrl+minus"),
            ShortcutPreset("Format cells", "cmd+1"),
            ShortcutPreset("Paste special", "ctrl+cmd+v"),
            ShortcutPreset("Toggle filter", "shift+cmd+f"),
            ShortcutPreset("Fill down", "ctrl+d"),
            ShortcutPreset("Fill right", "ctrl+r"),
            ShortcutPreset("Recalculate", "f9"),
        ])

    static let obs = AppPreset(
        id: "obs", name: "OBS Studio", category: "Work",
        note: "OBS has no default shortcuts. Set these in Settings > Hotkeys first.",
        bundleIDs: ["com.obsproject.obs-studio"],
                color: 1,
        knobs: [
            KnobPreset("Scenes",
                       ccw: ShortcutPreset("Scene 1", "f1"),
                       press: ShortcutPreset("Start / stop recording", "f8"),
                       cw: ShortcutPreset("Scene 2", "f2")),
            KnobPreset("Volume",
                       ccw: ShortcutPreset("Volume down", "media:volumedown"),
                       press: ShortcutPreset("Mute", "media:mute"),
                       cw: ShortcutPreset("Volume up", "media:volumeup")),
        ],
        shortcuts: [
            ShortcutPreset("Start / stop stream", "f7"),
            ShortcutPreset("Start / stop recording", "f8"),
            ShortcutPreset("Pause recording", "f9"),
            ShortcutPreset("Mute microphone", "f10"),
            ShortcutPreset("Scene 1", "f1"),
            ShortcutPreset("Scene 2", "f2"),
            ShortcutPreset("Scene 3", "f3"),
            ShortcutPreset("Scene 4", "f4"),
        ])
}

extension Profile {
    /// Builds a profile that maps a preset onto one layer of a pad, filling
    /// keys first and then knob slots, in catalog order.
    public init(filling preset: AppPreset, layer: Int, geometry: Geometry) throws {
        self.init(name: preset.name, geometry: geometry)

        // Keys take the flat shortcut list, in order.
        for (offset, shortcut) in preset.shortcuts.prefix(geometry.keyCount).enumerated() {
            set(try KeyAction.parse(shortcut.action), key: offset + 1, layer: layer,
                label: shortcut.label)
        }

        // Knobs get their own definitions, so a turn is always something worth
        // repeating rather than whatever fell off the end of the key list.
        for (index, knob) in preset.knobs.prefix(geometry.knobCount).enumerated() {
            let base = Wire.knobSlotBase + index * Wire.slotsPerKnob
            for (offset, shortcut) in knob.inOrder.enumerated() {
                set(try KeyAction.parse(shortcut.action), key: base + offset,
                    layer: layer, label: shortcut.label)
            }
        }

        // The pad then shows which app the layer is for without being read.
        setLed(preset.lighting, layer: layer)
        setSource(LayerSource(layer: layer, appID: preset.id, appName: preset.name),
                  layer: layer)
    }
}
