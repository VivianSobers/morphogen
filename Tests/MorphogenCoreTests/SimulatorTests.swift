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
      sim.step(p.steps)  // the preset's own run: small time steps need many steps
      let s = sim.stats()
      XCTAssertTrue(s.minV.isFinite && s.maxV.isFinite && s.meanV.isFinite, "\(p.name) blew up")
      // Relative spread, since each model's displayed chemical has its own scale.
      XCTAssertGreaterThan(s.maxV - s.minV, 0.15 * max(abs(s.maxV), 1e-3), "\(p.name) is uniform")
    }
  }

  func testEveryModelHasAPreset() {
    for model in Model.allCases {
      XCTAssertTrue(Preset.all.contains { $0.model == model }, "\(model) has no preset")
    }
  }

  func testPerturbedSeedStartsAtSteadyState() throws {
    // Brusselator's uniform state is u = A (displayed), v = B / A.
    let brusselator = Preset.all.first { $0.model == .brusselator }!
    let s = try makeSim(w: 128, h: 128, p: brusselator, s: 3).stats()
    XCTAssertEqual(s.meanV, brusselator.constants[0], accuracy: 0.05 * brusselator.constants[0])
    XCTAssertGreaterThan(s.maxV, s.minV)
  }

  func testSpiralsKeepTurning() throws {
    // Turing patterns settle; excitable spirals never do.
    let spiral = Preset.all.first { $0.model == .barkley }!
    let sim = try makeSim(w: 256, h: 256, p: spiral, s: 9)
    sim.step(3000)
    let before = luminance(try sim.render(palette: "mono", style: .flat))
    sim.step(300)
    let after = luminance(try sim.render(palette: "mono", style: .flat))
    let change = zip(before, after).map { abs($0 - $1) }.reduce(0, +) / Double(before.count)
    XCTAssertGreaterThan(change, 20)
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
    let lum = luminance(try sim.render(palette: "coral"))
    let mean = lum.reduce(0, +) / Double(lum.count)
    let variance = lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)
    XCTAssertGreaterThan(variance.squareRoot(), 10.0)
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

  // Total brightness change between each pixel and its neighbour at (dx, dy).
  private func gradient(_ img: CGImage, dx: Int, dy: Int) -> Double {
    let lum = luminance(img), w = img.width, h = img.height
    var total = 0.0
    for y in max(0, -dy)..<(h - max(0, dy)) {
      for x in max(0, -dx)..<(w - max(0, dx)) {
        total += abs(lum[(y + dy) * w + x + dx] - lum[y * w + x])
      }
    }
    return total
  }

  func testFlowAlignsStripes() throws {
    let horizontal = Preset(name: "h", feed: 0.037, kill: 0.06, seedShape: .noise, steps: 4000,
                            palette: "mono", summary: "", flowAngle: 0)
    let sim = try makeSim(w: 256, h: 256, p: horizontal, s: 5)
    sim.step(4000)
    let img = try sim.render(palette: "mono", style: .flat)
    XCTAssertGreaterThan(gradient(img, dx: 0, dy: 1), 2 * gradient(img, dx: 1, dy: 0), "stripes should run along x")
  }

  func testFlowAngleRotatesStripes() throws {
    let vertical = Preset(name: "v", feed: 0.037, kill: 0.06, seedShape: .noise, steps: 4000,
                          palette: "mono", summary: "", flowAngle: 90)
    let sim = try makeSim(w: 256, h: 256, p: vertical, s: 5)
    sim.step(4000)
    let img = try sim.render(palette: "mono", style: .flat)
    XCTAssertGreaterThan(gradient(img, dx: 1, dy: 0), 2 * gradient(img, dx: 0, dy: 1), "stripes should run along y")
  }

  func testDiagonalFlowFollowsAngle() throws {
    // 45 degrees in image coordinates (y down) points down-right.
    let diagonal = Preset(name: "d", feed: 0.037, kill: 0.06, seedShape: .noise, steps: 4000,
                          palette: "mono", summary: "", flowAngle: 45)
    let sim = try makeSim(w: 256, h: 256, p: diagonal, s: 5)
    sim.step(4000)
    let img = try sim.render(palette: "mono", style: .flat)
    XCTAssertGreaterThan(gradient(img, dx: 1, dy: -1), 1.5 * gradient(img, dx: 1, dy: 1), "stripes should run down-right")
  }

  func testFrameScheduleSumsToTotal() {
    for (total, frames) in [(10000, 120), (7, 3), (120, 120), (1000, 7)] {
      let schedule = frameSchedule(totalSteps: total, frames: frames)
      XCTAssertEqual(schedule.count, frames)
      XCTAssertEqual(schedule.reduce(0, +), total)
      XCTAssertLessThanOrEqual(schedule.max()! - schedule.min()!, 1)
    }
  }

  func testDownscaleAveragesInsteadOfAliasing() throws {
    // Fine vertical stripes, a few cells wide: point sampling at 1/4 size aliases them.
    let stripes = Preset(name: "s", feed: 0.030, kill: 0.057, seedShape: .noise, steps: 3000,
                         palette: "mono", summary: "", flowAngle: 90)
    let sim = try makeSim(w: 256, h: 256, p: stripes, s: 5)
    sim.step(3000)
    let full = luminance(try sim.render(palette: "mono", style: .flat))
    let small = luminance(try sim.render(palette: "mono", style: .flat, outputWidth: 64, outputHeight: 64))

    // Reference: average each 4x4 block of the full-size render.
    var error = 0.0
    for y in 0..<64 {
      for x in 0..<64 {
        var block = 0.0
        for dy in 0..<4 { for dx in 0..<4 { block += full[(y * 4 + dy) * 256 + x * 4 + dx] } }
        error += abs(block / 16 - small[y * 64 + x])
      }
    }
    XCTAssertLessThan(error / 4096, 12, "downscaled pixels should average the cells they cover")
  }

  func testPhaseStyleCyclesThroughHues() throws {
    let spiral = Preset.all.first { $0.model == .barkley }!
    let sim = try makeSim(w: 256, h: 256, p: spiral, s: 9)
    sim.step(3000)
    let data = try sim.render(palette: "mono", style: .phase).dataProvider!.data! as Data
    var dominant = [0, 0, 0]
    for i in stride(from: 0, to: data.count, by: 4) {
      let rgb = [data[i], data[i + 1], data[i + 2]]
      dominant[rgb.firstIndex(of: rgb.max()!)!] += 1
    }
    let pixels = data.count / 4
    for count in dominant { XCTAssertGreaterThan(count, pixels / 10, "phase colors should span red, green and blue") }
  }

  func testReliefCastsShadows() throws {
    let sim = try makeSim()
    sim.step(1500)
    let emboss = luminance(try sim.render(palette: "ink", style: .emboss))
    let relief = luminance(try sim.render(palette: "ink", style: .relief))
    let shadowed = zip(emboss, relief).filter { $0 > 60 && $1 < 0.6 * $0 }.count
    XCTAssertGreaterThan(shadowed, emboss.count / 20, "relief should shade the lee side of ridges")
  }

  func testContourDrawsLines() throws {
    let sim = try makeSim()
    sim.step(1500)
    let flat = try sim.render(palette: "mono", style: .flat).dataProvider!.data! as Data
    let contour = try sim.render(palette: "mono", style: .contour).dataProvider!.data! as Data
    let changed = stride(from: 0, to: flat.count, by: 4).filter { flat[$0] != contour[$0] }.count
    XCTAssertGreaterThan(changed, flat.count / 4 / 20, "contour lines should cover part of the image")
    XCTAssertLessThan(changed, flat.count / 4 / 2, "but leave most of it as the flat colour")
  }

  func testEveryPaletteRenders() throws {
    let sim = try makeSim(w: 32, h: 32)
    let images = try Palette.names.map { try sim.render(palette: $0, style: .flat).dataProvider!.data! as Data }
    XCTAssertEqual(Set(images).count, Palette.names.count)
  }

  func testSwiftHohenbergPicksItsWavelength() throws {
    // (1 + lap)^2 selects wavelength 2 pi in model units: 2 pi / h cells. With
    // g = 0 it forms rolls in every direction; for randomly oriented stripes a
    // straight line crosses 4 / (pi lambda) edges per unit length (Buffon).
    let benard = Preset.all.first { $0.model == .swiftHohenberg }!
    let rolls = Preset(name: "rolls", model: .swiftHohenberg, constants: [0.3, 0, benard.constants[2]],
                       dt: benard.dt, seedShape: .perturbed, steps: benard.steps, palette: "mono", summary: "")
    let sim = try makeSim(w: 256, h: 256, p: rolls, s: 4)
    sim.step(rolls.steps)
    let lum = luminance(try sim.render(palette: "mono", style: .flat))
    let mean = lum.reduce(0, +) / Double(lum.count)
    var crossings = 0
    for line in stride(from: 0, to: 256, by: 4) {
      for i in 1..<256 {
        if (lum[line * 256 + i] > mean) != (lum[line * 256 + i - 1] > mean) { crossings += 1 }  // rows
        if (lum[i * 256 + line] > mean) != (lum[(i - 1) * 256 + line] > mean) { crossings += 1 }  // columns
      }
    }
    let perCell = Double(crossings) / (2 * 64 * 255)
    let wavelength = 4 / (Double.pi * perCell)
    let expected = 2 * Double.pi / Double(rolls.constants[2])
    XCTAssertEqual(wavelength, expected, accuracy: 0.2 * expected)
  }

  func testCyclicCompetitionKeepsEverySpecies() throws {
    // Rock-paper-scissors: each species beats the next, so none can win and
    // all three survive in rotating spirals. Rendered by species, all three
    // colours stay on screen.
    let cyclic = Preset.all.first { $0.model == .mayLeonard }!
    let sim = try makeSim(w: 256, h: 256, p: cyclic, s: 6)
    sim.step(cyclic.steps)
    let data = try sim.render(palette: "mono", style: .species).dataProvider!.data! as Data
    var dominant = [0, 0, 0]
    for i in stride(from: 0, to: data.count, by: 4) {
      let rgb = [data[i], data[i + 1], data[i + 2]]
      dominant[rgb.firstIndex(of: rgb.max()!)!] += 1
    }
    for count in dominant { XCTAssertGreaterThan(count, data.count / 4 / 10, "a species died out") }
  }
}
