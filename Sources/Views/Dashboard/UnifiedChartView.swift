import Charts
import SwiftUI

struct UnifiedChartView: View {
    let snapshots: [UsageSnapshot]
    var gaps: [MonitoringGap] = []
    var momentum: MomentumCalculation?
    var projection: WindowProjection?
    var fiveHourWindow: UsageWindow?
    var sevenDayWindow: UsageWindow?
    var usagePlan: UsagePlan?
    var dailyTarget: BudgetEngine.DailyTarget?

    @State private var hoverDate: Date?
    @State private var now: Date = .now

    // Timeline state
    @State private var visibleCenter: Date = .now
    @State private var visibleSpan: TimeInterval = 3 * 3600
    @State private var gestureSpanAtStart: TimeInterval = 0
    @State private var gestureCenterAtStart: Date = .distantPast
    @State private var activePreset: Preset? = .threeHours

    private static let maxChartPoints = 500
    private static let minSpan: TimeInterval = 5 * 60
    private static let maxSpan: TimeInterval = 14 * 86400

    // MARK: - Presets

    enum Preset: String, CaseIterable {
        case threeHours = "3H"
        case today = "Today"
        case thisWeek = "This Week"
    }

    /// The 7-day window boundaries (start...reset).
    private var currentWindowStart: Date {
        guard let sevenDay = sevenDayWindow else {
            return now.addingTimeInterval(-7 * 86400)
        }
        return sevenDay.resetsAt.addingTimeInterval(-sevenDay.duration)
    }

    private var currentWindowEnd: Date {
        sevenDayWindow?.resetsAt ?? now
    }

    private var windowDuration: TimeInterval {
        sevenDayWindow?.duration ?? 7 * 86400
    }

    // MARK: - Timeline Bounds

    private var timelineStart: Date {
        let earliest = snapshots.first?.timestamp ?? now
        // Allow navigating one window back from current
        let oneWindowBack = currentWindowStart.addingTimeInterval(-windowDuration)
        return min(earliest, oneWindowBack)
    }

    private var timelineEnd: Date {
        // Extend to the current window reset (for projections/target)
        return max(now, currentWindowEnd)
    }

    private var totalSpan: TimeInterval {
        max(timelineEnd.timeIntervalSince(timelineStart), Self.minSpan)
    }

    private var dateRange: ClosedRange<Date> {
        let halfSpan = visibleSpan / 2
        var from = visibleCenter.addingTimeInterval(-halfSpan)
        var to = visibleCenter.addingTimeInterval(halfSpan)

        if from < timelineStart {
            from = timelineStart
            to = from.addingTimeInterval(visibleSpan)
        }
        if to > timelineEnd {
            to = timelineEnd
            from = to.addingTimeInterval(-visibleSpan)
            if from < timelineStart { from = timelineStart }
        }

        return from...max(to, from.addingTimeInterval(1))
    }

