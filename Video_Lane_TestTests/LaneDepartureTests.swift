//
//  LaneDepartureManagerTests.swift
//  Video_Lane_TestTests
//
//  
//

import Testing
import UIKit
@testable import Video_Lane_Test

/**
 A test suite for `LaneDepartureManager`, covering:
 - Initial no-lines fallback
 - Single-line fallback with learned width
 - Automatic calibration after stable frames
 - Consecutive frames departure logic

 The linear polynomial fixtures cross both look-ahead rows (180 and 200)
 at integer x coordinates, within the manager's seven-pixel search tolerance.
 */
struct LaneDepartureManagerTests {
    
    // MARK: - 1) Test Initialization
    /// Verifies the manager begins with no learned widths and no departure, returning `.none` if no lines.
    @Test
    func testInitialization() async throws {
        let manager = LaneDepartureManager()
        
        let (state, debug) = manager.updateDepartureState(leftPoly: nil, rightPoly: nil)
        
        // Expect no lines => no departure
        #expect(state == .none, "Should be .none if no lines are given initially.")
        #expect(debug.contains("no detection") || debug.contains("no learned width"),
                "Expected debug mentioning missing lines or no detection.")
    }
    
    // MARK: - 2) Test No Lines => None
    /// If both left and right polynomials are nil, departure remains `.none`.
    @Test
    func testNoLinesResultsInNoDeparture() async throws {
        let manager = LaneDepartureManager()
        
        let (state, msg) = manager.updateDepartureState(leftPoly: nil, rightPoly: nil)
        #expect(state == .none, "No lines => no departure.")
        #expect(msg.contains("no detection") || msg.contains("No lines"),
                "Expected a mention of missing lines or no detection.")
    }
    
    // MARK: - 3) Test Single-Line Fallback
    /// A learned width supports both centered and displaced single-boundary observations.
    @Test
    func testSingleLineFallback() async throws {
        let manager = LaneDepartureManager()
        let stableLeft = Self.makeLanePoly(xAtY200: 250)
        let stableRight = Self.makeLanePoly(xAtY200: 262)

        for _ in 0..<5 {
            _ = manager.updateDepartureState(leftPoly: stableLeft, rightPoly: stableRight)
        }

        let learnedWidth = try #require(manager.getLearnedLaneWidth())
        #expect(learnedWidth == 12)

        let (centeredState, _) = manager.updateDepartureState(leftPoly: stableLeft, rightPoly: nil)
        #expect(centeredState == .none)

        // A displaced left boundary with no right boundary must use the learned width.
        // This checks the fallback behavior rather than accepting an unknown-state `.none`.
        let displacedLeft = Self.makeLanePoly(xAtY200: 100)
        for call in 1...5 {
            let (state, _) = manager.updateDepartureState(leftPoly: displacedLeft, rightPoly: nil)
            #expect(state == (call < 5 ? .none : .left))
        }
    }

    // MARK: - 4) Test Calibration
    /// The twentieth stable observation calibrates the center to an offset lane pair.
    @Test
    func testCalibrationAutoCentersAfterStableFrames() async throws {
        let manager = LaneDepartureManager()

        // Midpoints are 268 at y=200 and 266 at y=180: both lie within
        // 20 pixels of the initial center (256), but exceed the departure limit.
        let left = Self.makeLanePoly(xAtY200: 262)
        let right = Self.makeLanePoly(xAtY200: 274)

        for call in 1..<20 {
            let (state, _) = manager.updateDepartureState(leftPoly: left, rightPoly: right)
            #expect(state == (call < 5 ? .none : .right))
        }

        let learnedWidth = try #require(manager.getLearnedLaneWidth())
        #expect(learnedWidth == 12)

        // Calibration on call 20 changes subsequent observable behavior:
        // the same lane pair is now centered and must no longer trigger a departure.
        let (calibrationState, _) = manager.updateDepartureState(leftPoly: left, rightPoly: right)
        #expect(calibrationState == .none)
        for _ in 0..<5 {
            let (state, _) = manager.updateDepartureState(leftPoly: left, rightPoly: right)
            #expect(state == .none)
        }
    }

    // MARK: - 5) Test Consecutive Frames => Departure
    /// The fifth consecutive out-of-bounds observation produces the current `.left` state.
    @Test
    func testConsecutiveFramesTriggerDeparture() async throws {
        let manager = LaneDepartureManager()
        let stableLeft = Self.makeLanePoly(xAtY200: 250)
        let stableRight = Self.makeLanePoly(xAtY200: 262)
        for _ in 0..<3 {
            _ = manager.updateDepartureState(leftPoly: stableLeft, rightPoly: stableRight)
        }

        // Both look-ahead intersections remain inside the 512-pixel domain.
        let leftDepart = Self.makeLanePoly(xAtY200: 100)
        let rightDepart = Self.makeLanePoly(xAtY200: 112)
        for call in 1...5 {
            let (state, _) = manager.updateDepartureState(leftPoly: leftDepart, rightPoly: rightDepart)
            #expect(state == (call < 5 ? .none : .left))
        }
    }

    // MARK: - 6) Test Offset Returns Before Reaching Required Consecutive Frames
    /// A centered observation resets an incomplete four-call departure sequence.
    @Test
    func testOffsetReturnsBeforeThresholdConsecutiveFrames() async throws {
        let manager = LaneDepartureManager()
        let stableLeft = Self.makeLanePoly(xAtY200: 250)
        let stableRight = Self.makeLanePoly(xAtY200: 262)
        for _ in 0..<3 {
            _ = manager.updateDepartureState(leftPoly: stableLeft, rightPoly: stableRight)
        }

        let leftDepart = Self.makeLanePoly(xAtY200: 100)
        let rightDepart = Self.makeLanePoly(xAtY200: 112)
        for _ in 0..<4 {
            let (state, _) = manager.updateDepartureState(leftPoly: leftDepart, rightPoly: rightDepart)
            #expect(state == .none)
        }

        let (resetState, _) = manager.updateDepartureState(leftPoly: stableLeft, rightPoly: stableRight)
        #expect(resetState == .none)

        // A fresh sequence needs all five calls again; the first four must not
        // inherit the count accumulated before the centered observation.
        for call in 1...5 {
            let (state, _) = manager.updateDepartureState(leftPoly: leftDepart, rightPoly: rightDepart)
            #expect(state == (call < 5 ? .none : .left))
        }
    }

    // MARK: - Helper: Polynomial generator
    /// y = 10 * (x - xAtY200) + 200, represented as (A, B, C, D).
    /// Crosses y=200 at xAtY200 and y=180 at xAtY200-2, without search error.
    private static func makeLanePoly(xAtY200: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        return (0, 0, 10, 200 - 10 * xAtY200)
    }
}
