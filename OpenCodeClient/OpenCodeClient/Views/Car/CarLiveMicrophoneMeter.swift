import CoreGraphics
import Foundation
import SwiftUI

nonisolated enum CarLiveMicrophoneMeter {
    static let iconSide: CGFloat = 48
    static let fullScaleInput = 0.25
    static let attack: TimeInterval = 0.065
    static let release: TimeInterval = 0.320

    enum Motion: Equatable {
        case snap
        case attack
        case release
    }

    struct Transition: Equatable {
        var fill: Double
        var motion: Motion

        var duration: TimeInterval {
            switch motion {
            case .snap:
                return 0
            case .attack:
                return CarLiveMicrophoneMeter.attack
            case .release:
                return CarLiveMicrophoneMeter.release
            }
        }
    }

    static func sanitized(_ inputLevel: Double) -> Double {
        guard inputLevel.isFinite else { return 0 }
        return min(1, max(0, inputLevel))
    }

    static func displayFill(inputLevel: Double) -> Double {
        let raw = sanitized(inputLevel)
        guard raw > 0 else { return 0 }
        return min(1, (raw / fullScaleInput).squareRoot())
    }

    static func isLive(phase: CarLivePhase, isMuted: Bool) -> Bool {
        guard !isMuted else { return false }
        switch phase {
        case .listening, .speaking:
            return true
        case .idle, .connecting, .closing, .failed:
            return false
        }
    }

    static func targetFill(inputLevel: Double, phase: CarLivePhase, isMuted: Bool) -> Double {
        guard isLive(phase: phase, isMuted: isMuted) else { return 0 }
        return displayFill(inputLevel: inputLevel)
    }

    static func transition(
        from current: Double,
        inputLevel: Double,
        phase: CarLivePhase,
        isMuted: Bool,
        reduceMotion: Bool
    ) -> Transition {
        let fill = targetFill(inputLevel: inputLevel, phase: phase, isMuted: isMuted)
        let live = isLive(phase: phase, isMuted: isMuted)
        if reduceMotion || !live || abs(fill - current) <= 0.000_001 {
            return Transition(fill: fill, motion: .snap)
        }
        if fill > current {
            return Transition(fill: fill, motion: .attack)
        }
        return Transition(fill: fill, motion: .release)
    }
}

nonisolated struct CarLiveMicrophoneGlyphLayout: Equatable {
    var side: CGFloat
    var stroke: CGFloat
    var slashStroke: CGFloat
    var head: CGRect
    var innerHead: CGRect
    var cradleLeft: CGFloat
    var cradleRight: CGFloat
    var armTop: CGFloat
    var arcCenterY: CGFloat
    var arcRadius: CGFloat
    var cradleBottom: CGFloat
    var stemBottom: CGFloat
    var baseHalf: CGFloat
    var slashStart: CGPoint
    var slashEnd: CGPoint

    init(side: CGFloat = CarLiveMicrophoneMeter.iconSide) {
        self.side = side
        stroke = side * 1.8 / 28
        slashStroke = side * 2.1 / 28
        let headSize = CGSize(width: side * 10.4 / 28, height: side * 14.4 / 28)
        let headOrigin = CGPoint(x: (side - headSize.width) / 2, y: side * 3.7 / 28)
        head = CGRect(origin: headOrigin, size: headSize)
        let gap = stroke / 2 + side * 1.15 / 28
        innerHead = head.insetBy(dx: gap, dy: gap)
        let cradleGap = side * 2.3 / 28
        cradleLeft = head.minX - cradleGap
        cradleRight = head.maxX + cradleGap
        armTop = head.minY + head.height * 0.42
        arcRadius = (cradleRight - cradleLeft) / 2
        cradleBottom = head.maxY + side * 2.8 / 28
        arcCenterY = cradleBottom - arcRadius
        stemBottom = cradleBottom + side * 3.5 / 28
        baseHalf = side * 5.6 / 28
        slashStart = CGPoint(x: side * 21.8 / 28, y: side * 4.6 / 28)
        slashEnd = CGPoint(x: side * 6.0 / 28, y: side * 24.8 / 28)
    }

    func revealRect(fill: Double) -> CGRect {
        let fraction = min(1, max(0, fill.isFinite ? fill : 0))
        let height = innerHead.height * fraction
        return CGRect(x: innerHead.minX, y: innerHead.maxY - height, width: innerHead.width, height: height)
    }

    var inkStaysInsideSide: Bool {
        let pad = max(stroke, slashStroke) / 2
        let xs = [head.minX, head.maxX, innerHead.minX, innerHead.maxX, cradleLeft, cradleRight, slashStart.x, slashEnd.x]
        let ys = [head.minY, head.maxY, cradleBottom, stemBottom, slashStart.y, slashEnd.y, armTop, arcCenterY]
        let minX = (xs.min() ?? 0) - pad
        let maxX = (xs.max() ?? 0) + pad
        let minY = (ys.min() ?? 0) - pad
        let maxY = (ys.max() ?? 0) + pad
        return minX >= 0 && minY >= 0 && maxX <= side && maxY <= side
    }
}

