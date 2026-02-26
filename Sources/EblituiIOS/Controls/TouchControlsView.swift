import SwiftUI
import UIKit

/// Virtual touch controls overlay for gameplay
/// Button layout is generated dynamically from SystemInfo.buttons
public struct TouchControlsView: View {
    @Binding var buttonMask: Int
    var onMenuTap: () -> Void

    // Haptic feedback generator
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    // SystemInfo buttons split into action and start
    private let actionButtons: [ButtonInfo]
    private let startButton: ButtonInfo?

    // Track per-button pressed state for UI
    @State private var dpadUp = false
    @State private var dpadDown = false
    @State private var dpadLeft = false
    @State private var dpadRight = false
    @State private var actionStates: [Int: Bool] = [:]

    public init(buttonMask: Binding<Int>, onMenuTap: @escaping () -> Void) {
        self._buttonMask = buttonMask
        self.onMenuTap = onMenuTap
        let allButtons = EmulatorBridge.systemInfo.buttons
        self.startButton = allButtons.first(where: { $0.name == "Start" })
        self.actionButtons = allButtons.filter { $0.name != "Start" }
    }

    public var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            if isLandscape {
                landscapeLayout(size: geometry.size)
            } else {
                portraitLayout(size: geometry.size)
            }
        }
        .onChange(of: dpadUp) { _, _ in recalculateMask() }
        .onChange(of: dpadDown) { _, _ in recalculateMask() }
        .onChange(of: dpadLeft) { _, _ in recalculateMask() }
        .onChange(of: dpadRight) { _, _ in recalculateMask() }
    }

    // MARK: - Layouts

    @ViewBuilder
    private func landscapeLayout(size: CGSize) -> some View {
        ZStack {
            // Left side - D-Pad centered vertically with Menu above
            HStack {
                VStack(spacing: 10) {
                    // Menu and Start at top left
                    HStack(spacing: 10) {
                        CircleButton(label: "MENU", isPressed: .constant(false)) {
                            onMenuTap()
                        }
                        .frame(width: 50, height: 50)
                        if let start = startButton {
                            actionButton(for: start)
                                .frame(width: 50, height: 50)
                        }
                    }

                    Spacer()

                    // D-Pad centered vertically
                    DPadView(
                        up: $dpadUp,
                        down: $dpadDown,
                        left: $dpadLeft,
                        right: $dpadRight,
                        onStateChange: { triggerHaptic() }
                    )
                    .frame(width: 150, height: 150)

                    Spacer()
                }
                .padding(.leading, 60)
                .padding(.top, 10)

                Spacer()
            }

            // Right side - Action buttons aligned with D-Pad
            HStack {
                Spacer()

                VStack {
                    Spacer()
                    actionButtonsView
                        .offset(y: 35)
                    Spacer()
                }
                .padding(.trailing, 20)
            }
        }
    }

    @ViewBuilder
    private func portraitLayout(size: CGSize) -> some View {
        VStack {
            // Menu and Start above controls
            HStack(spacing: 15) {
                CircleButton(label: "MENU", isPressed: .constant(false)) {
                    onMenuTap()
                }
                .frame(width: 50, height: 50)
                if let start = startButton {
                    actionButton(for: start)
                        .frame(width: 50, height: 50)
                }
            }
            .padding(.top, 80)
            .padding(.bottom, 10)

            // D-Pad and action buttons
            HStack(alignment: .center) {
                DPadView(
                    up: $dpadUp,
                    down: $dpadDown,
                    left: $dpadLeft,
                    right: $dpadRight,
                    onStateChange: { triggerHaptic() }
                )
                .frame(width: 150, height: 150)
                .padding(.leading, 20)

                Spacer()

                actionButtonsView
                    .padding(.trailing, 20)
            }

            Spacer()
        }
    }

    // MARK: - Dynamic Action Buttons

    @ViewBuilder
    private var actionButtonsView: some View {
        let count = actionButtons.count

        if count <= 2 {
            // 2 buttons: side by side
            HStack(spacing: 10) {
                ForEach(actionButtons, id: \.id) { button in
                    actionButton(for: button)
                        .frame(width: 70, height: 70)
                }
            }
        } else if count <= 3 {
            // 3 buttons: row
            HStack(spacing: 8) {
                ForEach(actionButtons, id: \.id) { button in
                    actionButton(for: button)
                        .frame(width: 60, height: 60)
                }
            }
        } else {
            // 4+ buttons: two rows
            let midpoint = (count + 1) / 2
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(actionButtons[midpoint...].map { $0 }, id: \.id) { button in
                        actionButton(for: button)
                            .frame(width: 55, height: 55)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(actionButtons[..<midpoint].map { $0 }, id: \.id) { button in
                        actionButton(for: button)
                            .frame(width: 55, height: 55)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(for button: ButtonInfo) -> some View {
        let isPressed = Binding<Bool>(
            get: { actionStates[button.id] ?? false },
            set: { newValue in
                actionStates[button.id] = newValue
                recalculateMask()
            }
        )

        CircleButton(label: button.name, isPressed: isPressed) {
            triggerHaptic()
        }
    }

    // MARK: - Mask Calculation

    private func recalculateMask() {
        var mask = 0

        // D-pad bits 0-3
        if dpadUp { mask |= (1 << 0) }
        if dpadDown { mask |= (1 << 1) }
        if dpadLeft { mask |= (1 << 2) }
        if dpadRight { mask |= (1 << 3) }

        // Action buttons at their configured bit positions
        for button in actionButtons {
            if actionStates[button.id] == true {
                mask |= (1 << button.id)
            }
        }

        // Start button
        if let start = startButton, actionStates[start.id] == true {
            mask |= (1 << start.id)
        }

        buttonMask = mask
    }

    private func triggerHaptic() {
        impactGenerator.impactOccurred()
    }
}

/// D-Pad control
struct DPadView: View {
    @Binding var up: Bool
    @Binding var down: Bool
    @Binding var left: Bool
    @Binding var right: Bool
    var onStateChange: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let buttonSize = size / 3

            ZStack {
                // Background circle
                Circle()
                    .fill(Color.black.opacity(0.4))

                // D-pad shape
                DPadShape()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: size * 0.9, height: size * 0.9)

                // Direction indicators
                VStack(spacing: buttonSize * 0.8) {
                    DirectionIndicator(direction: "U", isPressed: up)
                        .frame(width: buttonSize * 0.5, height: buttonSize * 0.5)
                    Spacer()
                    DirectionIndicator(direction: "D", isPressed: down)
                        .frame(width: buttonSize * 0.5, height: buttonSize * 0.5)
                }
                .frame(height: size * 0.9)

                HStack(spacing: buttonSize * 0.8) {
                    DirectionIndicator(direction: "L", isPressed: left)
                        .frame(width: buttonSize * 0.5, height: buttonSize * 0.5)
                    Spacer()
                    DirectionIndicator(direction: "R", isPressed: right)
                        .frame(width: buttonSize * 0.5, height: buttonSize * 0.5)
                }
                .frame(width: size * 0.9)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateDirection(location: value.location, center: center, size: size)
                    }
                    .onEnded { _ in
                        clearAll()
                    }
            )
        }
    }

    private func updateDirection(location: CGPoint, center: CGPoint, size: CGFloat) {
        let deadzone = size * 0.15
        let dx = location.x - center.x
        let dy = location.y - center.y

        let wasPressed = up || down || left || right

        // Reset all directions
        up = false
        down = false
        left = false
        right = false

        // Check if within the d-pad bounds
        let distance = sqrt(dx * dx + dy * dy)
        if distance < deadzone {
            if wasPressed { onStateChange() }
            return
        }

        // Determine direction based on angle
        let angle = atan2(dy, dx)

        // 8-way with 45-degree zones
        let degrees = angle * 180 / .pi

        if degrees >= -22.5 && degrees < 22.5 {
            right = true
        } else if degrees >= 22.5 && degrees < 67.5 {
            right = true
            down = true
        } else if degrees >= 67.5 && degrees < 112.5 {
            down = true
        } else if degrees >= 112.5 && degrees < 157.5 {
            left = true
            down = true
        } else if degrees >= 157.5 || degrees < -157.5 {
            left = true
        } else if degrees >= -157.5 && degrees < -112.5 {
            left = true
            up = true
        } else if degrees >= -112.5 && degrees < -67.5 {
            up = true
        } else if degrees >= -67.5 && degrees < -22.5 {
            right = true
            up = true
        }

        let isPressed = up || down || left || right
        if isPressed != wasPressed {
            onStateChange()
        }
    }

    private func clearAll() {
        if up || down || left || right {
            up = false
            down = false
            left = false
            right = false
            onStateChange()
        }
    }
}

