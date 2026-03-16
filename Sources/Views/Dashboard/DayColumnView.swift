import SwiftUI

struct DayColumnView: View {
    let weekday: Int
    @Binding var slot: DaySlot
    let isEnabled: Bool
    let isToday: Bool
    let dayColor: Color
    let dayBoundary: Int
    let onChanged: () -> Void

    // Local drag state — prevents parent re-renders during drag
    @State private var dragEdge: DragEdge?
    @State private var editingStartHour: Int?
    @State private var editingEndHour: Int?

    private enum DragEdge {
        case top, bottom
    }

    private let handleZone: CGFloat = 14

    /// The start hour to display (in-progress drag or committed).
    private var displayStartHour: Int { editingStartHour ?? slot.startHour }
    /// The end hour to display (in-progress drag or committed).
    private var displayEndHour: Int { editingEndHour ?? slot.endHour }
    /// Active hours for the displayed state.
    private var displayActiveHours: Double {
        let s = displayStartHour
        let e = displayEndHour
        guard e != s else { return 0 }
        return e > s ? Double(e - s) : Double(24 - s + e)
    }

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.weekdaySymbols[(weekday - 1) % 7]
    }

    var body: some View {
        GeometryReader { geo in
            let totalHours = 24
            let unitHeight = geo.size.height / CGFloat(totalHours)

            ZStack(alignment: .top) {
                gridLines(totalHours: totalHours, unitHeight: unitHeight)

                if isEnabled && slot.isActive {
                    slotBlock(unitHeight: unitHeight, totalHours: totalHours, columnWidth: geo.size.width)
                } else if isEnabled && !slot.isActive {
                    dayOffOverlay(unitHeight: unitHeight, totalHours: totalHours)
                }

                if isToday {
                    currentTimeIndicator(unitHeight: unitHeight)
                }
            }
            .coordinateSpace(name: "dayColumn\(weekday)")
            .contentShape(Rectangle())
            .highPriorityGesture(columnDragGesture(unitHeight: unitHeight))
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slot.isActive
            ? "\(dayName), active \(DateFormatting.formatHourShort(displayStartHour)) to \(DateFormatting.formatHourShort(displayEndHour)), \(Int(displayActiveHours)) hours"
            : "\(dayName), day off")
    }

    // MARK: - Grid

    private func gridLines(totalHours: Int, unitHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<totalHours, id: \.self) { _ in
                Rectangle()
                    .fill(.quaternary.opacity(0.3))
                    .frame(height: unitHeight)
                    .overlay(alignment: .top) {
                        Divider()
                    }
            }
        }
    }

    // MARK: - Day Off Overlay

    private func dayOffOverlay(unitHeight: CGFloat, totalHours: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(.quaternary.opacity(0.08))
                .frame(height: CGFloat(totalHours) * unitHeight)

            VStack(spacing: 4) {
                Image(systemName: "moon.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.3))
                Text("Off")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.3))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    // MARK: - Slot Block

    private func slotBlock(unitHeight: CGFloat, totalHours: Int, columnWidth: CGFloat) -> some View {
        let startOffset = hourOffset(from: displayStartHour)
        let yOffset = CGFloat(startOffset) * unitHeight
        let hours = displayActiveHours
        let blockHeight = CGFloat(hours) * unitHeight
        let isDragging = dragEdge != nil

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(dayColor.gradient.opacity(isDragging ? 0.5 : 0.4))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(dayColor.opacity(isDragging ? 0.9 : 0.6), lineWidth: isDragging ? 2 : 1)
                }
                .overlay {
                    VStack(spacing: 2) {
                        Text(DateFormatting.formatHourShort(displayStartHour))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                        if blockHeight > 40 {
                            Text("\(Int(displayActiveHours))h")
                                .font(.caption2.weight(.bold))
                        }
                        if blockHeight > 56 {
                            Text(DateFormatting.formatHourShort(displayEndHour))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                        }
                    }
                    .foregroundStyle(dayColor)
                }

            // Top drag handle
            VStack {
                dragHandle(edge: .top)
                Spacer()
            }

            // Bottom drag handle
            VStack {
                Spacer()
                dragHandle(edge: .bottom)
            }
        }
        .frame(height: blockHeight)
        .offset(y: yOffset)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.interactiveSpring(duration: 0.15), value: displayStartHour)
        .animation(.interactiveSpring(duration: 0.15), value: displayEndHour)
    }

    /// Drag gesture attached to the full column, using column-relative coordinates.
    /// Uses local state during drag to prevent parent re-renders — only writes to
    /// the binding on .onEnded, fixing the bug where dragging one column broke others.
    func columnDragGesture(unitHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("dayColumn\(weekday)"))
            .onChanged { value in
                guard isEnabled, slot.isActive else { return }

                if dragEdge == nil {
                    let startY = value.startLocation.y
                    let topEdgeY = CGFloat(hourOffset(from: slot.startHour)) * unitHeight
                    let bottomEdgeY = topEdgeY + CGFloat(slot.activeHours) * unitHeight

                    if abs(startY - topEdgeY) < handleZone {
                        dragEdge = .top
                        editingStartHour = slot.startHour
                    } else if abs(startY - bottomEdgeY) < handleZone {
                        dragEdge = .bottom
                        editingEndHour = slot.endHour
                    } else {
                        return
                    }
                }

                let currentY = value.location.y
                let snappedOffset = Int(round(currentY / unitHeight))
                let snappedHour = clampHour(dayBoundary + snappedOffset)

                switch dragEdge {
                case .top:
                    let endH = editingEndHour ?? slot.endHour
                    if snappedHour != endH {
                        editingStartHour = snappedHour
                    }
                case .bottom:
                    let startH = editingStartHour ?? slot.startHour
                    if snappedHour != startH {
                        editingEndHour = snappedHour
                    }
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if let start = editingStartHour {
                    slot.startHour = start
                }
                if let end = editingEndHour {
                    slot.endHour = end
                }
                dragEdge = nil
                editingStartHour = nil
                editingEndHour = nil
                onChanged()
            }
    }

    private func dragHandle(edge: DragEdge) -> some View {
        Capsule()
            .fill(dayColor.opacity(dragEdge == edge ? 1.0 : 0.8))
            .frame(width: 20, height: 3)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity)
            .frame(height: handleZone)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    // MARK: - Current Time

    private func currentTimeIndicator(unitHeight: CGFloat) -> some View {
        let cal = Calendar.current
        let now = Date.now
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let offset = hourOffset(from: hour)
        let nowOffset = CGFloat(offset) * unitHeight + CGFloat(minute) / 60 * unitHeight

        return HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
        .offset(y: nowOffset - 3)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Helpers

    private func hourOffset(from hour: Int) -> Int {
        if hour >= dayBoundary {
            return hour - dayBoundary
        } else {
            return 24 - dayBoundary + hour
        }
    }

    private func clampHour(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24
    }
}
