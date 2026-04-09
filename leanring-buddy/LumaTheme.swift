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

    static let background      = Color(hex: "#0A0A0A")
    static let surface         = Color(hex: "#141414")
    static let surfaceElevated = Color(hex: "#1C1C1C")

    // MARK: Borders

    static let border      = Color(hex: "#2A2A2A")
    static let borderFocus = Color(hex: "#FFFFFF")

    // MARK: Text

    static let textPrimary     = Color(hex: "#FFFFFF")
    static let textSecondary   = Color(hex: "#888888")
    static let textPlaceholder = Color(hex: "#444444")

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

    // MARK: Cursor Overlay

    /// Bright blue used for the animated cursor dot and waveform in OverlayWindow.
    static let cursorBlue = Color(hex: "#0A84FF")

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

    /// SF Symbol name for the Luma menu bar icon.
    static let menuBarIconName = "lightbulb.fill"

    // MARK: Typography

    enum Typography {
        static let caption    = Font.system(size: 11, weight: .regular)
        static let body       = Font.system(size: 13, weight: .regular)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let headline   = Font.system(size: 15, weight: .semibold)
        static let title      = Font.system(size: 20, weight: .bold)
        static let largeTitle = Font.system(size: 28, weight: .bold)
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
