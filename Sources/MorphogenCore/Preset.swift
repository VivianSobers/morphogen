import Foundation

public enum SeedShape: UInt32 { case spots = 0, square = 1, rings = 2, noise = 3 }

public struct Preset: Equatable {
    public let name: String, feed: Float, kill: Float
    public let feedEnd: Float?, killEnd: Float?
    public let seedShape: SeedShape, steps: Int
    public let palette: String, summary: String

    public init(name: String, feed: Float, kill: Float, feedEnd: Float? = nil, killEnd: Float? = nil, seedShape: SeedShape, steps: Int, palette: String, summary: String) {
        self.name = name; self.feed = feed; self.kill = kill; self.feedEnd = feedEnd; self.killEnd = killEnd
        self.seedShape = seedShape; self.steps = steps; self.palette = palette; self.summary = summary
    }

    public static let all: [Preset] = [
        Preset(name: "coral", feed: 0.0545, kill: 0.062, seedShape: .spots, steps: 12000, palette: "coral", summary: "branching coral growth"),
        Preset(name: "mitosis", feed: 0.0360, kill: 0.063, seedShape: .spots, steps: 15000, palette: "ocean", summary: "spots that divide like cells"),
        Preset(name: "zebra", feed: 0.0240, kill: 0.050, seedShape: .noise, steps: 10000, palette: "mono", summary: "stripes"),
        Preset(name: "fingerprint", feed: 0.037, kill: 0.060, seedShape: .noise, steps: 12000, palette: "ink", summary: "labyrinth of ridges"),
        Preset(name: "worms", feed: 0.078, kill: 0.061, seedShape: .spots, steps: 12000, palette: "magma", summary: "wriggling worms"),
        Preset(name: "bubbles", feed: 0.082, kill: 0.059, seedShape: .noise, steps: 12000, palette: "ocean", summary: "holes in a sheet"),
        Preset(name: "atlas", feed: 0.010, kill: 0.045, feedEnd: 0.100, killEnd: 0.070, seedShape: .noise, steps: 15000, palette: "ocean", summary: "the whole parameter space in one image")
    ]
    public static func named(_ name: String) -> Preset? { all.first { $0.name == name } }
}

public enum Palette {
    public static let names = ["ocean", "magma", "coral", "ink", "mono"]
    public static func index(of name: String) -> UInt32? { names.firstIndex(of: name).map { UInt32($0) } }
}
