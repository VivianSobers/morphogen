import Foundation
import MorphogenCore
import CoreGraphics

func failUsage(_ msg: String) -> Never {
    fputs("morphogen: \(msg)\n", stderr)
    exit(64)
}

func failRuntime(_ msg: String) -> Never {
    fputs("morphogen: \(msg)\n", stderr)
    exit(1)
}

let args = CommandLine.arguments
var i = 1
var presetName: String?
var sizeArg: Int?
var widthArg: Int?
var heightArg: Int?
var stepsArg: Int?
var feedArg: Float?
var killArg: Float?
var paletteArg: String?
var seedArg: UInt32?
var outArg: String?
var gifArg: String?
var framesArg: Int?
var gifSizeArg: Int?

while i < args.count {
    let a = args[i]
    switch a {
    case "--help", "-h":
        print("""
        Usage: morphogen [options]
          --preset NAME         Preset name (coral, mitosis, zebra, ...)
          --size N              Square size in pixels [16..4096]
          --width W --height H  Custom dimensions [16..4096]
          --steps N             Simulation steps (>= 1)
          --feed F              Feed rate [0.0..0.12]
          --kill K              Kill rate [0.0..0.12]
          --palette NAME        Palette (ocean, magma, coral, ink, mono)
          --seed N              Random seed
          --out FILE.png        Output PNG file
          --gif FILE.gif        Output animated GIF
          --frames N            GIF frame count [2..600]
          --gif-size N          GIF square size [16..4096]
          --list                List available presets and palettes
          --help                Show this help
        """)
        exit(0)
    case "--list":
        for p in Preset.all {
            let fStr = String(format: "%.4f", p.feed)
            let kStr = String(format: "%.4f", p.kill)
            let padded = p.name.padding(toLength: 12, withPad: " ", startingAt: 0)
            print("\(padded) f=\(fStr) k=\(kStr)  \(p.summary)")
        }
        print("\npalettes: \(Palette.names.joined(separator: ", "))")
        exit(0)
    case "--preset":
        i += 1; guard i < args.count else { failUsage("missing value for --preset") }; presetName = args[i]
    case "--size":
        i += 1; guard i < args.count, let v = Int(args[i]) else { failUsage("invalid value for --size") }; sizeArg = v
    case "--width":
        i += 1; guard i < args.count, let v = Int(args[i]) else { failUsage("invalid value for --width") }; widthArg = v
    case "--height":
        i += 1; guard i < args.count, let v = Int(args[i]) else { failUsage("invalid value for --height") }; heightArg = v
    case "--steps":
        i += 1; guard i < args.count, let v = Int(args[i]) else { failUsage("invalid value for --steps") }; stepsArg = v
    case "--feed":
        i += 1; guard i < args.count, let v = Float(args[i]) else { failUsage("invalid value for --feed") }; feedArg = v
    case "--kill":
        i += 1; guard i < args.count, let v = Float(args[i]) else { failUsage("invalid value for --kill") }; killArg = v
    case "--palette":
        i += 1; guard i < args.count else { failUsage("missing value for --palette") }; paletteArg = args[i]
    case "--seed":
        i += 1; guard i < args.count, let v = UInt32(args[i]) else { failUsage("invalid value for --seed") }; seedArg = v
    case "--out":
        i += 1; guard i < args.count else { failUsage("missing value for --out") }; outArg = args[i]
    case "--gif":
        i += 1; guard i < args.count else { failUsage("missing value for --gif") }; gifArg = args[i]
    case "--frames":
        i += 1; guard i < args.count, let v = Int(args[i]) else { failUsage("invalid value for --frames") }; framesArg = v
    case "--gif-size":
        i += 1; guard i < args.count, let v = Int(args[i]) else { failUsage("invalid value for --gif-size") }; gifSizeArg = v
    default:
        failUsage("unknown option '\(a)'. Use --help for usage.")
    }
    i += 1
}

let presetTargetName = presetName ?? "coral"
guard let preset = Preset.named(presetTargetName) else {
    failUsage("unknown preset '\(presetTargetName)'. Valid presets: \(Preset.all.map(\.name).joined(separator: ", "))")
}

let palette = paletteArg ?? preset.palette
guard Palette.names.contains(palette) else {
    failUsage("unknown palette '\(palette)'. Valid palettes: \(Palette.names.joined(separator: ", "))")
}

let width = widthArg ?? sizeArg ?? 1024
let height = heightArg ?? sizeArg ?? 1024
guard (16...4096).contains(width), (16...4096).contains(height) else {
    failUsage("size must be between 16 and 4096 (got \(width)x\(height))")
}

let steps = stepsArg ?? preset.steps
guard steps >= 1 else { failUsage("steps must be >= 1 (got \(steps))") }

let feed = feedArg ?? preset.feed
guard (0.0...0.12).contains(feed) else { failUsage("feed must be between 0.0 and 0.12 (got \(feed))") }

let kill = killArg ?? preset.kill
guard (0.0...0.12).contains(kill) else { failUsage("kill must be between 0.0 and 0.12 (got \(kill))") }

let seed = seedArg ?? UInt32.random(in: 1...UInt32.max)
let outPath = outArg ?? "\(preset.name).png"
let frames = framesArg ?? 120
guard (2...600).contains(frames) else { failUsage("frames must be between 2 and 600 (got \(frames))") }
let gifSize = gifSizeArg ?? 512
guard (16...4096).contains(gifSize) else { failUsage("gif-size must be between 16 and 4096 (got \(gifSize))") }

let banner = "preset=\(preset.name) size=\(width)x\(height) steps=\(steps) feed=\(feed) kill=\(kill) palette=\(palette) seed=\(seed)"
print(banner)

let start = ProcessInfo.processInfo.systemUptime

do {
    let sim = try Simulator(width: width, height: height, preset: preset, seed: seed, feed: feed, kill: kill)
    if let gifPath = gifArg {
        let chunk = max(1, steps / frames)
        var gifFrames: [CGImage] = []
        for _ in 0..<frames {
            sim.step(chunk)
            let fImg = try sim.render(palette: palette, outputWidth: gifSize, outputHeight: gifSize)
            gifFrames.append(fImg)
        }
        let rem = steps - (chunk * frames)
        if rem > 0 { sim.step(rem) }
        try writeGIF(gifFrames, to: URL(fileURLWithPath: gifPath), frameDelay: 1.0 / 30.0)
    } else {
        sim.step(steps)
    }

    let finalImg = try sim.render(palette: palette, outputWidth: width, outputHeight: height)
    try writePNG(finalImg, to: URL(fileURLWithPath: outPath), description: banner)

    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print("wrote \(outPath) (\(String(format: "%.1f", elapsed))s)")
} catch let err as MorphogenError {
    failRuntime(err.description)
} catch {
    failRuntime(error.localizedDescription)
}
