import XCTest
import Metal
@testable import MorphogenCore

final class SimulatorTests: XCTestCase {
    func testSkeleton() {
        XCTAssertEqual(MorphogenError.noDevice.description, "No Metal GPU available")
    }
}
