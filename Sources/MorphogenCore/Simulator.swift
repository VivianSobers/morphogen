import Foundation
import Metal

public struct FieldStats: Equatable {
    public let minV, maxV, meanV: Float
    public init(minV: Float, maxV: Float, meanV: Float) {
        self.minV = minV; self.maxV = maxV; self.meanV = meanV
    }
}

struct SimParams {
    var feed, kill, feedEnd, killEnd: Float
    var width, height, isMapped: UInt32
    var dt, Du, Dv: Float
}

struct SeedParams { var width, height, seed, shape: UInt32 }
struct PartialStats { var minV, maxV, sumV: Float }

public final class Simulator {
    public let width, height: Int
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let seedPipe, stepPipe, statsPipe: MTLComputePipelineState
    var texA, texB: MTLTexture
    var currentTex = 0
    let simParams: SimParams

    public init(width: Int, height: Int, preset: Preset, seed: UInt32, feed: Float? = nil, kill: Float? = nil, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let dev = device, let cq = dev.makeCommandQueue() else { throw MorphogenError.noDevice }
        self.device = dev; self.queue = cq; self.width = width; self.height = height
        let lib = try makeShaderLibrary(device: dev)
        self.library = lib
        guard let sFn = lib.makeFunction(name: "seed_field"),
              let stFn = lib.makeFunction(name: "gray_scott_step"),
              let fFn = lib.makeFunction(name: "field_stats") else {
            throw MorphogenError.shaderCompile("Missing kernel function")
        }
        self.seedPipe = try dev.makeComputePipelineState(function: sFn)
        self.stepPipe = try dev.makeComputePipelineState(function: stFn)
        self.statsPipe = try dev.makeComputePipelineState(function: fFn)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let tA = dev.makeTexture(descriptor: desc), let tB = dev.makeTexture(descriptor: desc) else {
            throw MorphogenError.noDevice
        }
        self.texA = tA; self.texB = tB

        let f = feed ?? preset.feed, k = kill ?? preset.kill
        let fEnd = preset.feedEnd ?? f, kEnd = preset.killEnd ?? k
        let isMap: UInt32 = (preset.feedEnd != nil && preset.killEnd != nil) ? 1 : 0
        self.simParams = SimParams(feed: f, kill: k, feedEnd: fEnd, killEnd: kEnd, width: UInt32(width), height: UInt32(height), isMapped: isMap, dt: 1.0, Du: 1.0, Dv: 0.5)

        try seedField(shape: preset.seedShape, seed: seed)
    }

    private func seedField(shape: SeedShape, seed: UInt32) throws {
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { throw MorphogenError.noDevice }
        enc.setComputePipelineState(seedPipe)
        enc.setTexture(texA, index: 0)
        var p = SeedParams(width: UInt32(width), height: UInt32(height), seed: seed, shape: shape.rawValue)
        enc.setBytes(&p, length: MemoryLayout<SeedParams>.stride, index: 0)
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: min(16, width), height: min(16, height), depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    public func step(_ count: Int) {
        guard count > 0, let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(stepPipe)
        var p = simParams
        enc.setBytes(&p, length: MemoryLayout<SimParams>.stride, index: 0)
        let grid = MTLSize(width: width, height: height, depth: 1)
        let tg = MTLSize(width: min(16, width), height: min(16, height), depth: 1)
        for _ in 0..<count {
            let inTex = (currentTex == 0) ? texA : texB
            let outTex = (currentTex == 0) ? texB : texA
            enc.setTexture(inTex, index: 0)
            enc.setTexture(outTex, index: 1)
            enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
            enc.memoryBarrier(scope: .textures)
            currentTex = 1 - currentTex
        }
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    public func stats() -> FieldStats {
        let gx = (width + 15) / 16, gy = (height + 15) / 16, total = gx * gy
        guard let buf = device.makeBuffer(length: max(1, total * MemoryLayout<PartialStats>.stride), options: .storageModeShared),
              let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else {
            return FieldStats(minV: 0, maxV: 0, meanV: 0)
        }
        enc.setComputePipelineState(statsPipe)
        enc.setTexture((currentTex == 0) ? texA : texB, index: 0)
        enc.setBuffer(buf, offset: 0, index: 0)
        var dims = SIMD2<UInt32>(UInt32(width), UInt32(height))
        enc.setBytes(&dims, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
        enc.dispatchThreadgroups(MTLSize(width: gx, height: gy, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        let ptr = buf.contents().bindMemory(to: PartialStats.self, capacity: total)
        var minV: Float = .infinity, maxV: Float = -.infinity, sumV: Double = 0
        for i in 0..<total {
            minV = min(minV, ptr[i].minV)
            maxV = max(maxV, ptr[i].maxV)
            sumV += Double(ptr[i].sumV)
        }
        return FieldStats(minV: minV, maxV: maxV, meanV: Float(sumV / Double(width * height)))
    }
}