    private var filteredSnapshots: [UsageSnapshot] {
        let range = dateRange
        let base = snapshots
            .filter { $0.timestamp >= range.lowerBound && $0.timestamp <= range.upperBound }
            .sorted { $0.timestamp < $1.timestamp }
        guard base.count > Self.maxChartPoints else { return base }

        let bucketCount = Self.maxChartPoints
        let rangeSpan = range.upperBound.timeIntervalSince(range.lowerBound)
        let bucketDuration = rangeSpan / Double(bucketCount)

        var result: [UsageSnapshot] = []
        result.reserveCapacity(bucketCount)
        var bucketStart = range.lowerBound
        var baseIdx = 0

        for _ in 0..<bucketCount {
            let bucketEnd = bucketStart.addingTimeInterval(bucketDuration)
            var sumFive = 0.0, sumSeven = 0.0, count = 0

            while baseIdx < base.count && base[baseIdx].timestamp < bucketEnd {
                sumFive += base[baseIdx].fiveHourUtilization
                sumSeven += base[baseIdx].sevenDayUtilization
                count += 1
                baseIdx += 1
            }

            if count > 0 {
                let midTime = bucketStart.addingTimeInterval(bucketDuration / 2)
                result.append(UsageSnapshot(
                    id: UUID(),
                    accountID: base[0].accountID,
                    timestamp: midTime,
                    fiveHourUtilization: sumFive / Double(count),
                    sevenDayUtilization: sumSeven / Double(count)
                ))
            }
            bucketStart = bucketEnd
        }

        if let last = base.last, result.last?.timestamp != last.timestamp {
            result.append(last)
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toolbar
            HStack(spacing: 6) {
                // Previous window
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { navigateWindow(direction: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous week")
                .help("Previous week")

                // Presets
                ForEach(Preset.allCases, id: \.self) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { applyPreset(preset) }
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                activePreset == preset
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(Color.secondary.opacity(0.1)),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .foregroundStyle(activePreset == preset ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                // Next window
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { navigateWindow(direction: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next week")
                .help("Next week")

                Spacer()

                usageStats
            }

            // Chart
            usageChart
                .frame(height: 180)
                .clipped()
                .contentShape(Rectangle())
                .gesture(panGesture)
                .gesture(pinchGesture)
                .onScrollWheel { delta in
                    handleScrollWheel(delta)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartAccessibilityLabel)

            // Range info
            HStack {
                rangeLabel
                Spacer()
            }
        }
        .onAppear { applyPreset(.threeHours) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            now = date
            // Keep right edge pinned to now for live presets
            if activePreset == .threeHours || activePreset == .today {
                visibleCenter = now.addingTimeInterval(-visibleSpan / 2 + visibleSpan / 2)
            }
        }
    }

    private var chartAccessibilityLabel: String {
        let count = filteredSnapshots.count
        let range = dateRange
        let spanDesc = rangeDescription(span: range.upperBound.timeIntervalSince(range.lowerBound))
        let fivePeak = filteredSnapshots.map(\.fiveHourUtilization).max() ?? 0
        let sevenPeak = filteredSnapshots.map(\.sevenDayUtilization).max() ?? 0
        return "Usage history chart, \(spanDesc), \(count) data points. Peak 5-hour \(Int(fivePeak)) percent, peak 7-day \(Int(sevenPeak)) percent"
    }

    // MARK: - Preset Logic

    private func applyPreset(_ preset: Preset) {
        activePreset = preset
        switch preset {
        case .threeHours:
            visibleSpan = 3 * 3600
            visibleCenter = now.addingTimeInterval(-visibleSpan / 2 + visibleSpan / 2)
        case .today:
            visibleSpan = 24 * 3600
            visibleCenter = now.addingTimeInterval(-visibleSpan / 2 + visibleSpan / 2)
        case .thisWeek:
            visibleSpan = windowDuration
            let midpoint = currentWindowStart.addingTimeInterval(windowDuration / 2)
            visibleCenter = midpoint
        }
        clampTimeline()
    }

    private func navigateWindow(direction: Int) {
        activePreset = nil
        let offset = Double(direction) * windowDuration
        visibleSpan = windowDuration
        let targetStart = currentWindowStart.addingTimeInterval(offset)
        visibleCenter = targetStart.addingTimeInterval(windowDuration / 2)
        clampTimeline()
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if gestureCenterAtStart == .distantPast {
                    gestureCenterAtStart = visibleCenter
                }
                let pixelsPerSecond = 400.0 / visibleSpan
                let timeOffset = -Double(value.translation.width) / pixelsPerSecond
                visibleCenter = gestureCenterAtStart.addingTimeInterval(timeOffset)
                activePreset = nil
                clampTimeline()
            }
            .onEnded { _ in
                gestureCenterAtStart = .distantPast
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if gestureSpanAtStart == 0 {
                    gestureSpanAtStart = visibleSpan
                }
                let newSpan = gestureSpanAtStart / value.magnification
                visibleSpan = min(max(newSpan, Self.minSpan), min(totalSpan, Self.maxSpan))
                activePreset = nil
                clampTimeline()
            }
            .onEnded { _ in
                gestureSpanAtStart = 0
            }
    }

    private func handleScrollWheel(_ delta: CGPoint) {
        if abs(delta.x) > abs(delta.y) || abs(delta.y) < 0.5 {
            let panFraction = delta.x / 400.0
            let timeOffset = -Double(panFraction) * visibleSpan
            visibleCenter = visibleCenter.addingTimeInterval(timeOffset)
        } else {
            let zoomFactor = 1.0 + Double(delta.y) * 0.03
            visibleSpan = min(max(visibleSpan * zoomFactor, Self.minSpan), min(totalSpan, Self.maxSpan))
        }
        activePreset = nil
        clampTimeline()
    }

    // MARK: - Timeline Helpers

    private func clampTimeline() {
        visibleSpan = min(max(visibleSpan, Self.minSpan), min(totalSpan, Self.maxSpan))

        let halfSpan = visibleSpan / 2
        let minCenter = timelineStart.addingTimeInterval(halfSpan)
        let maxCenter = timelineEnd.addingTimeInterval(-halfSpan)

        if minCenter >= maxCenter {
            visibleCenter = timelineStart.addingTimeInterval(totalSpan / 2)
        } else if visibleCenter < minCenter {
            visibleCenter = minCenter
        } else if visibleCenter > maxCenter {
            visibleCenter = maxCenter
        }
    }

    // MARK: - Range Label

    private var rangeLabel: some View {
        let range = dateRange
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        return HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(rangeDescription(span: span))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func rangeDescription(span: TimeInterval) -> String {
        if span < 3600 {
            return "\(Int(span / 60))m window"
        } else if span < 86400 {
            return String(format: "%.1fh window", span / 3600)
        } else {
            return String(format: "%.1fd window", span / 86400)
        }
    }

    // MARK: - Chart Overlay

    private func chartOverlay<V: View>(content: V) -> some View {
        content
            .chartXScale(domain: dateRange)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geo[plotFrame].origin
                                let x = location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    hoverDate = date
                                }
                            case .ended:
                                hoverDate = nil
                            }
                        }
                }
            }
    }

