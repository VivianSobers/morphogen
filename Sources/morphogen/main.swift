import CoreGraphics
import Foundation
import MorphogenCore

let usage = """
  Usage: morphogen [options]

    --preset NAME        pattern preset (default coral; see --list)
    --size N             grid width and height (default 1024)
    --width W --height H grid size, if not square
    --steps N            simulation steps (default: the preset's)
    --feed F --kill K    override the preset's feed and kill rates
    --palette NAME       color ramp (default: the preset's)
    --style NAME         flat, emboss or glossy (default emboss)
    --seed N             random seed (default: random, printed)
    --out FILE.png       output image (default <preset>.png)
    --gif FILE.gif       also write an animation of the pattern growing
    --frames N           GIF frames (default 120)
    --gif-size N         GIF longer side in pixels (default 512)
    --list               list presets, palettes and styles
  """

func fail(_ message: String, _ code: Int32 = 64) -> Never {
  FileHandle.standardError.write(Data("morphogen: \(message)\n".utf8))
  exit(code)
}

// MARK: - Arguments

var options: [String: String] = [:]
var arguments = CommandLine.arguments.dropFirst()
let valueOptions: Set = ["--preset", "--size", "--width", "--height", "--steps", "--feed", "--kill",
                         "--palette", "--style", "--seed", "--out", "--gif", "--frames", "--gif-size"]

while let argument = arguments.popFirst() {
  switch argument {
  case "--help", "-h":
    print(usage)
    exit(0)
  case "--list":
    for preset in Preset.all {
      let rates = String(format: "f=%.4f k=%.4f", preset.feed, preset.kill)
      print("\(preset.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(rates)  \(preset.summary)")
    }
    print("\npalettes: \(Palette.names.joined(separator: ", "))")
    print("styles: \(RenderStyle.allCases.map(\.name).joined(separator: ", "))")
    exit(0)
  case _ where valueOptions.contains(argument):
    guard let value = arguments.popFirst() else { fail("\(argument) needs a value") }
    options[argument] = value
  default:
    fail("unknown option '\(argument)'\n\(usage)")
  }
}

/// Parses a numeric option, failing with a usage error if it is malformed or out of range.
func number<T: LosslessStringConvertible & Comparable>(_ name: String, default fallback: T,
                                                       in range: ClosedRange<T>) -> T {
  guard let text = options[name] else { return fallback }
  guard let value = T(text) else { fail("invalid \(name) '\(text)'") }
  guard range.contains(value) else { fail("\(name) must be in \(range.lowerBound)...\(range.upperBound)") }
  return value
}

let presetName = options["--preset"] ?? "coral"
guard let preset = Preset.named(presetName) else {
  fail("unknown preset '\(presetName)'. Valid presets: \(Preset.all.map(\.name).joined(separator: ", "))")
}
let palette = options["--palette"] ?? preset.palette
guard Palette.names.contains(palette) else {
  fail("unknown palette '\(palette)'. Valid palettes: \(Palette.names.joined(separator: ", "))")
}
let styleName = options["--style"] ?? "emboss"
guard let style = RenderStyle.named(styleName) else {
  fail("unknown style '\(styleName)'. Valid styles: \(RenderStyle.allCases.map(\.name).joined(separator: ", "))")
}

let size = number("--size", default: 1024, in: 16...4096)
let width = number("--width", default: size, in: 16...4096)
let height = number("--height", default: size, in: 16...4096)
let steps = number("--steps", default: preset.steps, in: 1...1_000_000)
let feed = number("--feed", default: preset.feed, in: 0...0.12)
let kill = number("--kill", default: preset.kill, in: 0...0.12)
let seed = number("--seed", default: UInt32.random(in: 1...UInt32.max), in: 0...UInt32.max)
let frames = number("--frames", default: 120, in: 2...600)
let gifSize = number("--gif-size", default: 512, in: 16...4096)
let output = options["--out"] ?? "\(preset.name).png"
let gifPath = options["--gif"]
if gifPath != nil && frames > steps { fail("--frames (\(frames)) cannot exceed --steps (\(steps))") }

// MARK: - Run

let banner = "preset=\(preset.name) size=\(width)x\(height) steps=\(steps) feed=\(feed) kill=\(kill) "
  + "palette=\(palette) style=\(style.name) seed=\(seed)"
print(banner)

let start = Date()
do {
  let simulator = try Simulator(width: width, height: height, preset: preset, seed: seed, feed: feed, kill: kill)

  if let gifPath {
    // gif-size is the longer side; the shorter one keeps the grid's aspect ratio.
    let scale = Double(gifSize) / Double(max(width, height))
    let gifWidth = max(1, Int((Double(width) * scale).rounded()))
    let gifHeight = max(1, Int((Double(height) * scale).rounded()))
    var gifFrames: [CGImage] = []
    for chunk in frameSchedule(totalSteps: steps, frames: frames) {
      simulator.step(chunk)
      gifFrames.append(try simulator.render(palette: palette, style: style,
                                            outputWidth: gifWidth, outputHeight: gifHeight))
    }
    try writeGIF(gifFrames, to: URL(fileURLWithPath: gifPath), frameDelay: 1.0 / 30.0)
  } else {
    simulator.step(steps)
  }

  let image = try simulator.render(palette: palette, style: style,
                                   outputWidth: width, outputHeight: height)
  try writePNG(image, to: URL(fileURLWithPath: output), description: banner)
  print("wrote \(output) (\(String(format: "%.1f", Date().timeIntervalSince(start)))s)")
} catch let error as MorphogenError {
  fail(error.description, 1)
} catch {
  fail(error.localizedDescription, 1)
}
