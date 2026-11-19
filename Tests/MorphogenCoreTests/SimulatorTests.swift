import XCTest
import Metal
@testable import MorphogenCore

final class SimulatorTests: XCTestCase {
    private func makeSim(width: Int = 128, height: Int = 128, preset: Preset = Preset.named("coral")!, seed: UInt32 = 1, feed: Float? = nil, kill: Float? = nil) throws -> Simulator {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal GPU available")
        }
        return try Simulator(width: width, height: height, preset: preset, seed: seed, feed: feed, kill: kill, device: device)
    }

    func testShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal GPU available")
        }
        let library = try makeShaderLibrary(device: device)
        XCTAssertNotNil(library.makeFunction(name: "seed_field"))
        XCTAssertNotNil(library.makeFunction(name: "gray_scott_step"))
        XCTAssertNotNil(library.makeFunction(name: "field_stats"))
    }

    func testSeedStatsInRange() throws {
        let sim = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 1)
        let s = sim.stats()
        XCTAssertGreaterThanOrEqual(s.minV, 0)
        XCTAssertLessThanOrEqual(s.maxV, 1)
        XCTAssertGreaterThan(s.maxV, 0.2)
    }

    func testStepIsDeterministic() throws {
        let preset = Preset.named("coral")!
        let sim1 = try makeSim(width: 128, height: 128, preset: preset, seed: 7)
        let sim2 = try makeSim(width: 128, height: 128, preset: preset, seed: 7)
        sim1.step(500)
        sim2.step(500)
        XCTAssertEqual(sim1.stats(), sim2.stats())
    }

    func testDifferentSeedsDiffer() throws {
        let preset = Preset.named("coral")!
        let sim1 = try makeSim(width: 128, height: 128, preset: preset, seed: 7)
        let sim2 = try makeSim(width: 128, height: 128, preset: preset, seed: 8)
        XCTAssertNotEqual(sim1.stats().meanV, sim2.stats().meanV)
    }

    func testEveryPresetFormsPattern() throws {
        for preset in Preset.all {
            let sim = try makeSim(width: 256, height: 256, preset: preset, seed: 42)
            sim.step(min(preset.steps, 4000))
            let s = sim.stats()
            let diff = s.maxV - s.minV
            XCTAssertGreaterThan(diff, 0.15, "Preset \(preset.name) failed max-min range")
            XCTAssertGreaterThan(s.meanV, 0.01, "Preset \(preset.name) failed min mean")
            XCTAssertLessThan(s.meanV, 0.6, "Preset \(preset.name) failed max mean")
        }
    }
}
