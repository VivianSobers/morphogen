import XCTest
import Metal
@testable import MorphogenCore

final class SimulatorTests: XCTestCase {
    func testShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal GPU available")
        }
        let library = try makeShaderLibrary(device: device)
        XCTAssertNotNil(library.makeFunction(name: "seed_field"))
        XCTAssertNotNil(library.makeFunction(name: "gray_scott_step"))
        XCTAssertNotNil(library.makeFunction(name: "field_stats"))
    }
}
