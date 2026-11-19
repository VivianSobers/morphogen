import XCTest
import Metal
import CoreGraphics
import ImageIO
@testable import MorphogenCore

final class SimulatorTests: XCTestCase {
  private func makeSim(w: Int = 128, h: Int = 128, p: Preset = Preset.named("coral")!, s: UInt32 = 1) throws -> Simulator {
    guard let d = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal GPU available") }
    return try Simulator(width: w, height: h, preset: p, seed: s, device: d)
  }

  func testShadersCompile() throws {
    guard let d = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal GPU available") }
    let lib = try makeShaderLibrary(device: d)
    for name in ["seed_field", "gray_scott_step", "field_stats", "colorize"] {
      XCTAssertNotNil(lib.makeFunction(name: name))
    }
  }

  func testSeedStatsInRange() throws {
    let s = try makeSim().stats()
    XCTAssertGreaterThanOrEqual(s.minV, 0); XCTAssertLessThanOrEqual(s.maxV, 1); XCTAssertGreaterThan(s.maxV, 0.2)
  }

  func testStepIsDeterministic() throws {
    let (s1, s2) = (try makeSim(s: 7), try makeSim(s: 7))
    s1.step(500); s2.step(500)
    XCTAssertEqual(s1.stats(), s2.stats())
  }

  func testDifferentSeedsDiffer() throws {
    let (s1, s2) = (try makeSim(s: 7), try makeSim(s: 8))
    XCTAssertNotEqual(s1.stats().meanV, s2.stats().meanV)
  }

  func testEveryPresetFormsPattern() throws {
    for p in Preset.all {
      let sim = try makeSim(w: 256, h: 256, p: p, s: 42)
      sim.step(min(p.steps, 4000))
      let s = sim.stats()
      XCTAssertGreaterThan(s.maxV - s.minV, 0.15)
      XCTAssertGreaterThan(s.meanV, 0.01); XCTAssertLessThan(s.meanV, 0.6)
    }
  }

  func testRenderSize() throws {
    let sim = try makeSim()
    let (img1, img2) = (try sim.render(palette: "coral"), try sim.render(palette: "coral", outputWidth: 64, outputHeight: 64))
    XCTAssertEqual(img1.width, 128); XCTAssertEqual(img1.height, 128)
    XCTAssertEqual(img2.width, 64); XCTAssertEqual(img2.height, 64)
  }

  func testOddSizeFullyWritten() throws {
    for (w, h) in [(100, 100), (333, 97)] {
      let sim = try makeSim(w: w, h: h)
      sim.step(200)
      let img = try sim.render(palette: "ocean")
      let data = img.dataProvider!.data! as Data
      for i in stride(from: 3, to: data.count, by: 4) { XCTAssertEqual(data[i], 255) }
    }
  }

  func testRenderNotUniform() throws {
    let sim = try makeSim()
    sim.step(1500)
    let img = try sim.render(palette: "coral")
    let data = img.dataProvider!.data! as Data
    var sum: Double = 0, sqSum: Double = 0, n: Double = 0
    for i in stride(from: 0, to: data.count, by: 4) {
      let r = Double(data[i]), g = Double(data[i+1]), b = Double(data[i+2])
      let lum = 0.299 * r + 0.587 * g + 0.114 * b
      sum += lum; sqSum += lum * lum; n += 1
    }
    let mean = sum / n
    XCTAssertGreaterThan(sqrt(sqSum / n - mean * mean), 10.0)
  }

  func testRenderDeterministic() throws {
    let (s1, s2) = (try makeSim(s: 42), try makeSim(s: 42))
    s1.step(200); s2.step(200)
    let d1 = try s1.render(palette: "coral").dataProvider!.data! as Data
    let d2 = try s2.render(palette: "coral").dataProvider!.data! as Data
    XCTAssertEqual(d1, d2)
  }

  func testUnknownPaletteThrows() throws {
    XCTAssertThrowsError(try makeSim().render(palette: "plaid")) { XCTAssertEqual($0 as? MorphogenError, .unknownPalette("plaid")) }
  }

  func testWritePNGRoundTrip() throws {
    let img = try makeSim(w: 64, h: 64).render(palette: "coral")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).png")
    let desc = "preset=coral size=64x64"
    try writePNG(img, to: url, description: desc)
    defer { try? FileManager.default.removeItem(at: url) }

    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let readImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { XCTFail(); return }
    XCTAssertEqual(readImg.width, 64); XCTAssertEqual(readImg.height, 64)
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let pngProps = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
    XCTAssertEqual(pngProps?[kCGImagePropertyPNGDescription] as? String, desc)
  }

  func testWritePNGMissingDirectoryThrows() throws {
    let img = try makeSim(w: 32, h: 32).render(palette: "mono")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent_\(UUID().uuidString)/out.png")
    XCTAssertThrowsError(try writePNG(img, to: url, description: "test")) { err in
      guard case MorphogenError.io = err else { XCTFail(); return }
    }
  }

  func testWriteGIFFrameCount() throws {
    let sim = try makeSim(w: 32, h: 32)
    var frames = [try sim.render(palette: "ocean")]
    sim.step(50); frames.append(try sim.render(palette: "ocean"))
    sim.step(50); frames.append(try sim.render(palette: "ocean"))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).gif")
    try writeGIF(frames, to: url, frameDelay: 0.05)
    defer { try? FileManager.default.removeItem(at: url) }

    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { XCTFail(); return }
    XCTAssertEqual(CGImageSourceGetCount(src), 3)
  }

  private func luminance(_ img: CGImage) -> [Double] {
    let data = img.dataProvider!.data! as Data
    return stride(from: 0, to: data.count, by: 4).map {
      0.299 * Double(data[$0]) + 0.587 * Double(data[$0 + 1]) + 0.114 * Double(data[$0 + 2])
    }
  }

  func testFlatRenderSpansWholePalette() throws {
    let sim = try makeSim()
    sim.step(1500)
    let lum = luminance(try sim.render(palette: "mono", style: .flat))
    XCTAssertLessThan(lum.min()!, 20)
    XCTAssertGreaterThan(lum.max()!, 235)
  }

  func testStylesDiffer() throws {
    let sim = try makeSim()
    sim.step(1500)
    let images = try RenderStyle.allCases.map { try sim.render(palette: "coral", style: $0).dataProvider!.data! as Data }
    XCTAssertEqual(Set(images).count, RenderStyle.allCases.count)
  }
}
