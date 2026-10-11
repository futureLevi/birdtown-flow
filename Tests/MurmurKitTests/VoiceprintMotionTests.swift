import Testing
@testable import MurmurKit

@Suite("VoiceprintMotion")
struct VoiceprintMotionTests {
    typealias Motion = VoiceprintMotion

    @Test("A sweep crosses from under the greeting to the right edge, then rests")
    func sweepTravels() {
        #expect(Motion.bandCenter(at: 0) == Motion.bandStartX)
        #expect(Motion.bandCenter(at: Motion.sweepDuration / 2) == (Motion.bandStartX + Motion.bandEndX) / 2)
        #expect(Motion.bandCenter(at: -0.1) == nil)
        #expect(Motion.bandCenter(at: Motion.sweepDuration) == nil)
        #expect(Motion.restDuration == Motion.sweepInterval - Motion.sweepDuration)
    }

    @Test("The band is brightest at its centre and fades out within a few sigma")
    func bandShape() {
        let t = Motion.sweepDuration / 2
        let center = Motion.bandCenter(at: t)!
        #expect(Motion.sheen(x: center, sweepTime: t) == 1)
        #expect(Motion.sheen(x: center + Motion.bandSigma, sweepTime: t) < 0.4)
        #expect(Motion.sheen(x: center + 3 * Motion.bandSigma, sweepTime: t) < 0.001)
        // Between sweeps nothing is lit.
        #expect(Motion.sheen(x: center, sweepTime: Motion.sweepDuration + 1) == 0)
    }

    @Test("Lines grow by at most the lift")
    func heightLift() {
        #expect(Motion.heightFactor(sheen: 0) == 1)
        #expect(abs(Motion.heightFactor(sheen: 1) - 1.045) < 1e-9)
    }

    @Test("The opening rises left to right and is done after its duration")
    func opening() {
        let first = Motion.openingStartX
        let last = Motion.openingStartX + Motion.openingSpanX
        #expect(Motion.opening(x: first, at: 0) == 0)
        #expect(Motion.opening(x: last, at: Motion.openingStagger) == 0)
        #expect(Motion.opening(x: first, at: 0.4) > Motion.opening(x: last, at: 0.4))
        #expect(Motion.opening(x: first, at: Motion.openingDuration) == 1)
        #expect(Motion.opening(x: last, at: Motion.openingDuration) == 1)
        #expect(abs(Motion.openingDuration - 1.4) < 1e-9)
    }
}
