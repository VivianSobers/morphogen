import Foundation
import MorphogenCore
import CoreGraphics

func fail(_ msg: String, _ code: Int32) -> Never { fputs("morphogen: \(msg)\n", stderr); exit(code) }

let a = CommandLine.arguments
var (pName, palName, styleName, outPath, gifPath): (String?, String?, String?, String?, String?)
var (sizeArg, wArg, hArg, stepsArg, framesArg, gifSzArg): (Int?, Int?, Int?, Int?, Int?, Int?)
var (feedArg, killArg): (Float?, Float?)
var seedArg: UInt32?

var i = 1
while i < a.count {
  let arg = a[i]
  switch arg {
  case "--help", "-h":
    print("Usage: morphogen [--preset NAME] [--size N | --width W --height H] [--steps N] [--feed F] [--kill K] [--palette NAME] [--style flat|emboss|glossy] [--seed N] [--out FILE.png] [--gif FILE.gif] [--frames N] [--gif-size N] [--list] [--help]")
    exit(0)
  case "--list":
    for p in Preset.all {
      let f = String(format: "%.4f", p.feed), k = String(format: "%.4f", p.kill)
      print("\(p.name.padding(toLength: 12, withPad: " ", startingAt: 0)) f=\(f) k=\(k)  \(p.summary)")
    }
    print("\npalettes: \(Palette.names.joined(separator: ", "))")
    print("styles: \(RenderStyle.allCases.map(\.name).joined(separator: ", "))")
    exit(0)
  case "--preset": i += 1; guard i < a.count else { fail("missing value", 64) }; pName = a[i]
  case "--size": i += 1; guard i < a.count, let v = Int(a[i]) else { fail("invalid --size", 64) }; sizeArg = v
  case "--width": i += 1; guard i < a.count, let v = Int(a[i]) else { fail("invalid --width", 64) }; wArg = v
  case "--height": i += 1; guard i < a.count, let v = Int(a[i]) else { fail("invalid --height", 64) }; hArg = v
  case "--steps": i += 1; guard i < a.count, let v = Int(a[i]) else { fail("invalid --steps", 64) }; stepsArg = v
  case "--feed": i += 1; guard i < a.count, let v = Float(a[i]) else { fail("invalid --feed", 64) }; feedArg = v
  case "--kill": i += 1; guard i < a.count, let v = Float(a[i]) else { fail("invalid --kill", 64) }; killArg = v
  case "--palette": i += 1; guard i < a.count else { fail("missing value", 64) }; palName = a[i]
  case "--style": i += 1; guard i < a.count else { fail("missing value", 64) }; styleName = a[i]
  case "--seed": i += 1; guard i < a.count, let v = UInt32(a[i]) else { fail("invalid --seed", 64) }; seedArg = v
  case "--out": i += 1; guard i < a.count else { fail("missing value", 64) }; outPath = a[i]
  case "--gif": i += 1; guard i < a.count else { fail("missing value", 64) }; gifPath = a[i]
  case "--frames": i += 1; guard i < a.count, let v = Int(a[i]) else { fail("invalid --frames", 64) }; framesArg = v
  case "--gif-size": i += 1; guard i < a.count, let v = Int(a[i]) else { fail("invalid --gif-size", 64) }; gifSzArg = v
  default: fail("unknown option '\(arg)'", 64)
  }
  i += 1
}

let pTarget = pName ?? "coral"
guard let preset = Preset.named(pTarget) else {
  fail("unknown preset '\(pTarget)'. Valid presets: \(Preset.all.map(\.name).joined(separator: ", "))", 64)
}
let pal = palName ?? preset.palette
guard Palette.names.contains(pal) else {
  fail("unknown palette '\(pal)'. Valid palettes: \(Palette.names.joined(separator: ", "))", 64)
}

guard let style = RenderStyle.named(styleName ?? "emboss") else {
  fail("unknown style '\(styleName!)'. Valid styles: \(RenderStyle.allCases.map(\.name).joined(separator: ", "))", 64)
}

let w = wArg ?? sizeArg ?? 1024, h = hArg ?? sizeArg ?? 1024
guard (16...4096).contains(w), (16...4096).contains(h) else { fail("size must be in 16...4096 (got \(w)x\(h))", 64) }

let steps = stepsArg ?? preset.steps
guard steps >= 1 else { fail("steps must be >= 1", 64) }

let feed = feedArg ?? preset.feed
guard (0...0.12).contains(feed) else { fail("feed must be in 0...0.12", 64) }

let kill = killArg ?? preset.kill
guard (0...0.12).contains(kill) else { fail("kill must be in 0...0.12", 64) }

let seed = seedArg ?? UInt32.random(in: 1...UInt32.max)
let out = outPath ?? "\(preset.name).png"
let frames = framesArg ?? 120
guard (2...600).contains(frames) else { fail("frames must be in 2...600", 64) }
let gifSize = gifSzArg ?? 512
guard (16...4096).contains(gifSize) else { fail("gif-size must be in 16...4096", 64) }

let banner = "preset=\(preset.name) size=\(w)x\(h) steps=\(steps) feed=\(feed) kill=\(kill) palette=\(pal) style=\(style.name) seed=\(seed)"
print(banner)

let t0 = ProcessInfo.processInfo.systemUptime
do {
  let sim = try Simulator(width: w, height: h, preset: preset, seed: seed, feed: feed, kill: kill)
  if let gp = gifPath {
    let chunk = max(1, steps / frames)
    var fList: [CGImage] = []
    for _ in 0..<frames {
      sim.step(chunk)
      fList.append(try sim.render(palette: pal, style: style, outputWidth: gifSize, outputHeight: gifSize))
    }
    let rem = steps - (chunk * frames)
    if rem > 0 { sim.step(rem) }
    try writeGIF(fList, to: URL(fileURLWithPath: gp), frameDelay: 1.0 / 30.0)
  } else {
    sim.step(steps)
  }
  let img = try sim.render(palette: pal, style: style, outputWidth: w, outputHeight: h)
  try writePNG(img, to: URL(fileURLWithPath: out), description: banner)
  print("wrote \(out) (\(String(format: "%.1f", ProcessInfo.processInfo.systemUptime - t0))s)")
} catch let err as MorphogenError {
  fail(err.description, 1)
} catch {
  fail(error.localizedDescription, 1)
}
