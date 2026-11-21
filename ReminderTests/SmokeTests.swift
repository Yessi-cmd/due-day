import Foundation
import Testing
@testable import Reminder

@Suite("Smoke")
struct SmokeTests {
    @Test("Bundle exposes version and build")
    func bundleVersion() {
        #expect(AppInfo.version != "—")
        #expect(AppInfo.build != "—")
    }

    @Test("Foundation calendars needed by the app are available")
    func calendarsAvailable() {
        let gregorian = Calendar(identifier: .gregorian)
        let chinese = Calendar(identifier: .chinese)
        #expect(gregorian.identifier == .gregorian)
        #expect(chinese.identifier == .chinese)
    }
}
