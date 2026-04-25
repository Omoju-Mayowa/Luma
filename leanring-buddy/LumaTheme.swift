//
//  LumaTheme.swift
//  leanring-buddy
//
//  Luma dark design system. All UI tokens live here — colors, spacing,
//  corner radii, typography, and animation timing — so every view
//  references a single source of truth.
//

import SwiftUI

// MARK: - Color Hex Initializer

extension Color {
    /// Convenience initializer that accepts a hex string in `#RGB`, `#RRGGBB`,
    /// or `#AARRGGBB` format (the leading `#` is optional).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - LumaTheme

struct LumaTheme {

    // MARK: Backgrounds

    static let background      = Color(hex: "#0A0A0F")
    static let surface         = Color(hex: "#141414")
    static let surfaceElevated = Color(hex: "#1C1C1C")

    // MARK: Borders

    static let border      = Color(hex: "#3A3A3A")
    static let borderFocus = Color(hex: "#FFFFFF")

    // MARK: Text

    static let textPrimary     = Color(hex: "#FFFFFF")
    static let textSecondary   = Color(hex: "#B0B0B0")
    static let textPlaceholder = Color(hex: "#656565")

    // MARK: Accent

    /// Primary accent — white on dark background.
    static let accent           = Color(hex: "#FFFFFF")
    /// Foreground drawn on top of accent-colored buttons (e.g. black text on white button).
    static let accentForeground = Color(hex: "#000000")

    // MARK: Semantic

    static let destructive = Color(hex: "#FF3B30")
    static let success     = Color(hex: "#34C759")
    static let warning     = Color(hex: "#FF9500")

    // MARK: Input

    static let inputBackground = Color(hex: "#1C1C1C")
    static let inputBorder     = Color(hex: "#2A2A2A")
    static let inputText       = Color(hex: "#FFFFFF")

    // MARK: - Companion Appearance
    //
    // ┌─────────────────────────────────────────────────────────────────────┐
    // │  Change these two values to restyle the floating companion.         │
    // │  Everything — dot, waveform, glow, spinner — updates automatically. │
    // └─────────────────────────────────────────────────────────────────────┘

    /// Color of the floating companion, waveform bars, and glow.
    /// Change the hex value to any colour you like.
    static let companionColor = Color(hex: "#0A84FF") // #0A84FF — Old blue color

    // Shape options — set companionShape and companionMorphTargetShape to any of these:
    //
    //   .circle   — a perfect round dot. Clean, minimal.
    //               Good idle shape when you want something subtle and non-directional.
    //
    //   .capsule  — a pill / stadium shape. Taller than it is wide when the companion
    //               is small (16×16 frame), so it looks like a vertical oval/pill.
    //               Because the frame is square, width == height, making it identical
    //               to a circle at that size. To get a visible pill you must increase
    //               the companion frame size in OverlayWindow.swift (the .frame(width:16,
    //               height:16) line) — e.g. width:24, height:14 for a wide pill, or
    //               width:10, height:20 for a tall pill. The capsule fills whatever
    //               frame it is given and rounds the two shorter ends automatically.
    //
    //   .triangle — equilateral arrow that rotates to face its direction of travel.
    //               Classic cursor look. Best as the morph target so it snaps into
    //               a pointer when the companion flies to a UI element.

    /// Width of the companion shape in points.
    /// For a capsule pill, make width and height different (e.g. width:24, height:14).
    /// For circle/triangle, width and height should be equal.
    static let companionWidth:  CGFloat = 14
    static let companionHeight: CGFloat = 14

    /// Shape of the companion while idle / following the cursor.
    static let companionShape: CompanionShape = .capsule

    // MARK: Companion Morph
    //
    // When the companion navigates to a UI element it morphs into companionMorphTargetShape
    // then morphs back when it returns. Tune the spring feel here.
    //
    // ┌────────────────────────────────────────────────────────────────────────┐
    // │ Change these values to tune how the morph feels.                       │
    // └────────────────────────────────────────────────────────────────────────┘

    /// Shape the companion morphs INTO when navigating to or pointing at a UI element.
    /// .triangle gives the classic pointer look. Can be any CompanionShape.
    static let companionMorphTargetShape: CompanionShape = .triangle

