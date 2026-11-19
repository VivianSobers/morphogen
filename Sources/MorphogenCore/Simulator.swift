import CoreGraphics
import Foundation
import Metal

public struct FieldStats: Equatable {
  public let minV: Float
  public let maxV: Float
  public let meanV: Float
}

// Mirrors of the structs in 00_common.metal. Every field is 4 bytes, so the
// Swift and Metal layouts match without padding.
struct SimParams {
  var feed, kill, feedEnd, killEnd: Float
  var width, height, isMapped: UInt32
  var dt, Du, Dv: Float
  var flowAngle, flowStrength: Float
  var c0, c1, c2, c3: Float
}

struct SeedParams {
  var width, height, seed, shape, model: UInt32
  var c0, c1, c2, c3: Float
}

struct ColorParams {
  var width, height, outWidth, outHeight, paletteIndex, style: UInt32
  var vLow, vHigh: Float
}

struct PartialStats {
  var minV, maxV, sumV: Float
}

/// A Gray-Scott reaction-diffusion simulation on the GPU.
///
/// The (U, V) field lives in two rg32Float textures; each step reads one and
/// writes the other.
public final class Simulator {
  public let width: Int
  public let height: Int

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let seedPipeline: MTLComputePipelineState
  private let stepPipeline: MTLComputePipelineState
  private let statsPipeline: MTLComputePipelineState
  private let colorPipeline: MTLComputePipelineState
  private var fields: [MTLTexture]
  private var current = 0
  private var params: SimParams

  private static let statsGroupSize = 16  // matches the 256-slot reduction in field_stats

  public init(width: Int, height: Int, preset: Preset, seed: UInt32,
              feed: Float? = nil, kill: Float? = nil,
              device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
    guard let device, let queue = device.makeCommandQueue() else { throw MorphogenError.noDevice }
    self.width = width
    self.height = height
    self.device = device
    self.queue = queue

    let library = try makeShaderLibrary(device: device)
    func pipeline(_ name: String) throws -> MTLComputePipelineState {
      guard let function = library.makeFunction(name: name) else {
        throw MorphogenError.shaderCompile("missing kernel \(name)")
      }
      return try device.makeComputePipelineState(function: function)
    }
    seedPipeline = try pipeline("seed_field")
    stepPipeline = try pipeline(preset.flowAngle == nil ? preset.model.kernel : "gray_scott_step_flow")
    statsPipeline = try pipeline("field_stats")
    colorPipeline = try pipeline("colorize")

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    fields = try (0..<2).map { _ in
      guard let texture = device.makeTexture(descriptor: descriptor) else { throw MorphogenError.noDevice }
      return texture
    }

    let feed = feed ?? preset.feed
    let kill = kill ?? preset.kill
    let mapped = preset.feedEnd != nil && preset.killEnd != nil
    let c = preset.constants + Array(repeating: 0, count: 4 - preset.constants.count)
    params = SimParams(
      feed: feed, kill: kill, feedEnd: preset.feedEnd ?? feed, killEnd: preset.killEnd ?? kill,
      width: UInt32(width), height: UInt32(height), isMapped: mapped ? 1 : 0,
      dt: preset.dt, Du: preset.du, Dv: preset.dv,
      flowAngle: (preset.flowAngle ?? 0) * .pi / 180,
      flowStrength: preset.flowAngle == nil ? 0 : 0.9,
      c0: c[0], c1: c[1], c2: c[2], c3: c[3])

    var seedParams = SeedParams(width: UInt32(width), height: UInt32(height), seed: seed,
                                shape: preset.seedShape.rawValue, model: preset.model.rawValue,
                                c0: c[0], c1: c[1], c2: c[2], c3: c[3])
    try run { encoder in
      encoder.setComputePipelineState(seedPipeline)
      encoder.setTexture(fields[0], index: 0)
      encoder.setBytes(&seedParams, length: MemoryLayout<SeedParams>.stride, index: 0)
      dispatch(encoder, width: width, height: height)
    }
  }

