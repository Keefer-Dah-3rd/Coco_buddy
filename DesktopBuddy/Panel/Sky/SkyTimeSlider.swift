import SwiftUI

/// The time slider from Coco Nook's "One little plan": ticks along a track, an orange thumb,
/// and the time in big figures above. The extra motion stays small: each tick lights up as
/// the thumb passes it, the thumb stretches with how fast you drag and rings out when you
/// let go, and the figure rolls. Reduce Motion keeps every state and drops the stretch and ring.
///
/// The value snaps to `step` minutes, the same step the old +/- buttons used. The thumb sits
/// at the real value, so an off-step value (from voice, say) still shows where it is.
struct SkyTimeSlider: View {
    /// What the slider is for, read aloud ("Estimate", "Focus length").
    let title: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int
    /// Every this many steps, a longer tick.
    var majorEvery: Int = 4
    /// Shown at the lowest value when that means "none" (the estimate's "—").
    var noneLabel: String?

    init(title: String, minutes: Binding<Int>, range: ClosedRange<Int>, step: Int, majorEvery: Int = 4, noneLabel: String? = nil) {
        self.title = title
        _minutes = minutes
        self.range = range
        self.step = step
        self.majorEvery = majorEvery
        self.noneLabel = noneLabel
    }

    @State private var dragging = false
    @State private var stretch: CGFloat = 0
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0
    @State private var lastX: CGFloat?
    @State private var lastTime: Date?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var steps: Int { max(1, (range.upperBound - range.lowerBound) / step) }

    /// The step the value sits on, for lighting the ticks.
    private var reachedIndex: Int {
        let raw = Double(minutes - range.lowerBound) / Double(step)
        return min(steps, max(0, Int(raw.rounded())))
    }

    /// Where the thumb really is along the track, from 0 to 1.
    private var fraction: CGFloat {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, Double(minutes - range.lowerBound) / span)))
    }

    private var label: String {
        if let noneLabel, minutes <= range.lowerBound { return noneLabel }
        return TodayView.duration(minutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Text(label)
                    .font(Sky.display(22))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(Sky.ink)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .animation(Sky.Motion.quick, value: minutes)
            }
            track
                .frame(height: 46)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let down = press.key == .leftArrow || press.key == .downArrow
            setMinutes(minutes + (down ? -step : step))
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            setMinutes(minutes + (direction == .increment ? step : -step))
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 12
            let width = max(1, geometry.size.width - inset * 2)
            let midY = geometry.size.height / 2
            let thumbX = inset + width * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Sky.line)
                    .frame(width: width, height: 6)
                    .offset(x: inset)
                Capsule()
                    .fill(Sky.accentSoft)
                    .frame(width: width * fraction, height: 6)
                    .offset(x: inset)

                ForEach(0...steps, id: \.self) { index in
                    let major = index % majorEvery == 0
                    let reached = index <= reachedIndex
                    Capsule()
                        .fill(reached ? (major ? Sky.accent : Sky.accentSoft) : Sky.ring)
                        .frame(width: major ? 2.2 : 1.4, height: major ? 16 : 9)
                        .scaleEffect(reached ? 1.25 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: reached)
                        .position(x: inset + width * CGFloat(index) / CGFloat(steps), y: midY)
                }

                thumb
                    .position(x: thumbX, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(drag(inset: inset, width: width))
        }
    }

    private var thumb: some View {
        ZStack {
            Circle()
                .stroke(Sky.accent.opacity(ringOpacity), lineWidth: 2)
                .frame(width: 24, height: 24)
                .scaleEffect(ringScale)
            Circle()
                .fill(Sky.accent)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .frame(width: dragging ? 30 : 24, height: dragging ? 30 : 24)
                .shadow(color: Sky.accent.opacity(dragging ? 0.45 : 0.25), radius: dragging ? 8 : 4, y: 2)
                .scaleEffect(x: 1 + 0.16 * stretch, y: 1 - 0.1 * stretch)
                .animation(Sky.Motion.squish, value: dragging)
                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.5), value: stretch)
        }
    }

    private func drag(inset: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    focused = true
                }
                let t = min(1, max(0, (value.location.x - inset) / width))
                setMinutes(range.lowerBound + Int((t * CGFloat(steps)).rounded()) * step)

                // The thumb stretches with how fast it's moving, in points a second.
                if !reduceMotion, let lastX, let lastTime {
                    let elapsed = max(0.001, value.time.timeIntervalSince(lastTime))
                    stretch = min(1, abs(value.location.x - lastX) / elapsed / 900)
                }
                lastX = value.location.x
                lastTime = value.time
            }
            .onEnded { _ in
                dragging = false
                stretch = 0
                lastX = nil
                lastTime = nil
                ring()
            }
    }

    private func setMinutes(_ value: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        guard clamped != minutes else { return }
        minutes = clamped
    }

    /// The ring that rings out from the thumb when you let go.
    private func ring() {
        guard !reduceMotion else { return }
        ringScale = 1
        ringOpacity = 0.7
        withAnimation(.easeOut(duration: 0.55)) {
            ringScale = 2.1
            ringOpacity = 0
        }
    }
}