    /// Size of the companion in its morph target (pointing) state.
    /// Interpolated from companionWidth/Height as the morph progresses.
    /// Set equal to companionWidth/Height to keep the size constant during morph.
    static let companionMorphTargetWidth:  CGFloat = 32
    static let companionMorphTargetHeight: CGFloat = 32

    // MARK: Companion Corner Radius
    //
    // Controls how rounded the corners of the companion shape are.
    // Only applies to shapes with corners (.triangle, polygon).
    // .circle and .capsule are already smooth and ignore this value.
    //
    // Good starting values:
    //   .triangle idle,  14pt frame  →  0 (sharp) or 2–4 (soft)
    //   .triangle morph, 32pt frame  →  4–6 (nicely rounded corners)
    //   0 = perfectly sharp corners (fastest, no extra computation)

    /// Corner radius in points for the companion in its idle state.
    /// Only affects .triangle and polygon shapes; .circle/.capsule are already smooth.
    static let companionCornerRadius: CGFloat = 0

    /// Corner radius in points for the companion when it morphs to its target shape.
    /// For the default .triangle morph target at 32pt, 4–6 gives visibly rounded corners.
    static let companionMorphTargetCornerRadius: CGFloat = 6

    // MARK: Companion Morph Target Color

    /// Fill color of the companion after it has fully morphed into its target shape.
    /// Cross-fades with companionColor as the morph progresses.
    /// Set to companionColor to keep a constant fill throughout the morph.
    static let companionMorphTargetColor: Color = Color(hex: "#0A84FF") // changes to blue color on morph

    // MARK: Companion Border (idle state)

    /// Stroke color drawn around the companion in its idle / cursor-following state.
    /// Set width to 0 to disable the border entirely.
    static let companionBorderColor: Color  = .white.opacity(0.5)
    static let companionBorderWidth: CGFloat = 1.0

    // MARK: Companion Border (morph target / pointing state)

    /// Stroke color drawn around the companion after morphing into the target shape.
    /// Cross-fades with the idle border as the morph progresses.
    static let companionMorphTargetBorderColor: Color  = .white.opacity(0.25)
    static let companionMorphTargetBorderWidth: CGFloat = 1.5

    /// Spring response for the morph animation. Lower = faster / snappier.
    static let companionMorphSpringResponse: Double = 0.72
    /// Spring damping for the morph animation. Lower = more bounce. 1.0 = no bounce.
    static let companionMorphSpringDamping: Double = 0.36
    /// Number of outline sample points used to interpolate between shapes.
    /// Higher = smoother morph edge. 24–48 is a good range; rarely needs changing.
    static let companionMorphPointCount: Int = 36

    // Internal alias — existing code uses cursorBlue; this keeps it working
    // without needing to update every call site. Change companionColor above.
    static let cursorBlue = companionColor

    // MARK: Spacing

    static let spacingXS:  CGFloat = 4
    static let spacingSM:  CGFloat = 8
    static let spacingMD:  CGFloat = 16
    static let spacingLG:  CGFloat = 24
    static let spacingXL:  CGFloat = 32
    static let spacingXXL: CGFloat = 40

    // MARK: Padding
    // Use these for view padding (insets), not for spacing between elements.
    // paddingMD (12) ≠ spacingMD (16) — intentional: inputs use tighter insets.

    static let paddingXS:      CGFloat = 4
    static let paddingSM:      CGFloat = 8
    static let paddingMD:      CGFloat = 12
    static let paddingLG:      CGFloat = 16
    static let paddingXL:      CGFloat = 20
    static let paddingXXL:     CGFloat = 24
    static let sectionSpacing: CGFloat = 32

    // MARK: Corner Radius

    static let radiusSM:   CGFloat = 6
    static let radiusMD:   CGFloat = 10
    static let radiusLG:   CGFloat = 16
    static let radiusXL:   CGFloat = 20
    static let radiusFull: CGFloat = 999

    // MARK: Animation Durations (seconds)

    static let animationFast:   Double = 0.15
    static let animationNormal: Double = 0.25
    static let animationSlow:   Double = 0.4

    // MARK: Menu Bar
    //
    // ┌──────────────────────────────────────────────────────────────────────┐
    // │  Change menuBarIconName to any SF Symbol to update the menu bar icon.│
    // │  Browse symbols at: https://developer.apple.com/sf-symbols/          │
    // └──────────────────────────────────────────────────────────────────────┘

    /// SF Symbol name for the Luma menu bar icon. e.g. "sparkles", "brain", "eye.fill"
    static let menuBarIconName = "lightbulb.fill"

