import SwiftUI

/// Design tokens.
///
/// The palette comes from the object itself: PBT-cream keycaps, a brass knob
/// ring, graphite housing. One accent — brass — carries every selected state,
/// so nothing else has to compete with it.
enum Theme {

    // MARK: - Palette

    /// The single accent. Selection, focus and "this is live" all use it.
    static let brass = Color(light: Color(red: 0.788, green: 0.549, blue: 0.086),
                             dark:  Color(red: 1.000, green: 0.714, blue: 0.153))

    /// Keycap top surface — the part a legend is printed on.
    static let capFace = Color(light: Color(red: 0.953, green: 0.945, blue: 0.925),
                               dark:  Color(red: 0.208, green: 0.224, blue: 0.251))

    /// The moulding below the face, which gives the cap its depth.
    static let capSkirt = Color(light: Color(red: 0.812, green: 0.792, blue: 0.761),
                                dark:  Color(red: 0.129, green: 0.141, blue: 0.161))

    /// Legend colour on a cap.
    static let legend = Color(light: Color(red: 0.153, green: 0.157, blue: 0.169),
                              dark:  Color(red: 0.902, green: 0.898, blue: 0.882))

    /// The housing the caps sit in.
    static let housing = Color(light: Color(red: 0.898, green: 0.890, blue: 0.875),
                               dark:  Color(red: 0.086, green: 0.094, blue: 0.114))

    // MARK: - Metrics

    static let capRadius: CGFloat = 9
    static let capSkirtDepth: CGFloat = 3
    static let capSpacing: CGFloat = 9
    static let dialSize: CGFloat = 118
}

extension Color {
    /// Picks between two colours by appearance, so every token is defined once
    /// for light and once for dark rather than guessed from opacity.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

/// A ring segment, used for the two rotation halves of a knob.
struct AnnularSector: Shape {
    /// Degrees, measured clockwise from straight up.
    var startAngle: Double
    var endAngle: Double
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = max(outer - thickness, 0)

        // SwiftUI angles run clockwise from 3 o'clock; shift so 0 is 12 o'clock.
        let start = Angle(degrees: startAngle - 90)
        let end = Angle(degrees: endAngle - 90)

        var path = Path()
        path.addArc(center: center, radius: outer,
                    startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner,
                    startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
