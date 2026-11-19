import XCTest
import Metal
import CoreGraphics
import ImageIO
@testable import MorphogenCore

final class SimulatorTests: XCTestCase {
    private func makeSim(width: Int = 128, height: Int = 128, preset: Preset = Preset.named("coral")!, seed: UInt32 = 1, feed: Float? = nil, kill: Float? = nil) throws -> Simulator {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal GPU available") }
        return try Simulator(width: width, height: height, preset: preset, seed: seed, feed: feed, kill: kill, device: device)
    }

    func testShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal GPU available") }
        let lib = try makeShaderLibrary(device: device)
        XCTAssertNotNil(lib.makeFunction(name: "seed_field"))
        XCTAssertNotNil(lib.makeFunction(name: "gray_scott_step"))
        XCTAssertNotNil(lib.makeFunction(name: "field_stats"))
        XCTAssertNotNil(lib.makeFunction(name: "colorize"))
    }

    func testSeedStatsInRange() throws {
        let sim = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 1)
        let s = sim.stats()
        XCTAssertGreaterThanOrEqual(s.minV, 0); XCTAssertLessThanOrEqual(s.maxV, 1); XCTAssertGreaterThan(s.maxV, 0.2)
    }

    func testStepIsDeterministic() throws {
        let sim1 = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 7)
        let sim2 = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 7)
        sim1.step(500); sim2.step(500)
        XCTAssertEqual(sim1.stats(), sim2.stats())
    }

    func testDifferentSeedsDiffer() throws {
        let sim1 = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 7)
        let sim2 = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 8)
        XCTAssertNotEqual(sim1.stats().meanV, sim2.stats().meanV)
    }

    func testEveryPresetFormsPattern() throws {
        for p in Preset.all {
            let sim = try makeSim(width: 256, height: 256, preset: p, seed: 42)
            sim.step(min(p.steps, 4000))
            let s = sim.stats()
            XCTAssertGreaterThan(s.maxV - s.minV, 0.15)
            XCTAssertGreaterThan(s.meanV, 0.01); XCTAssertLessThan(s.meanV, 0.6)
        }
    }

    func testRenderSize() throws {
        let sim = try makeSim(width: 128, height: 128)
        let img1 = try sim.render(palette: "coral")
        XCTAssertEqual(img1.width, 128); XCTAssertEqual(img1.height, 128)
        let img2 = try sim.render(palette: "coral", outputWidth: 64, outputHeight: 64)
        XCTAssertEqual(img2.width, 64); XCTAssertEqual(img2.height, 64)
    }

    func testOddSizeFullyWritten() throws {
        for (w, h) in [(100, 100), (333, 97)] {
            let sim = try makeSim(width: w, height: h)
            sim.step(200)
            let img = try sim.render(palette: "ocean")
            guard let data = img.dataProvider?.data as Data? else { XCTFail(); return }
            for i in stride(from: 3, to: data.count, by: 4) {
                XCTAssertEqual(data[i], 255)
            }
        }
    }

    func testRenderNotUniform() throws {
        let sim = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!)
        sim.step(1500)
        let img = try sim.render(palette: "coral")
        guard let data = img.dataProvider?.data as Data? else { XCTFail(); return }
        var sum: Double = 0, sqSum: Double = 0, count: Double = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Double(data[i]), g = Double(data[i+1]), b = Double(data[i+2])
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            sum += lum; sqSum += lum * lum; count += 1
        }
        let mean = sum / count
        let stdDev = sqrt(sqSum / count - mean * mean)
        XCTAssertGreaterThan(stdDev, 10.0)
    }

    func testRenderDeterministic() throws {
        let sim1 = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 42)
        let sim2 = try makeSim(width: 128, height: 128, preset: Preset.named("coral")!, seed: 42)
        sim1.step(200); sim2.step(200)
        let img1 = try sim1.render(palette: "coral")
        let img2 = try sim2.render(palette: "coral")
        XCTAssertEqual(img1.dataProvider?.data as Data?, img2.dataProvider?.data as Data?)
    }

    func testUnknownPaletteThrows() throws {
        let sim = try makeSim()
        XCTAssertThrowsError(try sim.render(palette: "plaid")) { error in
            XCTAssertEqual(error as? MorphogenError, .unknownPalette("plaid"))
        }
    }

    func testWritePNGRoundTrip() throws {
        let sim = try makeSim(width: 64, height: 64)
        let img = try sim.render(palette: "coral")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).png")
        let desc = "preset=coral size=64x64"
        try writePNG(img, to: url, description: desc)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let readImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            XCTFail("Failed to read PNG back"); return
        }
        XCTAssertEqual(readImg.width, 64)
        XCTAssertEqual(readImg.height, 64)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let pngProps = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let readDesc = pngProps?[kCGImagePropertyPNGDescription] as? String
        XCTAssertEqual(readDesc, desc)
    }

    func testWritePNGMissingDirectoryThrows() throws {
        let sim = try makeSim(width: 32, height: 32)
        let img = try sim.render(palette: "mono")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent_\(UUID().uuidString)/out.png")
        XCTAssertThrowsError(try writePNG(img, to: url, description: "test")) { err in
            guard case MorphogenError.io = err else {
                XCTFail("Expected MorphogenError.io, got \(err)")
                return
            }
        }
    }

    func testWriteGIFFrameCount() throws {
        let sim = try makeSim(width: 32, height: 32)
        let frame1 = try sim.render(palette: "ocean")
        sim.step(50)
        let frame2 = try sim.render(palette: "ocean")
        sim.step(50)
        let frame3 = try sim.render(palette: "ocean")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).gif")
        try writeGIF([frame1, frame2, frame3], to: url, frameDelay: 0.05)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            XCTFail("Failed to read GIF back"); return
        }
        XCTAssertEqual(CGImageSourceGetCount(src), 3)
    }
}