    // MARK: Typography

    enum Typography {
        // Body text: SF Pro Text (system default design)
        static let caption    = Font.system(size: 11, weight: .regular, design: .default)
        static let body       = Font.system(size: 13, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
        // Headers: SF Pro Display (rounded design for distinction at larger sizes)
        static let headline   = Font.system(size: 15, weight: .semibold, design: .default)
        static let title      = Font.system(size: 20, weight: .bold, design: .default)
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .default)
    }

    // MARK: - Backward Compatibility Shims
    //
    // Views that still use the old nested-enum token paths (LumaTheme.Colors.*,
    // LumaTheme.Spacing.*, etc.) continue to compile via these computed-property
    // aliases. Migrate call-sites to the flat names above over time, then delete
    // these shims.

    enum Colors {
        static var background:       Color { LumaTheme.background }
        static var surface:          Color { LumaTheme.surface }
        static var surfaceElevated:  Color { LumaTheme.surfaceElevated }
        static var primaryText:      Color { LumaTheme.textPrimary }
        static var secondaryText:    Color { LumaTheme.textSecondary }
        static var tertiaryText:     Color { LumaTheme.textPlaceholder }
        static var accent:           Color { LumaTheme.accent }
        static var accentForeground: Color { LumaTheme.accentForeground }
        static var error:            Color { LumaTheme.destructive }
        static var success:          Color { LumaTheme.success }
        static var warning:          Color { LumaTheme.warning }
        static var overlayCursorBlue: Color { LumaTheme.cursorBlue }
        static var panelBackground:  Color { LumaTheme.surface }
        static var borderSubtle:     Color { LumaTheme.border }
        static var textPrimary:      Color { LumaTheme.textPrimary }
        static var textSecondary:    Color { LumaTheme.textSecondary }
        static var textTertiary:     Color { LumaTheme.textPlaceholder }
        static var textOnAccent:     Color { LumaTheme.accentForeground }
        static var inputBackground:  Color { LumaTheme.inputBackground }
        static var blue400:          Color { LumaTheme.cursorBlue }
        static var buttonHover:      Color { LumaTheme.surfaceElevated }
        static var iconTint:         Color { LumaTheme.textSecondary }
        static var panelBorder:      Color { LumaTheme.border }
    }

    enum CornerRadius {
        static var small:      CGFloat { LumaTheme.radiusSM }
        static var medium:     CGFloat { LumaTheme.radiusMD }
        static var large:      CGFloat { LumaTheme.radiusLG }
        static var extraLarge: CGFloat { LumaTheme.radiusXL }
        static var panel:      CGFloat { LumaTheme.radiusLG }
        static var bubble:     CGFloat { LumaTheme.radiusLG }
    }

    enum Spacing {
        static var xs:  CGFloat { LumaTheme.spacingXS }
        static var sm:  CGFloat { LumaTheme.spacingSM }
        static var md:  CGFloat { LumaTheme.spacingMD }
        static var lg:  CGFloat { LumaTheme.spacingLG }
        static var xl:  CGFloat { LumaTheme.spacingXL }
        static var xxl: CGFloat { LumaTheme.spacingXXL }
    }

    enum Animation {
        static var fast:     Double { LumaTheme.animationFast }
        static var standard: Double { LumaTheme.animationNormal }
        static var slow:     Double { LumaTheme.animationSlow }
    }

    enum MenuBar {
        static var iconName: String { LumaTheme.menuBarIconName }
    }
}

// MARK: - Companion Shape

/// Defines the shape of the floating companion cursor.
/// Set LumaTheme.companionShape to one of these values in LumaTheme.swift.
enum CompanionShape {
    /// Default arrow-like cursor — rotates to face its direction of travel.
    case triangle
    /// Simple round dot — ignores rotation during flight.
    case circle
    /// Horizontal pill — ignores rotation during flight.
    case capsule

