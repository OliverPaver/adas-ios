
import Foundation

/**
 Manages lane departure warnings given polynomial outputs from LaneDetector.
 Uses multiple look-ahead Y positions near the bottom of the image and tracks
 rolling averages for lane widths. Automatically calibrates the car center
 if frames appear stable for a certain number of consecutive frames.
*/
class LaneDepartureManager {
    private let domainWidth: Int = 512
    private let domainHeight: Int = 256
    
    private let lookAheadY1: Int = 200
    private let lookAheadY2: Int = 180
    
    private var carCenterX: CGFloat = 256.0
    private var isCalibrated = false
    private var stableFrameCount = 0
    private var sumOfMidpoints: CGFloat = 0.0
    private let stableFramesNeeded = 20
    
    private var widthHistoryY1 = RollingAverage(capacity: 10)
    private var widthHistoryY2 = RollingAverage(capacity: 10)
    
    private let stableCarOffsetThreshold: CGFloat = 20.0
    
    private var consecutiveDepartureFrames = 0
    private let neededDepartureFrames = 5
    
    enum DepartureState {
        case none
        case left
        case right
    }
    
    init() {}
    
    /**
     Updates lane departure state using polynomials for left and right lanes. Returns
     (DepartureState, debugString). The debug string can be used for logging or overlays.
    */
    func updateDepartureState(leftPoly: (CGFloat,CGFloat,CGFloat,CGFloat)?,
                              rightPoly: (CGFloat,CGFloat,CGFloat,CGFloat)?)
    -> (DepartureState, String)
    {
        // Looks up to two Y positions to find x-coordinates for left and right lanes
        var pairs = [(Int, CGFloat?, CGFloat?)]()
        for yLook in [lookAheadY1, lookAheadY2] {
            let xLeft = findXForY(yWanted: CGFloat(yLook), poly: leftPoly)
            let xRight = findXForY(yWanted: CGFloat(yLook), poly: rightPoly)
            pairs.append((yLook, xLeft, xRight))
        }
        
        // Attempts to measure lane widths if both lines exist
        var measuredWidths = [CGFloat]()
        var measuredMidpoints = [CGFloat]()
        
        for (_, xL, xR) in pairs {
            guard let xl = xL, let xr = xR else { continue }
            let laneWidth = xr - xl
            if laneWidth < 0 { continue }
            
            let midpoint = (xl + xr) * 0.5
            measuredWidths.append(laneWidth)
            measuredMidpoints.append(midpoint)
        }
        
        // Updates rolling averages for lane width if the midpoint is stable
        var stableCount = 0
        for mid in measuredMidpoints {
            let offset = abs(mid - carCenterX)
            if offset < stableCarOffsetThreshold {
                stableCount += 1
            }
        }
        if !measuredWidths.isEmpty && stableCount == measuredWidths.count {
            let avgWidth = measuredWidths.reduce(0, +) / CGFloat(measuredWidths.count)
            widthHistoryY1.addValue(avgWidth)
            widthHistoryY2.addValue(avgWidth)
        }
        
        // Automatic calibration if not already calibrated and measurements are stable
        if !isCalibrated && !measuredMidpoints.isEmpty && stableCount == measuredMidpoints.count {
            let localMid = measuredMidpoints.reduce(0, +) / CGFloat(measuredMidpoints.count)
            stableFrameCount += 1
            sumOfMidpoints += localMid
            
            if stableFrameCount >= stableFramesNeeded {
                let newCenter = sumOfMidpoints / CGFloat(stableFrameCount)
                carCenterX = newCenter
                isCalibrated = true
                stableFrameCount = 0
                sumOfMidpoints = 0
                return (.none, "Calibration done => new center=\(carCenterX)")
            }
        } else if !isCalibrated {
            // Resets if this frame is not stable
            stableFrameCount = 0
            sumOfMidpoints = 0
        }
        
        // Lane departure logic checks offsets from the calibrated center
        let yCheck = lookAheadY1
        let xLeft = findXForY(yWanted: CGFloat(yCheck), poly: leftPoly)
        let xRight = findXForY(yWanted: CGFloat(yCheck), poly: rightPoly)
        
        var finalLeft: CGFloat?
        var finalRight: CGFloat?
        let learnedWidth = getLearnedLaneWidth()
        
        switch (xLeft, xRight, learnedWidth) {
        case let (.some(lx), .some(rx), _):
            finalLeft = lx
            finalRight = rx
        case let (.some(lx), nil, .some(w)):
            finalLeft = lx
            finalRight = lx + w
        case let (nil, .some(rx), .some(w)):
            finalRight = rx
            finalLeft = rx - w
        default:
            return (.none, "No lines or no learned width => no detection")
        }
        
        guard let leftX = finalLeft,
              let rightX = finalRight,
              rightX > leftX else {
            return (.none, "Could not finalize left/right boundaries => no detection")
        }
        
        let laneMid = (leftX + rightX) * 0.5
        let offsetFromCenter = laneMid - carCenterX
        let halfWidth = (rightX - leftX) * 0.5
        let departureFraction: CGFloat = 0.4
        
        // Defines a threshold for departure based on lane width
        let departureLimit = departureFraction * halfWidth
        let absOffset = abs(offsetFromCenter)
        
        // Increments a counter if offset is beyond the threshold, then confirms departure
        if absOffset > departureLimit {
            consecutiveDepartureFrames += 1
            if consecutiveDepartureFrames >= neededDepartureFrames {
                let side: DepartureState = (offsetFromCenter > 0) ? .right : .left
                return (side, "Departing \(side). offset=\(offsetFromCenter)")
            } else {
                return (.none, "offset=\(offsetFromCenter) over limit but not 5 frames in a row.")
            }
        } else {
            // Reset if offset is within normal bounds
            consecutiveDepartureFrames = 0
            return (.none, "No departure. offset=\(offsetFromCenter)")
        }
    }
    
