import SwiftUI

/// An editable 24-hour clock. The two endpoints are separate VoiceOver controls.
struct SleepDial: View {
    @Binding var bed: Int
    @Binding var wake: Int
    let duration: Int

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: Theme.Metrics.itemSpacing) {
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius = min(center.x, center.y) - Theme.Metrics.minHitTarget / 2
                ZStack {
                    marks(center: center, radius: radius)
                    dialReadout(radius: radius)
                    handle($bed, title: Text("Bedtime", comment: "VoiceOver: the sleep dial’s bedtime handle."), symbol: "moon.fill", identifier: "checkin.dial.bed",
                           center: center, radius: bedRadius(radius))
                    handle($wake, title: Text("Wake time", comment: "VoiceOver: the sleep dial’s wake time handle."), symbol: "sun.max.fill", identifier: "checkin.dial.wake",
                           center: center, radius: radius)
                }
                .coordinateSpace(.named("sleepDial"))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("checkin.dial")
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Theme.Metrics.circleButton * 7)
            if typeSize.isAccessibilitySize {
                Text(verbatim: timeRange)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(trigger: bed, feedback)
        .sensoryFeedback(trigger: wake, feedback)
    }

    private var timeRange: String { "\(clock(bed)) – \(clock(wake))" }

    private func clock(_ minutes: Int) -> String {
        Fmt.time(hour: minutes / 60, minute: minutes % 60, locale: locale)
    }

    private func feedback(_ old: Int, _ new: Int) -> SensoryFeedback? {
        guard old != new else { return nil }
        return new.isMultiple(of: 60) ? .impact(weight: .light) : .selection
    }

    private func dialReadout(radius: CGFloat) -> some View {
        let text = durationText
        return VStack(spacing: Theme.Metrics.hairline) {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: text).font(.ryft(.metric))
                Text(verbatim: text).font(.ryft(.callout))
            }
            .foregroundStyle(Theme.textPrimary)
            .accessibilityLabel(Text(verbatim: Fmt.spokenDuration(minutes: duration, locale: locale)))
            if !typeSize.isAccessibilitySize {
                Text(verbatim: timeRange)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: max(0, radius * 1.35))
    }

    private var durationText: String {
        let (hours, minutes) = max(0, duration).quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return String(localized: "\(minutes) min", comment: "Sleep dial duration in minutes.") }
        if minutes == 0 { return String(localized: "\(hours) h", comment: "Sleep dial duration in whole hours.") }
        return String(localized: "\(hours) h \(minutes) min", comment: "Sleep dial duration, e.g. 7 h 30 min.")
    }

    private func marks(center: CGPoint, radius: CGFloat) -> some View {
        Canvas { context, _ in
            var ticks = Path()
            for hour in 0..<24 {
                let length = hour.isMultiple(of: 6) ? Theme.Metrics.itemSpacing : Theme.Metrics.itemSpacing / 2
                ticks.move(to: point(hour * 60, at: radius, around: center))
                ticks.addLine(to: point(hour * 60, at: radius - length, around: center))
            }
            context.stroke(ticks, with: .color(Theme.textTertiary), lineWidth: Theme.Metrics.hairline)
            let track = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(track, with: .color(Theme.separator), lineWidth: Theme.Metrics.controlOutline)

            let start = SleepDialMath.angle(for: bed) - 90
            let span = Double(SleepDialMath.duration(bed: bed, wake: wake)) * 360 / Double(SleepDialMath.dayMinutes)
            var sleep = Path()
            sleep.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + span),
                         clockwise: false)
            context.stroke(sleep, with: .color(Theme.textPrimary),
                           style: StrokeStyle(lineWidth: Theme.Metrics.controlOutline * 2, lineCap: .round))

            for hour in [0, 6, 12, 18] {
                let label = Text(verbatim: "\(hour)").font(.ryft(.axis)).foregroundStyle(Theme.textSecondary)
                context.draw(label, at: point(hour * 60, at: radius - Theme.Metrics.screenPadding - Theme.Metrics.itemSpacing / 2,
                                              around: center))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }

    private func handle(_ value: Binding<Int>, title: Text, symbol: String, identifier: String,
                        center: CGPoint, radius: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.ryft(.headline))
            .dynamicTypeSize(...DynamicTypeSize.large)
            .foregroundStyle(Theme.background)
            .frame(width: Theme.Metrics.circleButton, height: Theme.Metrics.circleButton)
            .background(Theme.textPrimary, in: Circle())
            .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("sleepDial")).onChanged { drag in
                let dx = drag.location.x - center.x
                let dy = drag.location.y - center.y
                guard hypot(dx, dy) >= Theme.Metrics.minHitTarget / 2 else { return }
                let angle = atan2(Double(dx), -Double(dy)) * 180 / .pi
                value.wrappedValue = SleepDialMath.snap(SleepDialMath.minutes(for: angle))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(Text(verbatim: clock(value.wrappedValue)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value.wrappedValue = SleepDialMath.wrapped(value.wrappedValue + SleepDialMath.step)
                case .decrement: value.wrappedValue = SleepDialMath.wrapped(value.wrappedValue - SleepDialMath.step)
                @unknown default: break
                }
            }
            .accessibilityIdentifier(identifier)
            .position(point(value.wrappedValue, at: radius, around: center))
    }

    /// Move the bed handle inward when the touch targets would otherwise overlap.
    private func bedRadius(_ radius: CGFloat) -> CGFloat {
        let a = point(bed, at: radius, around: .zero)
        let b = point(wake, at: radius, around: .zero)
        return hypot(a.x - b.x, a.y - b.y) < Theme.Metrics.minHitTarget ? radius - Theme.Metrics.minHitTarget : radius
    }

    private func point(_ minutes: Int, at radius: CGFloat, around center: CGPoint) -> CGPoint {
        let radians = SleepDialMath.angle(for: minutes) * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(radians)), y: center.y - radius * CGFloat(cos(radians)))
    }
}

#Preview("Sleep dial") {
    @Previewable @State var bed = 22 * 60 + 10
    @Previewable @State var wake = 5 * 60 + 40
    DarkPreview {
        SleepDial(bed: $bed, wake: $wake, duration: SleepDialMath.duration(bed: bed, wake: wake))
    }
}
