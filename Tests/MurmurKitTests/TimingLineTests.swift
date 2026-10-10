import Foundation
import Testing
@testable import MurmurKit

@Suite("TimingLine")
struct TimingLineTests {
    @Test("A line with no fields is its label")
    func labelOnly() {
        #expect(TimingLine("dictation 3F2A9C1B").text == "dictation 3F2A9C1B")
    }

    @Test("Fields keep the order they were added in, with their units")
    func formatting() {
        var line = TimingLine("dictation")
        line.seconds("audio", 372.44)
        line.ms("stop", 11)
        line.count("windows", 31)
        line.tag("path", "segmentedLive")
        #expect(line.text == "dictation audio=372.4s stop=11ms windows=31 path=segmentedLive")
    }

    @Test("Seconds round to a tenth")
    func secondsRounding() {
        var line = TimingLine("x")
        line.seconds("a", 0)
        line.seconds("b", 9.96)
        line.seconds("c", 1.04)
        #expect(line.text == "x a=0.0s b=10.0s c=1.0s")
    }

    @Test("A stage that didn't run is left out")
    func nilOmitted() {
        var line = TimingLine("x")
        line.ms("liveStop", nil)
        line.ms("wav", 86)
        line.ms("engineWait", nil)
        #expect(line.text == "x wav=86ms")
    }

    @Test("A group carries the inner fields without the inner label")
    func group() {
        var inner = TimingLine("transcribe")
        inner.count("windows", 2)
        inner.ms("tail", 298)
        var line = TimingLine("dictation")
        line.ms("transcribe", 612)
        line.group("transcribe", inner)
        line.ms("total", 700)
        #expect(line.text == "dictation transcribe=612ms transcribe(windows=2 tail=298ms) total=700ms")
    }

    @Test("An empty group adds nothing")
    func emptyGroup() {
        var line = TimingLine("dictation")
        line.group("polish", TimingLine("polish"))
        #expect(line.text == "dictation")
    }

    @Test("Equal lines compare equal")
    func equality() {
        var a = TimingLine("x")
        var b = TimingLine("x")
        a.ms("k", 1)
        #expect(a != b)
        b.ms("k", 1)
        #expect(a == b)
    }
}
