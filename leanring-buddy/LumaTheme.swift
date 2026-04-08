//
//  LumaTheme.swift
//  leanring-buddy
//
//  Light theme design system for Luma. All UI tokens (colors, corner radii,
//  typography, spacing, animation) live here so every view references a single
//  source of truth.
//

import SwiftUI

// MARK: - Color Hex Initializer

extension Color {
    /// Convenience initialiser that accepts a hex string in `#RGB`, `#RRGGBB`,
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

enum LumaTheme {

    // MARK: Colors

    enum Colors {
        // Backgrounds
        static let background      = Color.white
        static let surface         = Color(hex: "#F5F5F7")
        static let surfaceElevated = Color(hex: "#EBEBEB")

        // Text
        static let primaryText   = Color(hex: "#1D1D1F")
        static let secondaryText = Color(hex: "#6E6E73")
        static let tertiaryText  = Color(hex: "#AEAEB2")

        // Accent
        static let accent            = Color.black
        static let accentForeground  = Color.white

        // State colors
        static let success = Color(hex: "#34C759")
        static let warning = Color(hex: "#FF9F0A")
        static let error   = Color(hex: "#FF3B30")

        // Blue used for the cursor overlay and waveform
        static let blue400 = Color(hex: "#0A84FF")

        // Overlay (for dark panels like CompanionBubbleWindow)
        static let overlayBackground = Color.black.opacity(0.88)
        static let overlayText       = Color.white

        // The bright blue dot / cursor used in OverlayWindow
        static let overlayCursorBlue = Color(hex: "#0A84FF")

        // -----------------------------------------------------------------------
        // Legacy DS compatibility aliases
        // These map the old DS.Colors.* names used by CompanionPanelView and
        // OverlayWindow so those views compile without any changes until they are
        // fully migrated to LumaTheme naming.
        // -----------------------------------------------------------------------

        // Panel chrome (intentionally dark — these views are dark-themed panels)
        static let panelBackground = Color(hex: "#1C1C1E")
        static let panelBorder     = Color.white.opacity(0.08)
        static let inputBackground = Color(hex: "#2C2C2E")
        static let buttonHover     = Color.white.opacity(0.08)
        static let iconTint        = Color(hex: "#AEAEB2")

        // Text aliases (old DS names → LumaTheme equivalents)
        static let textPrimary   = Color(hex: "#E5E5EA")  // light text on dark panel
        static let textSecondary = Color(hex: "#AEAEB2")
        static let textTertiary  = Color(hex: "#636366")
        static let textOnAccent  = Color.white             // text drawn on accent-coloured buttons

        // Border alias used by CompanionPanelView
        static let borderSubtle = Color.white.opacity(0.08)
    }

    // MARK: Corner Radii

    enum CornerRadius {
        static let small:      CGFloat = 6
        static let medium:     CGFloat = 10
        static let large:      CGFloat = 14
        static let extraLarge: CGFloat = 20
        static let panel:      CGFloat = 16
        static let bubble:     CGFloat = 16
    }

    // MARK: Typography

    enum Typography {
        static let caption     = Font.system(size: 11, weight: .regular)
        static let body        = Font.system(size: 13, weight: .regular)
        static let bodyMedium  = Font.system(size: 13, weight: .medium)
        static let headline    = Font.system(size: 15, weight: .semibold)
        static let title       = Font.system(size: 20, weight: .bold)
        static let largeTitle  = Font.system(size: 28, weight: .bold)
    }

    // MARK: Spacing

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Animation durations (seconds)

    enum Animation {
        static let fast:     Double = 0.15
        static let standard: Double = 0.25
        static let slow:     Double = 0.4
    }

    // MARK: Menu Bar

    enum MenuBar {
        /// SF Symbol name for the Luma menu bar icon
        static let iconName = "lightbulb.fill"
    }
}

// MARK: - DS Compatibility Alias
// Temporary typealias so all existing views that reference DS.Colors.*,
// DS.CornerRadius.* etc. continue to compile while they are gradually
// migrated to use LumaTheme directly. Remove once migration is complete.
typealias DS = LumaTheme