    /// Returns an average lane width from stored rolling averages, or nil if insufficient data
    func getLearnedLaneWidth() -> CGFloat? {
        if widthHistoryY1.count() == 0 && widthHistoryY2.count() == 0 {
            return nil
        }
        let avg1 = widthHistoryY1.currentAverage() ?? 0
        let avg2 = widthHistoryY2.currentAverage() ?? 0
        
        if widthHistoryY1.count() > 0 && widthHistoryY2.count() > 0 {
            return (avg1 + avg2) * 0.5
        } else if widthHistoryY1.count() > 0 {
            return avg1
        } else {
            return avg2
        }
    }
    
    /**
     Searches for the x-value that yields yWanted in a cubic polynomial.
     The polynomial is evaluated across x in [0..domainWidth-1], and the x
     with minimal distance to yWanted is returned if within a certain tolerance.
    */
    private func findXForY(yWanted: CGFloat,
                           poly: (CGFloat,CGFloat,CGFloat,CGFloat)?) -> CGFloat? {
        guard let (A,B,C,D) = poly else { return nil }
        
        var bestX: CGFloat = -1
        var bestDist: CGFloat = .greatestFiniteMagnitude
        let maxAllowedDist: CGFloat = 7.0
        
        for x in 0..<domainWidth {
            let xx = CGFloat(x)
            let yy = cubicEval(x: xx, A: A, B: B, C: C, D: D)
            let dist = abs(yy - yWanted)
            if dist < bestDist {
                bestDist = dist
                bestX = xx
            }
        }
        
        if bestDist > maxAllowedDist {
            return nil
        }
        return bestX
    }
    
    /// Evaluates a cubic polynomial A*x^3 + B*x^2 + C*x + D
    private func cubicEval(x: CGFloat,
                           A: CGFloat,
                           B: CGFloat,
                           C: CGFloat,
                           D: CGFloat) -> CGFloat {
        return A*x*x*x + B*x*x + C*x + D
    }
}

// MARK: - RollingAverage Helper
fileprivate class RollingAverage {
    private let capacity: Int
    private var values = [CGFloat]()
    private var sum: CGFloat = 0
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    /// Adds a new value and removes the oldest if capacity is exceeded
    func addValue(_ val: CGFloat) {
        values.append(val)
        sum += val
        if values.count > capacity {
            let old = values.removeFirst()
            sum -= old
        }
    }
    
    /// Returns the current average of all stored values, or nil if none
    func currentAverage() -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return sum / CGFloat(values.count)
    }
    
    /// Returns the count of stored values
    func count() -> Int {
        return values.count
    }
}