    private func axisLabel(for date: Date) -> String {
        if visibleSpan < 86400 * 2 {
            return date.formatted(.dateTime.hour().minute())
        } else {
            return date.formatted(.dateTime.weekday(.abbreviated).hour())
        }
    }

    // MARK: - Projection

    private var projectionEnd: Date? {
        if let sevenDayReset = sevenDayWindow?.resetsAt {
            return sevenDayReset
        }
        guard momentum?.velocity ?? 0 > 0 else { return nil }
        if let fiveHourReset = fiveHourWindow?.resetsAt {
            return min(fiveHourReset, now.addingTimeInterval(3600))
        }
        return now.addingTimeInterval(3600)
    }

    private struct UsageProjectionData {
        var fiveHour: [(date: Date, value: Double)] = []
        var sevenDay: [(date: Date, value: Double)] = []
        var sevenDayBand: [(date: Date, low: Double, high: Double)] = []
        var isPatternAware: Bool = false
    }

    private var usageProjectionPoints: UsageProjectionData? {
        guard let lastSnap = filteredSnapshots.last,
              let velocity = momentum?.velocity, velocity > 0
        else { return nil }

        let sevenDayVelocity = projection?.sevenDayVelocity ?? 0
        guard let end = projectionEnd, end > lastSnap.timestamp else { return nil }

        var data = UsageProjectionData()

        // 5-hour projection (only when zoomed in)
        if visibleSpan < 86400 {
            let fiveHourEnd = fiveHourWindow?.resetsAt ?? now.addingTimeInterval(3600)
            let cappedEnd = min(fiveHourEnd, now.addingTimeInterval(3600))
            if cappedEnd > lastSnap.timestamp {
                let startDate = lastSnap.timestamp
                let steps = 30
                let interval = cappedEnd.timeIntervalSince(startDate) / Double(steps)
                data.fiveHour.append((startDate, lastSnap.fiveHourUtilization))
                for i in 1...steps {
                    let date = startDate.addingTimeInterval(Double(i) * interval)
                    let hours = date.timeIntervalSince(startDate) / 3600
                    let value = min(lastSnap.fiveHourUtilization + velocity * hours, 100)
                    data.fiveHour.append((date, value))
                }
            }
        }

        // 7-day projection
        if let pattern = projection?.patternProjection, pattern.curve.count >= 2 {
            data.isPatternAware = pattern.isPatternAware
            for point in pattern.curve {
                data.sevenDay.append((point.date, point.projected))
                data.sevenDayBand.append((point.date, point.optimistic, point.pessimistic))
            }
        } else if sevenDayVelocity > 0 {
            let startDate = lastSnap.timestamp
            let sevenDayBase = projection?.currentGranularUtilization() ?? lastSnap.sevenDayUtilization
            let steps = 60
            let interval = end.timeIntervalSince(startDate) / Double(steps)
            data.sevenDay.append((startDate, sevenDayBase))
            for i in 1...steps {
                let date = startDate.addingTimeInterval(Double(i) * interval)
                let hours = date.timeIntervalSince(startDate) / 3600
                let value = min(sevenDayBase + sevenDayVelocity * hours, 100)
                data.sevenDay.append((date, value))
            }
        }

        return data
    }

