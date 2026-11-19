import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public func writePNG(_ image: CGImage, to url: URL, description: String) throws {
  guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    throw MorphogenError.io("cannot write \(url.path)")
  }
  CGImageDestinationAddImage(dest, image, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: description]] as CFDictionary)
  guard CGImageDestinationFinalize(dest) else { throw MorphogenError.io("cannot write \(url.path)") }
}

public func writeGIF(_ frames: [CGImage], to url: URL, frameDelay: Double) throws {
  guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    throw MorphogenError.io("cannot write \(url.path)")
  }
  CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
  let p = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
  for f in frames { CGImageDestinationAddImage(dest, f, p) }
  guard CGImageDestinationFinalize(dest) else { throw MorphogenError.io("cannot write \(url.path)") }
}

/// Splits `totalSteps` into `frames` near-equal chunks that sum exactly to it.
public func frameSchedule(totalSteps: Int, frames: Int) -> [Int] {
  (0..<frames).map { i in (i + 1) * totalSteps / frames - i * totalSteps / frames }
}