    /// Returns the shape as an AnyShape so it can be used with .fill() and
    /// other Shape modifiers at the call site without knowing the concrete type.
    var asAnyShape: AnyShape {
        switch self {
        case .triangle: return AnyShape(CompanionTriangle())
        case .circle:   return AnyShape(Circle())
        case .capsule:  return AnyShape(Capsule())
        }
    }
}

/// Equilateral triangle used for the default companion cursor.
/// Tip points upward at 0° — OverlayWindow rotates it to a cursor-like -35°.
struct CompanionTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size   = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0
        path.move(to:     CGPoint(x: rect.midX,           y: rect.midY - height / 1.5))
        path.addLine(to:  CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        path.addLine(to:  CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}

// MARK: - Morphing Companion Shape

/// A SwiftUI Shape that smoothly morphs between LumaTheme.companionShape and a
/// triangle by sampling N evenly-spaced points along each shape's perimeter and
/// linearly interpolating between corresponding points.
///
/// progress = 0  →  LumaTheme.companionShape (idle / following cursor)
/// progress = 1  →  triangle (navigating to / pointing at a UI element)
///
/// Conforms to Animatable via animatableData so SwiftUI drives each frame of the
/// morph when progress is animated with a spring.
struct MorphingCompanionShape: Shape {

    /// 0 = companion's idle shape, 1 = triangle pointer.
    /// Animate this value with a spring to produce the morph.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let n = LumaTheme.companionMorphPointCount
        let fromPoints = Self.sampleShapePoints(LumaTheme.companionShape,           in: rect, count: n,
                                                cornerRadius: LumaTheme.companionCornerRadius)
        let toPoints   = Self.sampleShapePoints(LumaTheme.companionMorphTargetShape, in: rect, count: n,
                                                cornerRadius: LumaTheme.companionMorphTargetCornerRadius)

        // Linearly interpolate each corresponding pair of outline points.
        // Because both point arrays have the same count and start at the same
        // "top" anchor, the morph transitions cleanly without twisting.
        let interpolated = zip(fromPoints, toPoints).map { (from, to) -> CGPoint in
            CGPoint(
                x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress
            )
        }

        var path = Path()
        guard let first = interpolated.first else { return path }
        path.move(to: first)
        interpolated.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    // MARK: Shape Sampling

    private static func sampleShapePoints(_ shape: CompanionShape, in rect: CGRect, count: Int,
                                          cornerRadius: CGFloat = 0) -> [CGPoint] {
        switch shape {
        case .triangle: return sampleTrianglePoints(in: rect, count: count, cornerRadius: cornerRadius)
        case .circle:   return sampleCirclePoints(in: rect, count: count)
        case .capsule:  return sampleCapsulePoints(in: rect, count: count)
        }
    }

    /// N points evenly distributed along the triangle perimeter, starting near the top vertex.
    /// When cornerRadius > 0, the three corners are replaced with smooth arcs of that radius.
    /// The triangle vertices match CompanionTriangle exactly so the two shapes are consistent.
    static func sampleTrianglePoints(in rect: CGRect, count: Int, cornerRadius: CGFloat = 0) -> [CGPoint] {
        let size   = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0
        let top         = CGPoint(x: rect.midX,            y: rect.midY - height / 1.5)
        let bottomRight = CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3)
        let bottomLeft  = CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3)

        guard cornerRadius > 0 else {
            // No rounding — sample the sharp triangle perimeter directly.
            return samplePolygonPerimeter([top, bottomRight, bottomLeft], totalCount: count)
        }

        // Build a rounded triangle CGPath using tangent arcs at each corner, then sample
        // N evenly-spaced points along that path's perimeter.
        let vertices: [CGPoint] = [top, bottomRight, bottomLeft]
        let vertexCount = vertices.count

        // Clamp radius: the equilateral triangle inradius is height/3.
        // Exceeding ~85% of the inradius causes corners to collide.
        let inradius = height / 3.0
        let clampedRadius = min(Double(cornerRadius), inradius * 0.85)

        let cgPath = CGMutablePath()
        for i in 0..<vertexCount {
            let prevVertex = vertices[(i + vertexCount - 1) % vertexCount]
            let currVertex = vertices[i]
            let nextVertex = vertices[(i + 1) % vertexCount]

            // Unit vector pointing from the previous vertex toward the current (incoming direction).
            let dx = currVertex.x - prevVertex.x
            let dy = currVertex.y - prevVertex.y
            let edgeLength = sqrt(dx * dx + dy * dy)
            let inDirX = edgeLength > 0 ? dx / edgeLength : 0
            let inDirY = edgeLength > 0 ? dy / edgeLength : 0

            // Move to the tangent start point: r units before the corner along the incoming edge.
            // This is where the arc will begin.
            let tangentStartPoint = CGPoint(x: currVertex.x - inDirX * clampedRadius,
                                            y: currVertex.y - inDirY * clampedRadius)

            if i == 0 {
                cgPath.move(to: tangentStartPoint)
            } else {
                // Draw the straight portion of the previous edge up to this arc's start.
                cgPath.addLine(to: tangentStartPoint)
            }

            // addArc(tangent1End:tangent2End:radius:) draws a circular arc that is tangent to
            // both the incoming edge (currentPoint → currVertex) and the outgoing edge
            // (currVertex → nextVertex). The result is a smooth rounded corner.
            cgPath.addArc(tangent1End: currVertex, tangent2End: nextVertex, radius: clampedRadius)
        }
        // Close back to the starting tangent point, completing the final straight edge.
        cgPath.closeSubpath()

        return sampleCGPathPoints(cgPath, count: count)
    }

