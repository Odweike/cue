import SwiftUI

struct RulerSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var majorEvery: Int

    var body: some View {
        VStack(spacing: 3) {
            Slider(
                value: Binding(
                    get: { value },
                    set: { value = snapped($0) }
                ),
                in: range
            )

            Canvas { context, size in
                let ticks = tickCount
                guard ticks > 0, size.width > 0 else { return }
                for index in 0...ticks {
                    let x = size.width * CGFloat(index) / CGFloat(ticks)
                    let isMajor = index.isMultiple(of: max(majorEvery, 1))
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: isMajor ? 7 : 3.5))
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(isMajor ? 0.9 : 0.45)),
                        lineWidth: 1
                    )
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
    }

    private var tickCount: Int {
        Int(round((range.upperBound - range.lowerBound) / step))
    }

    private func snapped(_ rawValue: Double) -> Double {
        let ticks = ((rawValue - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + ticks * step, range.lowerBound), range.upperBound)
    }
}