    private var sevenDayResetInRange: Date? {
        guard let resetDate = sevenDayWindow?.resetsAt,
              resetDate >= dateRange.lowerBound && resetDate <= dateRange.upperBound
        else { return nil }
        return resetDate
    }

    private var projectedAtReset: Double? {
        projection?.projectedAtReset
    }

    // MARK: - Target Curve

    private var targetCurvePoints: [(date: Date, value: Double)] {
        guard let plan = usagePlan, plan.isEnabled,
              let sevenDay = sevenDayWindow
        else { return [] }

        let resetDate = sevenDay.resetsAt
        let current7Day = sevenDay.utilization
        let totalBudget = max(100 - current7Day, 0)
        guard totalBudget > 0 else { return [] }

        let totalActiveHours = plan.activeHoursRemaining(until: resetDate, from: now)
        guard totalActiveHours > 0 else { return [] }

        let budgetPerHour = totalBudget / totalActiveHours
        var points: [(date: Date, value: Double)] = []
        var cursor = now
        var accumulatedBudget = 0.0

        points.append((now, current7Day))

        while cursor < resetDate {
            let nextCursor = cursor.addingTimeInterval(3600)
            let stepEnd = min(nextCursor, resetDate)

            if plan.isActiveTime(cursor) {
                let dt = stepEnd.timeIntervalSince(cursor) / 3600
                accumulatedBudget += budgetPerHour * dt
            }

            points.append((stepEnd, min(current7Day + accumulatedBudget, 100)))
            cursor = nextCursor
        }

        return points
    }

    // MARK: - Usage Chart

    private var peakUtilization: Double {
        let fivePeak = filteredSnapshots.map(\.fiveHourUtilization).max() ?? 0
        let sevenPeak = filteredSnapshots.map(\.sevenDayUtilization).max() ?? 0
        let projFivePeak = usageProjectionPoints?.fiveHour.map(\.value).max() ?? 0
        let projSevenPeak = usageProjectionPoints?.sevenDay.map(\.value).max() ?? 0
        let bandPeak = usageProjectionPoints?.sevenDayBand.map(\.high).max() ?? 0
        let targetPeak = targetCurvePoints.map(\.value).max() ?? 0
        return max(fivePeak, sevenPeak, projFivePeak, projSevenPeak, bandPeak, targetPeak)
    }

    private func nearestSnapshot(to date: Date) -> UsageSnapshot? {
        guard !filteredSnapshots.isEmpty else { return nil }
        return filteredSnapshots.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }

