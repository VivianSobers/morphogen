import Foundation

public enum SeedShape: UInt32 { case spots = 0, square = 1, rings = 2, noise = 3 }

public struct Preset: Equatable {
  public let name: String, feed: Float, kill: Float, feedEnd: Float?, killEnd: Float?, seedShape: SeedShape, steps: Int, palette: String, summary: String
  /// Direction in degrees that diffusion favours; stripes line up along it. nil = isotropic.
  public let flowAngle: Float?

  public init(_ n: String, _ f: Float, _ k: Float, _ fe: Float? = nil, _ ke: Float? = nil, _ s: SeedShape, _ st: Int, _ pal: String, _ sum: String, _ flow: Float? = nil) {
    name = n; feed = f; kill = k; feedEnd = fe; killEnd = ke; seedShape = s; steps = st; palette = pal; summary = sum; flowAngle = flow
  }
  public init(name: String, feed: Float, kill: Float, feedEnd: Float? = nil, killEnd: Float? = nil, seedShape: SeedShape, steps: Int, palette: String, summary: String, flowAngle: Float? = nil) {
    self.init(name, feed, kill, feedEnd, killEnd, seedShape, steps, palette, summary, flowAngle)
  }

  public static let all: [Preset] = [
    Preset("coral", 0.0545, 0.062, nil, nil, .spots, 6000, "coral", "branching coral growth"),
    Preset("mitosis", 0.0360, 0.063, nil, nil, .spots, 15000, "ocean", "spots that divide like cells"),
    Preset("zebra", 0.030, 0.057, nil, nil, .noise, 10000, "mono", "stripes lined up by directional diffusion", 90),
    Preset("fingerprint", 0.030, 0.0565, nil, nil, .noise, 12000, "ink", "labyrinth of ridges"),
    Preset("worms", 0.078, 0.061, nil, nil, .spots, 12000, "magma", "wriggling worms"),
    Preset("bubbles", 0.082, 0.059, nil, nil, .noise, 12000, "ocean", "holes in a sheet"),
    Preset("atlas", 0.010, 0.045, 0.100, 0.070, .noise, 15000, "ocean", "the whole parameter space in one image")
  ]
  public static func named(_ n: String) -> Preset? { all.first { $0.name == n } }
}

public enum Palette {
  public static let names = ["ocean", "magma", "coral", "ink", "mono"]
  public static func index(of n: String) -> UInt32? { names.firstIndex(of: n).map { UInt32($0) } }
}

/// How `Simulator.render` lights the pattern.
public enum RenderStyle: UInt32, CaseIterable {
  case flat = 0, emboss = 1, glossy = 2

  public var name: String { String(describing: self) }
  public static func named(_ name: String) -> RenderStyle? { allCases.first { $0.name == name } }
}