    /// N points evenly distributed around the circle, starting at the top (12 o'clock).
    private static func sampleCirclePoints(in rect: CGRect, count: Int) -> [CGPoint] {
        let cx = rect.midX
        let cy = rect.midY
        let radius = min(rect.width, rect.height) / 2.0
        return (0..<count).map { i in
            // −π/2 starts at the top and winds clockwise, matching the triangle winding
            let angle = 2.0 * .pi * Double(i) / Double(count) - .pi / 2.0
            return CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
        }
    }

    /// N points evenly distributed around the capsule perimeter, starting at the top center.
    private static func sampleCapsulePoints(in rect: CGRect, count: Int) -> [CGPoint] {
        let w = rect.width
        let h = rect.height
        let radius = min(w, h) / 2.0
        let isHorizontal = w >= h
        let straightLength = max(w, h) - 2.0 * radius
        // Total perimeter = two straight edges + full circle circumference
        let totalPerimeter = 2.0 * straightLength + 2.0 * .pi * radius

        return (0..<count).map { i in
            let distance = totalPerimeter * Double(i) / Double(count)
            return capsulePoint(
                atDistance: distance,
                isHorizontal: isHorizontal,
                straightLength: straightLength,
                radius: radius,
                midX: Double(rect.midX),
                midY: Double(rect.midY)
            )
        }
    }

    /// Returns the outline point at `distance` along a capsule's perimeter.
    /// For a vertical capsule the traversal starts at the top-center and winds clockwise.
    /// For a horizontal capsule it starts at the top-left of the top straight edge.
    private static func capsulePoint(
        atDistance distance: Double,
        isHorizontal: Bool,
        straightLength: Double,
        radius: Double,
        midX: Double,
        midY: Double
    ) -> CGPoint {
        let half = straightLength / 2.0

        if isHorizontal {
            // Segments (clockwise from top-left of top edge):
            //   top straight → right semicap → bottom straight → left semicap
            let seg1End = straightLength
            let seg2End = seg1End + .pi * radius
            let seg3End = seg2End + straightLength

            if distance < seg1End {
                return CGPoint(x: midX - half + distance, y: midY - radius)
            } else if distance < seg2End {
                let angle = (distance - seg1End) / radius - .pi / 2.0
                return CGPoint(x: midX + half + radius * cos(angle), y: midY + radius * sin(angle))
            } else if distance < seg3End {
                return CGPoint(x: midX + half - (distance - seg2End), y: midY + radius)
            } else {
                let angle = (distance - seg3End) / radius + .pi / 2.0
                return CGPoint(x: midX - half + radius * cos(angle), y: midY + radius * sin(angle))
            }
        } else {
            // Vertical capsule — segments (clockwise from top-center):
            //   top semicap → right straight → bottom semicap → left straight
            let seg1End = .pi * radius
            let seg2End = seg1End + straightLength
            let seg3End = seg2End + .pi * radius

            if distance < seg1End {
                let angle = distance / radius - .pi / 2.0
                return CGPoint(x: midX + radius * cos(angle), y: midY - half + radius * sin(angle))
            } else if distance < seg2End {
                return CGPoint(x: midX + radius, y: midY - half + (distance - seg1End))
            } else if distance < seg3End {
                let angle = (distance - seg2End) / radius + .pi / 2.0
                return CGPoint(x: midX + radius * cos(angle), y: midY + half + radius * sin(angle))
            } else {
                return CGPoint(x: midX - radius, y: midY + half - (distance - seg3End))
            }
        }
    }

