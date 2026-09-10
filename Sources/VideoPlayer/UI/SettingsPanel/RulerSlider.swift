import SwiftUI

struct RulerSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var logScale = false
    var labels: [(value: Double, text: String)] = []

    private let thumbWidth: CGFloat = 10
    private let thumbHeight: CGFloat = 22
    private let tickCount = 16

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbX = x(forValue: value, width: width)

            VStack(spacing: 4) {
                ZStack {
                    ticks(width: width)
                    Capsule()
                        .fill(.white)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .position(x: thumbX, y: 16)
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            value = snapped(fromX: drag.location.x, width: width)
                        }
                )

                if !labels.isEmpty {
                    ZStack(alignment: .top) {
                        ForEach(Array(labels.enumerated()), id: \.offset) { _, item in
                            Text(item.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .position(
                                    x: x(forValue: item.value, width: width),
                                    y: 7
                                )
                        }
                    }
                    .frame(height: 14)
                }
            }
        }
        .frame(height: labels.isEmpty ? 36 : 50)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = snapped(value + step)
            case .decrement:
                value = snapped(value - step)
            default:
                break
            }
        }
    }

    private func ticks(width: CGFloat) -> some View {
        Canvas { context, size in
            guard size.width > 0 else { return }
            let midY = size.height / 2
            for index in 0...tickCount {
                let tickX = Self.x(
                    forPosition: Double(index) / Double(tickCount),
                    width: width,
                    thumbSize: thumbWidth
                )
                let labeled = labels.contains {
                    abs(
                        Self.position(for: $0.value, range: range, logScale: logScale)
                            - Double(index) / Double(tickCount)
                    ) < 0.03
                }
                let half = labeled ? 9.0 : 5.5
                var path = Path()
                path.move(to: CGPoint(x: tickX, y: midY - half))
                path.addLine(to: CGPoint(x: tickX, y: midY + half))
                context.stroke(
                    path,
                    with: .color(.secondary.opacity(labeled ? 0.85 : 0.4)),
                    lineWidth: 1
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func x(forValue value: Double, width: CGFloat) -> CGFloat {
        Self.x(
            forPosition: Self.position(for: value, range: range, logScale: logScale),
            width: width,
            thumbSize: thumbWidth
        )
    }

    private func snapped(_ rawValue: Double) -> Double {
        Self.snapped(rawValue, range: range, step: step)
    }

    private func snapped(fromX xPosition: CGFloat, width: CGFloat) -> Double {
        let usable = max(width - thumbWidth, 1)
        let t = min(max(Double((xPosition - thumbWidth / 2) / usable), 0), 1)
        return snapped(Self.value(at: t, range: range, logScale: logScale))
    }

    static func tickCount(range: ClosedRange<Double>, step: Double) -> Int {
        Int(round((range.upperBound - range.lowerBound) / step))
    }

    static func snapped(_ rawValue: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let ticks = ((rawValue - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + ticks * step, range.lowerBound), range.upperBound)
    }

    static func position(
        for value: Double,
        range: ClosedRange<Double>,
        logScale: Bool
    ) -> Double {
        if logScale {
            let lower = log(range.lowerBound)
            let upper = log(range.upperBound)
            return (log(value) - lower) / (upper - lower)
        }
        let span = range.upperBound - range.lowerBound
        return span == 0 ? 0 : (value - range.lowerBound) / span
    }

    static func value(
        at position: Double,
        range: ClosedRange<Double>,
        logScale: Bool
    ) -> Double {
        if logScale {
            let lower = log(range.lowerBound)
            let upper = log(range.upperBound)
            return exp(lower + position * (upper - lower))
        }
        return range.lowerBound + position * (range.upperBound - range.lowerBound)
    }

    static func x(forPosition position: Double, width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        let usable = max(width - thumbSize, 1)
        return thumbSize / 2 + usable * CGFloat(min(max(position, 0), 1))
    }
}
