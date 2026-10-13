import Testing
@testable import MurmurKit

@Suite("QuietRelease")
struct QuietReleaseTests {
    @Test("An item is held for the quiet period, then released")
    func releasedAfterQuietPeriod() {
        var list = QuietRelease<Int, String>(quietPeriod: 3)
        list.retire("engine", key: 1, at: 10)
        let due = list.nextDue
        let early = list.takeQuiet(at: 12.9)
        let stillHeld = list.isHolding(1)
        let onTime = list.takeQuiet(at: 13)
        #expect(due == 13)
        #expect(early.isEmpty)
        #expect(stillHeld)
        #expect(onTime == ["engine"])
        #expect(list.isEmpty)
        #expect(list.nextDue == nil)
    }

    @Test("Activity restarts the quiet period")
    func activityRestartsPeriod() {
        var list = QuietRelease<Int, String>(quietPeriod: 3)
        list.retire("engine", key: 1, at: 0)
        let noted = list.noteActivity(key: 1, at: 2)
        let due = list.nextDue
        let early = list.takeQuiet(at: 3)
        let onTime = list.takeQuiet(at: 5)
        #expect(noted)
        #expect(due == 5)
        #expect(early.isEmpty)
        #expect(onTime == ["engine"])
    }

    @Test("Activity for something not held is ignored")
    func unknownActivity() {
        var list = QuietRelease<Int, String>(quietPeriod: 3)
        let noted = list.noteActivity(key: 7, at: 1)
        #expect(!noted)
        #expect(list.isEmpty)
    }

    @Test("An out-of-order earlier time never shortens the period")
    func earlierActivityIgnored() {
        var list = QuietRelease<Int, String>(quietPeriod: 3)
        list.retire("engine", key: 1, at: 10)
        list.noteActivity(key: 1, at: 4)
        #expect(list.nextDue == 13)
    }

    @Test("Each item keeps its own period; only quiet ones are released, oldest first")
    func independentItems() {
        var list = QuietRelease<Int, String>(quietPeriod: 3)
        list.retire("b", key: 2, at: 1)
        list.retire("a", key: 1, at: 0)
        list.retire("c", key: 3, at: 2)
        list.noteActivity(key: 3, at: 4)
        let firstDue = list.nextDue
        let first = list.takeQuiet(at: 4.5)
        let remaining = list.count
        let secondDue = list.nextDue
        let second = list.takeQuiet(at: 7)
        #expect(firstDue == 3)
        #expect(first == ["a", "b"])
        #expect(remaining == 1)
        #expect(secondDue == 7)
        #expect(second == ["c"])
    }
}
