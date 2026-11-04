//
//  Video_Lane_TestTests.swift
//  Video_Lane_TestTests
//
//  Created by Oliver Paver on 3/4/25.
//

import Testing
import UIKit
@testable import Video_Lane_Test

/**
 Tests for `LaneDetector`, including:
 - Initialization and property defaults
 - Handling frames with or without lane overlays
 - Watchdog timeout resets
 - Detection of polynomials (or lack thereof) in uniform images
 - Real-lane image testing for DBSCAN and RANSAC coverage
 */
struct LaneDetectorTests {

    // MARK: - 1) Test Initialization
    /// Ensures polynomials start as nil and LaneDetector does not crash on creation.
    @Test
    func testInitializationSetsProperties() async throws {
        let sut = LaneDetector()
        #expect(sut.egoLeftPoly == nil, "Left polynomial should be nil at init.")
        #expect(sut.egoRightPoly == nil, "Right polynomial should be nil at init.")
    }

    // MARK: - 2) Test feedFrame returns raw image if no overlay
    /// If no lane overlay is present, `feedFrame(_:)` should return the same-size raw frame.
    @Test
    func testFeedFrameWithNoOverlay() async throws {
        let sut = LaneDetector()
        let inputImage = Self.makeTestImage(color: .blue, size: CGSize(width: 50, height: 50))

        let output = sut.feedFrame(inputImage)
        #expect(output != nil, "Expected a non-nil image result.")
        #expect(output?.size == inputImage.size, "Expected feedFrame to preserve size when no overlay.")
    }

    // MARK: - 3) Test the watchdog timeout triggers a reset
    /**
     Provides a large image that may stall the pipeline, ensuring the 2-second timeout
     clears polynomials and overlay. Then verifies the detector is still functional.
     */
    @Test
    func testWatchdogTimeoutResetsState() async throws {
        let sut = LaneDetector()

        // Potentially large image
        let bigImage = Self.makeTestImage(color: .red, size: CGSize(width: 5000, height: 5000))
        _ = sut.feedFrame(bigImage)

        // Wait >2s for the watchdog to elapse
        try await Task.sleep(nanoseconds: 3_000_000_000)

        #expect(sut.egoLeftPoly == nil, "Left polynomial should be nil after timeout reset.")
        #expect(sut.egoRightPoly == nil, "Right polynomial should be nil after timeout reset.")

        // Confirm it still processes a subsequent frame
        let smallFrame = Self.makeTestImage(color: .green, size: CGSize(width: 20, height: 20))
        let output = sut.feedFrame(smallFrame)
        #expect(output != nil, "feedFrame should return a valid image even after reset.")
    }

    // MARK: - 4) Test uniform image => no lanes => polynomials remain nil
    /// A pure white image typically yields no lane features. Polynomials should stay nil.
    @Test
    func testPolynomialsAfterUniformImage() async throws {
        let sut = LaneDetector()
        let testFrame = Self.makeTestImage(color: .white, size: CGSize(width: 512, height: 256))

        _ = sut.feedFrame(testFrame)

        // Wait <2s to avoid the watchdog
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(sut.egoLeftPoly == nil, "No lanes expected on a uniform white image => left poly remains nil.")
        #expect(sut.egoRightPoly == nil, "No lanes expected on a uniform white image => right poly remains nil.")
    }

    // MARK: - 5) Test pure black image => no lanes => polynomials remain nil
    @Test
    func testNoLaneImageLeavesPolynomialsNil() async throws {
        let sut = LaneDetector()
        let blackFrame = Self.makeTestImage(color: .black, size: CGSize(width: 1280, height: 720))
        _ = sut.feedFrame(blackFrame)

        try await Task.sleep(nanoseconds: 1_000_000_000)

        #expect(sut.egoLeftPoly == nil, "Left polynomial should remain nil if no features are detected.")
        #expect(sut.egoRightPoly == nil, "Right polynomial should remain nil if no features are detected.")
    }

    // MARK: - 6) Test real lane image triggers polynomials
    /**
     Loads a known-lane image from the test bundle to exercise DBSCAN, RANSAC,
     and the entire pipeline, expecting polynomials to be set.
     */
    @Test
    func testRealLaneImageTriggersLanePolynomials() async throws {
        let sut = LaneDetector()
        
        guard let realLaneImage = Self.loadTestImage(named: "lane_lines", fileExtension: "jpg") else {
            #expect(Bool(false), "Failed to load lane_lines.jpg from test bundle.")
            return
        }
        
        _ = sut.feedFrame(realLaneImage)

        // Wait <2s for normal processing
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(sut.egoLeftPoly != nil, "Expected left lane polynomial after real-lane image.")
        #expect(sut.egoRightPoly != nil, "Expected right lane polynomial after real-lane image.")
    }

    // MARK: - Helper: Create a synthetic solid-color test image
    private static func makeTestImage(color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    // MARK: - Helper: Load a real test image from the bundle
    private static func loadTestImage(named: String, fileExtension: String) -> UIImage? {
        guard let testBundleURL = Bundle(for: BundleToken.self).url(forResource: named,
                                                                   withExtension: fileExtension),
              let imageData = try? Data(contentsOf: testBundleURL),
              let image = UIImage(data: imageData) else {
            return nil
        }
        return image
    }
}

// MARK: - Internal bundle reference
private class BundleToken {}