  /// Advances the simulation `count` steps in a single command buffer.
  public func step(_ count: Int) {
    guard count > 0 else { return }
    try? run { encoder in
      encoder.setComputePipelineState(stepPipeline)
      encoder.setBytes(&params, length: MemoryLayout<SimParams>.stride, index: 0)
      for _ in 0..<count {
        encoder.setTexture(fields[current], index: 0)
        encoder.setTexture(fields[1 - current], index: 1)
        dispatch(encoder, width: width, height: height)
        encoder.memoryBarrier(scope: .textures)
        current = 1 - current
      }
    }
  }

  /// Min, max and mean of V. The GPU reduces each 16x16 tile; the CPU folds the tiles.
  public func stats() -> FieldStats {
    let group = Self.statsGroupSize
    let groupsX = (width + group - 1) / group
    let groupsY = (height + group - 1) / group
    let tiles = groupsX * groupsY
    guard let partials = device.makeBuffer(length: tiles * MemoryLayout<PartialStats>.stride,
                                           options: .storageModeShared) else {
      return FieldStats(minV: 0, maxV: 0, meanV: 0)
    }

    var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
    try? run { encoder in
      encoder.setComputePipelineState(statsPipeline)
      encoder.setTexture(fields[current], index: 0)
      encoder.setBuffer(partials, offset: 0, index: 0)
      encoder.setBytes(&size, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
      encoder.dispatchThreadgroups(MTLSize(width: groupsX, height: groupsY, depth: 1),
                                   threadsPerThreadgroup: MTLSize(width: group, height: group, depth: 1))
    }

    let tileStats = UnsafeBufferPointer(
      start: partials.contents().bindMemory(to: PartialStats.self, capacity: tiles), count: tiles)
    let sum = tileStats.reduce(0.0) { $0 + Double($1.sumV) }
    return FieldStats(minV: tileStats.map(\.minV).min() ?? 0,
                      maxV: tileStats.map(\.maxV).max() ?? 0,
                      meanV: Float(sum / Double(width * height)))
  }

  /// Colors the current V field. The palette spans V's actual range, so every
  /// preset uses the whole ramp.
  public func render(palette: String, style: RenderStyle = .emboss,
                     outputWidth: Int? = nil, outputHeight: Int? = nil) throws -> CGImage {
    guard let paletteIndex = Palette.index(of: palette) else { throw MorphogenError.unknownPalette(palette) }
    let outWidth = outputWidth ?? width
    let outHeight = outputHeight ?? height
    let range = stats()

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: outWidth, height: outHeight, mipmapped: false)
    descriptor.usage = [.shaderWrite]
    descriptor.storageMode = .shared
    guard let output = device.makeTexture(descriptor: descriptor) else { throw MorphogenError.noDevice }

    var colorParams = ColorParams(
      width: UInt32(width), height: UInt32(height),
      outWidth: UInt32(outWidth), outHeight: UInt32(outHeight),
      paletteIndex: paletteIndex, style: style.rawValue, vLow: range.minV, vHigh: range.maxV)
    try run { encoder in
      encoder.setComputePipelineState(colorPipeline)
      encoder.setTexture(fields[current], index: 0)
      encoder.setTexture(output, index: 1)
      encoder.setBytes(&colorParams, length: MemoryLayout<ColorParams>.stride, index: 0)
      dispatch(encoder, width: outWidth, height: outHeight)
    }

    let bytesPerRow = outWidth * 4
    var pixels = Data(count: bytesPerRow * outHeight)
    pixels.withUnsafeMutableBytes {
      output.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow,
                      from: MTLRegionMake2D(0, 0, outWidth, outHeight), mipmapLevel: 0)
    }
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    guard let provider = CGDataProvider(data: pixels as CFData),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let image = CGImage(width: outWidth, height: outHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo,
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else {
      throw MorphogenError.io("could not build image")
    }
    return image
  }

  // MARK: - Encoding helpers

  /// Encodes work into one compute encoder, then commits and waits.
  private func run(_ encode: (MTLComputeCommandEncoder) -> Void) throws {
    guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else {
      throw MorphogenError.noDevice
    }
    encode(encoder)
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
  }

  /// One thread per pixel; kernels bounds-check, so edges need no padding.
  private func dispatch(_ encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
    encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: min(16, width), height: min(16, height), depth: 1))
  }
}
