//
//  AgentShapeView.swift
//  leanring-buddy
//
//  SwiftUI view that renders an agent's shape inside a rounded rect button
//  with agent-colored glow and tinted border. Supports all AgentShape cases.
//

import SwiftUI

/// Renders an agent shape (square, rhombus, triangle, hexagon, circle)
/// inside a dark rounded rect button with a colored glow.
struct AgentShapeView: View {
    let shape: AgentShape
    let color: Color
    let size: CGFloat  // Total button size (e.g. 56pt)

    var body: some View {
        ZStack {
            // Background: dark translucent with colored glow
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color.black.opacity(0.75))
                .shadow(color: color.opacity(0.5), radius: 8)

            // Tinted border
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(color.opacity(0.4), lineWidth: 2)

            // Shape fills ~60% of button area
            agentShapePath
                .foregroundColor(color)
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var agentShapePath: some View {
        switch shape {
        case .circle:
            Circle()
        case .square:
            RoundedRectangle(cornerRadius: 4)
        case .rhombus:
            RhombusShape()
        case .triangle:
            TriangleShape()
        case .hexagon:
            HexagonShape()
        }
    }
}

// MARK: - Custom Shape Paths

private struct RhombusShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centerX = rect.midX
        let centerY = rect.midY
        let radius = min(rect.width, rect.height) / 2

        return Path { path in
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 2
                let point = CGPoint(
                    x: centerX + radius * cos(angle),
                    y: centerY + radius * sin(angle)
                )
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }
}
