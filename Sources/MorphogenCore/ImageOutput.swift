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
