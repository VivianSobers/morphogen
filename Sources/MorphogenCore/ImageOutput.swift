import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public func writePNG(_ image: CGImage, to url: URL, description: String) throws {
    let parent = url.deletingLastPathComponent().path
    guard FileManager.default.fileExists(atPath: parent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw MorphogenError.io("cannot write \(url.path)")
    }
    let meta = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: description]] as CFDictionary
    CGImageDestinationAddImage(dest, image, meta)
    guard CGImageDestinationFinalize(dest) else { throw MorphogenError.io("cannot write \(url.path)") }
}

public func writeGIF(_ frames: [CGImage], to url: URL, frameDelay: Double) throws {
    let parent = url.deletingLastPathComponent().path
    guard FileManager.default.fileExists(atPath: parent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
        throw MorphogenError.io("cannot write \(url.path)")
    }
    let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    CGImageDestinationSetProperties(dest, fileProps)
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
    for f in frames { CGImageDestinationAddImage(dest, f, frameProps) }
    guard CGImageDestinationFinalize(dest) else { throw MorphogenError.io("cannot write \(url.path)") }
}