struct CarLiveMicrophoneMeterIcon: View {
    var inputLevel: Double
    var phase: CarLivePhase
    var isMuted: Bool
    var foreground: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedFill: Double

    init(inputLevel: Double, phase: CarLivePhase, isMuted: Bool, foreground: Color) {
        self.inputLevel = inputLevel
        self.phase = phase
        self.isMuted = isMuted
        self.foreground = foreground
        _displayedFill = State(initialValue: CarLiveMicrophoneMeter.targetFill(
            inputLevel: inputLevel,
            phase: phase,
            isMuted: isMuted
        ))
    }

    var body: some View {
        CarLiveMicrophoneGlyph(fill: displayedFill, showsSlash: isMuted, color: foreground)
            .onAppear {
                apply(CarLiveMicrophoneMeter.transition(
                    from: displayedFill,
                    inputLevel: inputLevel,
                    phase: phase,
                    isMuted: isMuted,
                    reduceMotion: true
                ))
            }
            .onChange(of: sample) { _, _ in
                apply(CarLiveMicrophoneMeter.transition(
                    from: displayedFill,
                    inputLevel: inputLevel,
                    phase: phase,
                    isMuted: isMuted,
                    reduceMotion: reduceMotion
                ))
            }
    }

    private var sample: Sample {
        Sample(
            inputLevel: CarLiveMicrophoneMeter.sanitized(inputLevel),
            phase: phase,
            isMuted: isMuted,
            reduceMotion: reduceMotion
        )
    }

    private func apply(_ transition: CarLiveMicrophoneMeter.Transition) {
        switch transition.motion {
        case .snap:
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedFill = transition.fill
            }
        case .attack, .release:
            withAnimation(.easeOut(duration: transition.duration)) {
                displayedFill = transition.fill
            }
        }
    }

    private struct Sample: Equatable {
        var inputLevel: Double
        var phase: CarLivePhase
        var isMuted: Bool
        var reduceMotion: Bool
    }
}

private struct CarLiveMicrophoneGlyph: View, Animatable {
    var fill: Double
    var showsSlash: Bool
    var color: Color

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let side = CarLiveMicrophoneMeter.iconSide
            var drawing = context
            drawing.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let layout = CarLiveMicrophoneGlyphLayout(side: side)
            let fraction = min(1, max(0, fill.isFinite ? fill : 0))
            if fraction > 0 {
                var clipped = drawing
                clipped.clip(to: capsule(layout.innerHead))
                clipped.fill(Path(layout.revealRect(fill: fraction)), with: .color(color))
            }
            let outline = StrokeStyle(lineWidth: layout.stroke, lineCap: .round, lineJoin: .round)
            drawing.stroke(capsule(layout.head), with: .color(color), style: outline)
            drawing.stroke(cradle(layout), with: .color(color), style: outline)
            drawing.stroke(stem(layout), with: .color(color), style: outline)
            if showsSlash {
                var slash = Path()
                slash.move(to: layout.slashStart)
                slash.addLine(to: layout.slashEnd)
                drawing.stroke(
                    slash,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: layout.slashStroke, lineCap: .round)
                )
            }
        }
        .frame(width: CarLiveMicrophoneMeter.iconSide, height: CarLiveMicrophoneMeter.iconSide)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func capsule(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    }

    private func cradle(_ layout: CarLiveMicrophoneGlyphLayout) -> Path {
        let kappa: CGFloat = 0.5522847498
        let radius = layout.arcRadius
        let centerY = layout.arcCenterY
        let midX = (layout.cradleLeft + layout.cradleRight) / 2
        var path = Path()
        path.move(to: CGPoint(x: layout.cradleLeft, y: layout.armTop))
        path.addLine(to: CGPoint(x: layout.cradleLeft, y: centerY))
        path.addCurve(
            to: CGPoint(x: midX, y: centerY + radius),
            control1: CGPoint(x: layout.cradleLeft, y: centerY + kappa * radius),
            control2: CGPoint(x: midX - kappa * radius, y: centerY + radius)
        )
        path.addCurve(
            to: CGPoint(x: layout.cradleRight, y: centerY),
            control1: CGPoint(x: midX + kappa * radius, y: centerY + radius),
            control2: CGPoint(x: layout.cradleRight, y: centerY + kappa * radius)
        )
        path.addLine(to: CGPoint(x: layout.cradleRight, y: layout.armTop))
        return path
    }

    private func stem(_ layout: CarLiveMicrophoneGlyphLayout) -> Path {
        let midX = layout.side / 2
        var path = Path()
        path.move(to: CGPoint(x: midX, y: layout.cradleBottom))
        path.addLine(to: CGPoint(x: midX, y: layout.stemBottom))
        path.move(to: CGPoint(x: midX - layout.baseHalf, y: layout.stemBottom))
        path.addLine(to: CGPoint(x: midX + layout.baseHalf, y: layout.stemBottom))
        return path
    }
}