    private var usageChart: some View {
        let proj = usageProjectionPoints
        return chartOverlay(content:
            Chart {
                ForEach(filteredSnapshots) { snapshot in
                    LineMark(
                        x: .value("Time", snapshot.timestamp),
                        y: .value("5h Usage", snapshot.fiveHourUtilization)
                    )
                    .foregroundStyle(by: .value("Window", "5-Hour"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    LineMark(
                        x: .value("Time", snapshot.timestamp),
                        y: .value("7d Usage", snapshot.sevenDayUtilization)
                    )
                    .foregroundStyle(by: .value("Window", "7-Day"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // 5-hour projection
                if let fiveHourProj = proj?.fiveHour, fiveHourProj.count >= 2 {
                    ForEach(Array(fiveHourProj.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("5h Projected", point.value)
                        )
                        .foregroundStyle(Color.blue.opacity(0.4))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }

                // 7-day confidence band
                if let band = proj?.sevenDayBand, band.count >= 2 {
                    ForEach(Array(band.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Low", point.low),
                            yEnd: .value("High", point.high)
                        )
                        .foregroundStyle(Color.purple.opacity(0.08))
                        .interpolationMethod(.monotone)
                    }
                }

                // 7-day projection line
                if let sevenDayProj = proj?.sevenDay, sevenDayProj.count >= 2 {
                    ForEach(Array(sevenDayProj.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("7d Projected", point.value)
                        )
                        .foregroundStyle(Color.purple.opacity(0.4))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }

                // Target curve
                if !targetCurvePoints.isEmpty {
                    ForEach(Array(targetCurvePoints.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Target", point.value)
                        )
                        .foregroundStyle(Color.green.opacity(0.5))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }

                // 7-day reset marker
                if let resetDate = sevenDayResetInRange {
                    RuleMark(x: .value("Reset", resetDate))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.purple.opacity(0.5))
                        .annotation(position: .topLeading, spacing: 4) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("7d Reset")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.purple)
                                if let projected = projectedAtReset {
                                    Text(String(format: "%.0f%%", projected))
                                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.purple.opacity(0.7))
                                }
                                if let pattern = projection?.patternProjection, pattern.isPatternAware {
                                    Text(String(format: "%.0f–%.0f%%", pattern.optimisticAtReset, pattern.pessimisticAtReset))
                                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.purple.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }

                    if let projected = projectedAtReset {
                        PointMark(
                            x: .value("Reset", resetDate),
                            y: .value("Projected", projected)
                        )
                        .foregroundStyle(.purple.opacity(0.6))
                        .symbolSize(40)
                        .symbol(.diamond)
                    }
                }

                // Now marker
                if now >= dateRange.lowerBound && now <= dateRange.upperBound {
                    RuleMark(x: .value("Now", now))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.3))
                }

                // Hover
                if let date = hoverDate {
                    RuleMark(x: .value("Hover", date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary.opacity(0.6))

                    if let snap = nearestSnapshot(to: date) {
                        PointMark(
                            x: .value("Time", snap.timestamp),
                            y: .value("5h", snap.fiveHourUtilization)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(30)

                        PointMark(
                            x: .value("Time", snap.timestamp),
                            y: .value("7d", snap.sevenDayUtilization)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(30)
                    }
                }
            }
            .chartYScale(domain: 0...max(peakUtilization * 1.1, 10))
            .chartYAxisLabel("Usage %")
            .chartYAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartForegroundStyleScale([
                "5-Hour": Color.blue,
                "7-Day": Color.purple,
            ])
        )
        .overlay(alignment: .topLeading) {
            if let date = hoverDate, let snap = nearestSnapshot(to: date) {
                usageTooltip(snap: snap)
                    .padding(8)
            }
        }
    }

    private func usageTooltip(snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snap.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(.caption2.weight(.semibold))
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text(String(format: "5h: %.1f%%", snap.fiveHourUtilization))
                        .font(.caption2.monospacedDigit())
                }
                HStack(spacing: 3) {
                    Circle().fill(.purple).frame(width: 6, height: 6)
                    Text(String(format: "7d: %.1f%%", snap.sevenDayUtilization))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var usageStats: some View {
        HStack(spacing: 16) {
            if !filteredSnapshots.isEmpty {
                statItem(
                    "Peak 5H",
                    value: String(format: "%.1f%%", filteredSnapshots.map(\.fiveHourUtilization).max() ?? 0),
                    color: .blue
                )
                statItem(
                    "Peak 7D",
                    value: String(format: "%.1f%%", filteredSnapshots.map(\.sevenDayUtilization).max() ?? 0),
                    color: .purple
                )
            }
        }
    }

    // MARK: - Shared Helpers

    private func statItem(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Scroll Wheel

private extension View {
    func onScrollWheel(_ handler: @escaping (CGPoint) -> Void) -> some View {
        overlay {
            ScrollWheelView(onScroll: handler)
        }
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let onScroll: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private class ScrollWheelNSView: NSView {
    var onScroll: ((CGPoint) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > 0.1 || abs(dy) > 0.1 else {
            super.scrollWheel(with: event)
            return
        }
        onScroll?(CGPoint(x: dx, y: dy))
    }
}