    /// Samples `count` evenly-spaced points along the perimeter of an arbitrary CGPath.
    ///
    /// CGPath arcs (produced by addArc) are stored internally as cubic bezier curves.
    /// This function decomposes every path element into short line sub-segments, then
    /// walks those segments to place points at uniform perimeter intervals.
    private static func sampleCGPathPoints(_ cgPath: CGPath, count: Int) -> [CGPoint] {
        // Collect path as (start, end) line segments — curves are subdivided for accuracy.
        var lineSegments: [(start: CGPoint, end: CGPoint)] = []
        var currentPoint = CGPoint.zero
        var pathStartPoint = CGPoint.zero

        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {

            case .moveToPoint:
                currentPoint   = element.points[0]
                pathStartPoint = currentPoint

            case .addLineToPoint:
                let endPoint = element.points[0]
                lineSegments.append((start: currentPoint, end: endPoint))
                currentPoint = endPoint

            case .addQuadCurveToPoint:
                // Subdivide the quadratic bezier into 8 line segments for even sampling.
                let controlPoint = element.points[0]
                let endPoint     = element.points[1]
                let subdivisionCount = 8
                for j in 0..<subdivisionCount {
                    let t0 = Double(j)     / Double(subdivisionCount)
                    let t1 = Double(j + 1) / Double(subdivisionCount)
                    let segStart = quadraticBezierPoint(from: currentPoint, control: controlPoint,
                                                        to: endPoint, t: t0)
                    let segEnd   = quadraticBezierPoint(from: currentPoint, control: controlPoint,
                                                        to: endPoint, t: t1)
                    lineSegments.append((start: segStart, end: segEnd))
                }
                currentPoint = endPoint

            case .addCurveToPoint:
                // Subdivide the cubic bezier (arcs are stored as cubics) into 8 line segments.
                let cp1      = element.points[0]
                let cp2      = element.points[1]
                let endPoint = element.points[2]
                let subdivisionCount = 8
                for j in 0..<subdivisionCount {
                    let t0 = Double(j)     / Double(subdivisionCount)
                    let t1 = Double(j + 1) / Double(subdivisionCount)
                    let segStart = cubicBezierPoint(from: currentPoint, cp1: cp1, cp2: cp2,
                                                    to: endPoint, t: t0)
                    let segEnd   = cubicBezierPoint(from: currentPoint, cp1: cp1, cp2: cp2,
                                                    to: endPoint, t: t1)
                    lineSegments.append((start: segStart, end: segEnd))
                }
                currentPoint = endPoint

            case .closeSubpath:
                // Draw the final edge back to the path's starting point.
                if currentPoint != pathStartPoint {
                    lineSegments.append((start: currentPoint, end: pathStartPoint))
                }
                currentPoint = pathStartPoint

            default:
                break
            }
        }

        let segmentLengths = lineSegments.map { hypot($0.end.x - $0.start.x, $0.end.y - $0.start.y) }
        let totalPerimeter = segmentLengths.reduce(0.0, +)
        guard totalPerimeter > 0 else { return Array(repeating: .zero, count: count) }

