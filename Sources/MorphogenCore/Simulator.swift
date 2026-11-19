import Foundation
import Metal
import CoreGraphics

public struct FieldStats: Equatable {
  public let minV, maxV, meanV: Float
  public init(minV: Float, maxV: Float, meanV: Float) { self.minV = minV; self.maxV = maxV; self.meanV = meanV }
}

struct SimParams {
  var feed, kill, feedEnd, killEnd: Float
  var width, height, isMapped: UInt32
  var dt, Du, Dv: Float
}
struct SeedParams { var width, height, seed, shape: UInt32 }
struct ColorParams {
  var width, height, outWidth, outHeight, paletteIndex, style: UInt32
  var vLow, vHigh: Float
}
struct PartialStats { var minV, maxV, sumV: Float }

public final class Simulator {
  public let width, height: Int
  let dev: MTLDevice, queue: MTLCommandQueue
  let sPipe, stPipe, fPipe, cPipe: MTLComputePipelineState
  var texA, texB: MTLTexture
  var cur = 0
  let params: SimParams

  public init(width: Int, height: Int, preset: Preset, seed: UInt32, feed: Float? = nil, kill: Float? = nil, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
    guard let d = device, let q = d.makeCommandQueue() else { throw MorphogenError.noDevice }
    (dev, queue, self.width, self.height) = (d, q, width, height)
    let lib = try makeShaderLibrary(device: d)
    func p(_ n: String) throws -> MTLComputePipelineState {
      guard let fn = lib.makeFunction(name: n) else { throw MorphogenError.shaderCompile("missing \(n)") }
      return try d.makeComputePipelineState(function: fn)
    }
    (sPipe, stPipe, fPipe, cPipe) = (try p("seed_field"), try p("gray_scott_step"), try p("field_stats"), try p("colorize"))

    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]; desc.storageMode = .private
    guard let tA = d.makeTexture(descriptor: desc), let tB = d.makeTexture(descriptor: desc) else { throw MorphogenError.noDevice }
    (texA, texB) = (tA, tB)

    let f = feed ?? preset.feed, k = kill ?? preset.kill
    let isMap: UInt32 = (preset.feedEnd != nil && preset.killEnd != nil) ? 1 : 0
    params = SimParams(feed: f, kill: k, feedEnd: preset.feedEnd ?? f, killEnd: preset.killEnd ?? k, width: UInt32(width), height: UInt32(height), isMapped: isMap, dt: 1.0, Du: 1.0, Dv: 0.5)

    guard let cb = q.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { throw MorphogenError.noDevice }
    enc.setComputePipelineState(sPipe); enc.setTexture(texA, index: 0)
    var sp = SeedParams(width: UInt32(width), height: UInt32(height), seed: seed, shape: preset.seedShape.rawValue)
    enc.setBytes(&sp, length: MemoryLayout<SeedParams>.stride, index: 0)
    enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: min(16, width), height: min(16, height), depth: 1))
    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
  }

  public func step(_ count: Int) {
    guard count > 0, let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return }
    enc.setComputePipelineState(stPipe)
    var p = params
    enc.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 0)
    let grid = MTLSize(width: width, height: height, depth: 1), tg = MTLSize(width: min(16, width), height: min(16, height), depth: 1)
    for _ in 0..<count {
      enc.setTexture((cur == 0) ? texA : texB, index: 0)
      enc.setTexture((cur == 0) ? texB : texA, index: 1)
      enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
      enc.memoryBarrier(scope: .textures)
      cur = 1 - cur
    }
    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
  }

  public func stats() -> FieldStats {
    let gx = (width + 15) / 16, gy = (height + 15) / 16, total = gx * gy
    guard let buf = dev.makeBuffer(length: max(1, total * MemoryLayout<PartialStats>.stride), options: .storageModeShared),
          let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return FieldStats(minV: 0, maxV: 0, meanV: 0) }
    enc.setComputePipelineState(fPipe); enc.setTexture((cur == 0) ? texA : texB, index: 0); enc.setBuffer(buf, offset: 0, index: 0)
    var dims = SIMD2<UInt32>(UInt32(width), UInt32(height))
    enc.setBytes(&dims, length: 8, index: 1)
    enc.dispatchThreadgroups(MTLSize(width: gx, height: gy, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()

    let ptr = buf.contents().bindMemory(to: PartialStats.self, capacity: total)
    var minV: Float = .infinity, maxV: Float = -.infinity, sumV: Double = 0
    for i in 0..<total { minV = min(minV, ptr[i].minV); maxV = max(maxV, ptr[i].maxV); sumV += Double(ptr[i].sumV) }
    return FieldStats(minV: minV, maxV: maxV, meanV: Float(sumV / Double(width * height)))
  }

  public func render(palette: String, style: RenderStyle = .emboss, outputWidth: Int? = nil, outputHeight: Int? = nil) throws -> CGImage {
    guard let pIdx = Palette.index(of: palette) else { throw MorphogenError.unknownPalette(palette) }
    let range = stats()
    let (outW, outH) = (outputWidth ?? width, outputHeight ?? height)
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: outW, height: outH, mipmapped: false)
    desc.usage = [.shaderWrite]; desc.storageMode = .shared
    guard let outTex = dev.makeTexture(descriptor: desc), let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { throw MorphogenError.noDevice }

    enc.setComputePipelineState(cPipe); enc.setTexture((cur == 0) ? texA : texB, index: 0); enc.setTexture(outTex, index: 1)
    var cp = ColorParams(width: UInt32(width), height: UInt32(height), outWidth: UInt32(outW), outHeight: UInt32(outH),
                         paletteIndex: pIdx, style: style.rawValue, vLow: range.minV, vHigh: range.maxV)
    enc.setBytes(&cp, length: MemoryLayout<ColorParams>.stride, index: 0)
    enc.dispatchThreads(MTLSize(width: outW, height: outH, depth: 1), threadsPerThreadgroup: MTLSize(width: min(16, outW), height: min(16, outH), depth: 1))
    enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()

    let bpr = outW * 4
    var data = Data(count: bpr * outH)
    data.withUnsafeMutableBytes { outTex.getBytes($0.baseAddress!, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, outW, outH), mipmapLevel: 0) }
    guard let prov = CGDataProvider(data: data as CFData), let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let img = CGImage(width: outW, height: outH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
      throw MorphogenError.io("Failed creating CGImage")
    }
    return img
  }
}
