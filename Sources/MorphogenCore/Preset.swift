import Foundation

/// The reaction-diffusion system a preset runs. Raw values match MODEL_* in 00_common.metal.
public enum Model: UInt32, CaseIterable {
  case grayScott = 0, barkley = 1, brusselator = 2, schnakenberg = 3
  case giererMeinhardt = 4, lengyelEpstein = 5, thomas = 6

  var kernel: String {
    switch self {
    case .grayScott: return "gray_scott_step"
    case .barkley: return "barkley_step"
    case .brusselator: return "brusselator_step"
    case .schnakenberg: return "schnakenberg_step"
    case .giererMeinhardt: return "gierer_meinhardt_step"
    case .lengyelEpstein: return "lengyel_epstein_step"
    case .thomas: return "thomas_step"
    }
  }
}

/// Starting state, matching the branches in seed_field. The first four are
/// Gray-Scott shapes; perturbed is any model's steady state plus noise.
public enum SeedShape: UInt32 {
  case spots = 0, square = 1, rings = 2, noise = 3, perturbed = 4, brokenWaves = 5
}

public struct Preset: Equatable {
  public let name: String
  public let feed: Float
  public let kill: Float
  /// With both set, feed sweeps from `feed` to `feedEnd` along x and kill from
  /// `kill` to `killEnd` along y.
  public let feedEnd: Float?
  public let killEnd: Float?
  public let seedShape: SeedShape
  public let steps: Int
  public let palette: String
  public let summary: String
  /// Direction in degrees that diffusion favours; stripes line up along it. nil = isotropic.
  public let flowAngle: Float?
  public let model: Model
  /// The model's constants (c0...c3 in its kernel). Gray-Scott uses feed and kill instead.
  public let constants: [Float]
  /// Diffusion rates of the chemicals the model's kernel calls u and v, and the time step.
  public let du: Float
  public let dv: Float
  public let dt: Float

  public init(name: String, model: Model = .grayScott, feed: Float = 0, kill: Float = 0,
              feedEnd: Float? = nil, killEnd: Float? = nil, constants: [Float] = [],
              du: Float = 1, dv: Float = 0.5, dt: Float = 1,
              seedShape: SeedShape, steps: Int, palette: String, summary: String, flowAngle: Float? = nil) {
    precondition(constants.count <= 4, "kernels take at most four constants")
    self.name = name
    self.model = model
    self.constants = constants
    self.du = du
    self.dv = dv
    self.dt = dt
    self.feed = feed
    self.kill = kill
    self.feedEnd = feedEnd
    self.killEnd = killEnd
    self.seedShape = seedShape
    self.steps = steps
    self.palette = palette
    self.summary = summary
    self.flowAngle = flowAngle
  }

  public static let all: [Preset] = [
    Preset(name: "coral", feed: 0.0545, kill: 0.062, seedShape: .spots, steps: 6000,
           palette: "coral", summary: "branching coral growth"),
    Preset(name: "mitosis", feed: 0.036, kill: 0.063, seedShape: .spots, steps: 15000,
           palette: "ocean", summary: "spots that divide like cells"),
    Preset(name: "zebra", feed: 0.030, kill: 0.057, seedShape: .noise, steps: 10000,
           palette: "mono", summary: "stripes lined up by directional diffusion", flowAngle: 90),
    Preset(name: "fingerprint", feed: 0.030, kill: 0.0565, seedShape: .noise, steps: 12000,
           palette: "ink", summary: "labyrinth of ridges"),
    Preset(name: "worms", feed: 0.078, kill: 0.061, seedShape: .spots, steps: 12000,
           palette: "magma", summary: "wriggling worms"),
    Preset(name: "bubbles", feed: 0.082, kill: 0.059, seedShape: .noise, steps: 12000,
           palette: "ocean", summary: "holes in a sheet"),
    Preset(name: "atlas", feed: 0.010, kill: 0.045, feedEnd: 0.100, killEnd: 0.070, seedShape: .noise,
           steps: 15000, palette: "ocean", summary: "the whole parameter space in one image"),
    Preset(name: "spirals", model: .barkley, constants: [0.75, 0.06, 0.02], du: 15, dt: 0.05,
           seedShape: .brokenWaves, steps: 20000, palette: "magma", summary: "rotating spiral waves in an excitable medium"),
    Preset(name: "dunes", model: .brusselator, constants: [3, 4.6], du: 12, dv: 96, dt: 0.01,
           seedShape: .perturbed, steps: 80000, palette: "coral", summary: "Brusselator stripes, like ripples in sand"),
    Preset(name: "leopard", model: .schnakenberg, constants: [0.1, 0.9], du: 6, dv: 120, dt: 0.008,
           seedShape: .perturbed, steps: 100000, palette: "magma", summary: "Schnakenberg spots packing into hexagons"),
    Preset(name: "maze", model: .giererMeinhardt, constants: [1.5, 0.1, 0.02], du: 4, dv: 120, dt: 0.006,
           seedShape: .perturbed, steps: 80000, palette: "ocean", summary: "Gierer-Meinhardt stripes from a saturating activator"),
    Preset(name: "cima", model: .lengyelEpstein, constants: [12, 0.3], du: 1, dv: 30, dt: 0.02,
           seedShape: .perturbed, steps: 30000, palette: "coral", summary: "Lengyel-Epstein, the first Turing pattern seen in a lab"),
    Preset(name: "honeycomb", model: .thomas, constants: [150, 100, 13, 0.05], du: 0.5, dv: 13.5, dt: 0.02,
           seedShape: .perturbed, steps: 30000, palette: "mono", summary: "Thomas substrate inhibition: holes in a sheet"),
  ]

  public static func named(_ name: String) -> Preset? { all.first { $0.name == name } }
}

public enum Palette {
  /// Order matches the palette switch in sample_palette.
  public static let names = ["ocean", "magma", "coral", "ink", "mono"]

  public static func index(of name: String) -> UInt32? { names.firstIndex(of: name).map(UInt32.init) }
}

/// How `Simulator.render` lights the pattern.
public enum RenderStyle: UInt32, CaseIterable {
  case flat = 0, emboss = 1, glossy = 2, phase = 3

  public var name: String { String(describing: self) }

  public static func named(_ name: String) -> RenderStyle? { allCases.first { $0.name == name } }
}