        return (0..<count).map { sampleIndex in
            var remainingDistance = totalPerimeter * Double(sampleIndex) / Double(count)
            for (segIndex, segment) in lineSegments.enumerated() {
                let segmentLength = segmentLengths[segIndex]
                if remainingDistance <= segmentLength || segIndex == lineSegments.count - 1 {
                    let t = segmentLength > 0 ? min(1.0, remainingDistance / segmentLength) : 0.0
                    return CGPoint(
                        x: segment.start.x + (segment.end.x - segment.start.x) * t,
                        y: segment.start.y + (segment.end.y - segment.start.y) * t
                    )
                }
                remainingDistance -= segmentLength
            }
            return lineSegments.last?.end ?? .zero
        }
    }

    /// Evaluates a quadratic bezier curve at parameter t ∈ [0, 1].
    private static func quadraticBezierPoint(from p0: CGPoint, control p1: CGPoint,
                                             to p2: CGPoint, t: Double) -> CGPoint {
        let u = 1.0 - t
        return CGPoint(
            x: u * u * p0.x + 2.0 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2.0 * u * t * p1.y + t * t * p2.y
        )
    }

    /// Evaluates a cubic bezier curve at parameter t ∈ [0, 1].
    private static func cubicBezierPoint(from p0: CGPoint, cp1 p1: CGPoint,
                                         cp2 p2: CGPoint, to p3: CGPoint, t: Double) -> CGPoint {
        let u   = 1.0 - t
        let uu  = u * u
        let uuu = uu * u
        let tt  = t * t
        let ttt = tt * t
        return CGPoint(
            x: uuu * p0.x + 3.0 * uu * t * p1.x + 3.0 * u * tt * p2.x + ttt * p3.x,
            y: uuu * p0.y + 3.0 * uu * t * p1.y + 3.0 * u * tt * p2.y + ttt * p3.y
        )
    }

    /// Distributes `totalCount` points evenly along the perimeter of a closed polygon.
    /// The first point is placed at vertex[0] and the rest follow the edge order.
    private static func samplePolygonPerimeter(_ vertices: [CGPoint], totalCount: Int) -> [CGPoint] {
        let vertexCount = vertices.count
        var edgeLengths = [Double]()
        var totalPerimeter = 0.0
        for i in 0..<vertexCount {
            let next = (i + 1) % vertexCount
            let length = hypot(
                Double(vertices[next].x - vertices[i].x),
                Double(vertices[next].y - vertices[i].y)
            )
            edgeLengths.append(length)
            totalPerimeter += length
        }

        return (0..<totalCount).map { sampleIndex in
            var remaining = totalPerimeter * Double(sampleIndex) / Double(totalCount)
            var edgeIndex = 0
            while edgeIndex < vertexCount - 1 && remaining > edgeLengths[edgeIndex] {
                remaining -= edgeLengths[edgeIndex]
                edgeIndex += 1
            }
            let fraction = edgeLengths[edgeIndex] > 0 ? remaining / edgeLengths[edgeIndex] : 0.0
            let a = vertices[edgeIndex]
            let b = vertices[(edgeIndex + 1) % vertexCount]
            return CGPoint(
                x: a.x + (b.x - a.x) * CGFloat(fraction),
                y: a.y + (b.y - a.y) * CGFloat(fraction)
            )
        }
    }
}

// MARK: - Noise Texture View

/// A subtle procedural grain texture overlay generated via Core Image.
/// Renders at low opacity to add visual depth to dark surfaces.
struct NoiseTextureView: View {
    var opacity: Double = 0.03

    var body: some View {
        GeometryReader { geometry in
            if let noiseImage = Self.generateNoiseImage(
                width: Int(geometry.size.width),
                height: Int(geometry.size.height)
            ) {
                Image(nsImage: noiseImage)
                    .resizable()
                    .opacity(opacity)
                    .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
    }

    /// Generates a grain noise pattern using CIRandomGenerator + CIColorMatrix.
    private static func generateNoiseImage(width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0 else { return nil }

        let context = CIContext()
        guard let noiseFilter = CIFilter(name: "CIRandomGenerator") else { return nil }
        guard let noiseOutput = noiseFilter.outputImage else { return nil }

        // Reduce the noise to a subtle monochrome grain
        guard let monoFilter = CIFilter(name: "CIColorMatrix") else { return nil }
        monoFilter.setValue(noiseOutput, forKey: kCIInputImageKey)
        monoFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        monoFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        monoFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        monoFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.1), forKey: "inputAVector")
        monoFilter.setValue(CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0), forKey: "inputBiasVector")

        guard let monoOutput = monoFilter.outputImage else { return nil }

        let croppedOutput = monoOutput.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.createCGImage(croppedOutput, from: croppedOutput.extent) else { return nil }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        return nsImage
    }
}

// MARK: - View Cursor Extension

extension View {
    /// Sets the cursor to a pointing hand when the user hovers over this view.
    /// All interactive elements (buttons, links) should call this to communicate clickability.
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Button Glow Hover Modifier

/// Adds a subtle accent-colored glow behind a button when hovered.
struct ButtonGlowHoverModifier: ViewModifier {
    var glowColor: Color = LumaTheme.accent
    var glowRadius: CGFloat = 8
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: LumaTheme.radiusSM)
                    .fill(glowColor.opacity(isHovering ? 0.12 : 0))
                    .blur(radius: glowRadius)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

extension View {
    /// Applies a subtle glow on hover with a pointing hand cursor.
    func glowOnHover(color: Color = LumaTheme.accent, radius: CGFloat = 8) -> some View {
        modifier(ButtonGlowHoverModifier(glowColor: color, glowRadius: radius))
    }
}
