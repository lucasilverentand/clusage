import Testing
import Foundation
@testable import Clusage

@Suite("PaceCalculation")
struct PaceCalculationTests {
    @Test("On pace when utilization matches elapsed fraction")
    func onPace() {
        let window = UsageWindow(
            utilization: 50.0,
            resetsAt: Date().addingTimeInterval(2.5 * 3600),
            duration: UsageWindow.fiveHourDuration
        )
        let pace = PaceCalculation(window: window)
        #expect(abs(pace.delta) < 1)
        #expect(pace.description == "On pace")
    }

    @Test("Overpacing when usage exceeds expected")
    func overpacing() {
        let window = UsageWindow(
            utilization: 80.0,
            resetsAt: Date().addingTimeInterval(4 * 3600),
            duration: UsageWindow.fiveHourDuration
        )
        let pace = PaceCalculation(window: window)
        #expect(pace.isOverpacing)
        #expect(pace.delta > 0)
    }

    @Test("Underpacing when usage is below expected")
    func underpacing() {
        let window = UsageWindow(
            utilization: 10.0,
            resetsAt: Date().addingTimeInterval(1 * 3600),
            duration: UsageWindow.fiveHourDuration
        )
        let pace = PaceCalculation(window: window)
        #expect(pace.isUnderpacing)
        #expect(pace.delta < 0)
    }
}