/// D-Pad cross shape
struct DPadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let third = rect.width / 3

        // Top arm
        path.move(to: CGPoint(x: third, y: 0))
        path.addLine(to: CGPoint(x: third * 2, y: 0))
        path.addLine(to: CGPoint(x: third * 2, y: third))

        // Right arm
        path.addLine(to: CGPoint(x: rect.width, y: third))
        path.addLine(to: CGPoint(x: rect.width, y: third * 2))
        path.addLine(to: CGPoint(x: third * 2, y: third * 2))

        // Bottom arm
        path.addLine(to: CGPoint(x: third * 2, y: rect.height))
        path.addLine(to: CGPoint(x: third, y: rect.height))
        path.addLine(to: CGPoint(x: third, y: third * 2))

        // Left arm
        path.addLine(to: CGPoint(x: 0, y: third * 2))
        path.addLine(to: CGPoint(x: 0, y: third))
        path.addLine(to: CGPoint(x: third, y: third))

        path.closeSubpath()

        return path
    }
}

/// Direction indicator arrow
struct DirectionIndicator: View {
    let direction: String
    let isPressed: Bool

    var body: some View {
        Text(direction)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isPressed ? .white : .gray)
    }
}

/// Circular button for action buttons and Menu
struct CircleButton: View {
    let label: String
    @Binding var isPressed: Bool
    var onTap: (() -> Void)?

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )

            Text(label)
                .font(.system(size: label.count > 2 ? 10 : 20, weight: .bold))
                .foregroundColor(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onTap?()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
