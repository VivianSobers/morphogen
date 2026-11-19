import Foundation
import Metal

public enum MorphogenError: Error, CustomStringConvertible, Equatable {
  case noDevice, shaderCompile(String), unknownPreset(String), unknownPalette(String), io(String)
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

public func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
  guard let dir = Bundle.module.resourceURL?.appendingPathComponent("Shaders"),
        let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
    throw MorphogenError.shaderCompile("Missing Shaders")
  }
  let src = try files.filter { $0.pathExtension == "metal" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
  do { return try device.makeLibrary(source: src, options: nil) }
  catch { throw MorphogenError.shaderCompile(error.localizedDescription) }
}
