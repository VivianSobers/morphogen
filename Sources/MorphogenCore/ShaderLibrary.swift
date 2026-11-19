import Foundation

public enum MorphogenError: Error, CustomStringConvertible, Equatable {
    case noDevice
    case shaderCompile(String)
    case unknownPreset(String)
    case unknownPalette(String)
    case io(String)

    public var description: String {
        switch self {
        case .noDevice: return "No Metal GPU available"
        case .shaderCompile(let m): return "Shader compile error: \(m)"
        case .unknownPreset(let p): return "Unknown preset '\(p)'"
        case .unknownPalette(let p): return "Unknown palette '\(p)'"
        case .io(let m): return m
        }
    }
}
