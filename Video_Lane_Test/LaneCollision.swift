import UIKit
import Vision

/// Manages detection of humans/animals within the lane corridor.
class LaneCollisionManager {
    private let domainWidth: Int = 1280
    private let domainHeight: Int = 720
    
    /// Number of frames in a row to confirm collision.
    private let neededCollisionFrames = 3
    
    private var consecutiveCollisionCount = 0
    private let queue = DispatchQueue(label: "com.example.LaneCollision")
    
    /// Performs collision detection; returns (didCollide, debugInfo).
    func updateCollisionState(
        leftPoly: (CGFloat,CGFloat,CGFloat,CGFloat)?,
        rightPoly: (CGFloat,CGFloat,CGFloat,CGFloat)?,
        learnedWidth: CGFloat?,
        in image: UIImage
    ) -> (Bool, String) {
        guard let cgImage = image.cgImage else {
            return (false, "No CGImage")
        }
        
        // 1) Evaluate polynomials at two Y's
        let yBot = CGFloat(domainHeight)
        let yTop = CGFloat(domainHeight) * 0.5
        let xL_bot = findX(y: yBot, poly: leftPoly, fallback: learnedWidth, isLeft: true)
        let xR_bot = findX(y: yBot, poly: rightPoly, fallback: learnedWidth, isLeft: false)
        let xL_top = findX(y: yTop, poly: leftPoly, fallback: learnedWidth, isLeft: true)
        let xR_top = findX(y: yTop, poly: rightPoly, fallback: learnedWidth, isLeft: false)
        
        guard let xl_bot = xL_bot, let xr_bot = xR_bot,
              let xl_top = xL_top, let xr_top = xR_top else {
            return (false, "Incomplete corridor")
        }
        
        // 2) Build lane corridor path
        let path = UIBezierPath()
        path.move(to: CGPoint(x: xl_bot, y: yBot))
        path.addLine(to: CGPoint(x: xr_bot, y: yBot))
        path.addLine(to: CGPoint(x: xr_top, y: yTop))
        path.addLine(to: CGPoint(x: xl_top, y: yTop))
        path.close()
        
        // 3) Prepare Vision requests
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let humanReq = VNDetectHumanRectanglesRequest()
        humanReq.upperBodyOnly = false
        let animalReq = VNRecognizeAnimalsRequest()
        
        var didDetect = false
        let group = DispatchGroup()
        
        [humanReq, animalReq].forEach { req in
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try handler.perform([req])
                    
                    // 1) Human detection returns VNHumanObservation
                    if let humans = (req as? VNDetectHumanRectanglesRequest)?.results {
                        print("[LaneCollision] Detected \(humans.count) human(s) in frame")
                        for h in humans {
                            // bottom‑center → pixel coords
                            let bb = h.boundingBox
                            let normBottomMidX = bb.minX + bb.width * 0.5
                            let normBottomY    = bb.minY
                            let px = normBottomMidX * CGFloat(self.domainWidth)
                            let py = (1 - normBottomY) * CGFloat(self.domainHeight)
                            let pt = CGPoint(x: px, y: py)
                            
                            if path.contains(pt) {
                                print("[LaneCollision] Human INSIDE corridor at \(pt)")
                                didDetect = true
                            } else {
                                print("[LaneCollision] Human outside corridor at \(pt)")
                            }
                        }
                    }
                    
                    // 2) Animal detection returns VNRecognizedObjectObservation
                    if let animals = (req as? VNRecognizeAnimalsRequest)?.results {
                        print("[LaneCollision] Detected \(animals.count) animal(s) in frame")
                        for a in animals {
                            let abb = a.boundingBox
                            let normAnimalMidX = abb.minX + abb.width * 0.5
                            let normAnimalY    = abb.minY
                            let ax = normAnimalMidX * CGFloat(self.domainWidth)
                            let ay = (1 - normAnimalY) * CGFloat(self.domainHeight)
                            let pt = CGPoint(x: ax, y: ay)
                            
                            if path.contains(pt) {
                                print("[LaneCollision] Animal INSIDE corridor at \(pt)")
                                didDetect = true
                            } else {
                                print("[LaneCollision] Animal outside corridor at \(pt)")
                            }
                        }
                    }
                } catch {
                    // ignore errors for this frame
                }
            }
        }
        
        group.wait()
        
        // 4) Debounce: require N frames in succession
        if didDetect {
            consecutiveCollisionCount += 1
        } else {
            consecutiveCollisionCount = 0
        }
        let collided = consecutiveCollisionCount >= neededCollisionFrames
        
        let debug = "Bot:\(xl_bot),\(xr_bot) Top:\(xl_top),\(xr_top) → detect:\(didDetect)"
        return (collided, debug)
    }
    
    /// Solve for X at a given Y, or fallback to learned width.
    private func findX(
        y: CGFloat,
        poly: (CGFloat,CGFloat,CGFloat,CGFloat)?,
        fallback: CGFloat?,
        isLeft: Bool
    ) -> CGFloat? {
        if let (A,B,C,D) = poly {
            var bestX: CGFloat = 0
            var bestDist = CGFloat.greatestFiniteMagnitude
            for x in 0..<domainWidth {
                let xx = CGFloat(x)
                let yy = cubicEval(x: xx, A: A, B: B, C: C, D: D)
                let d = abs(yy - y)
                if d < bestDist {
                    bestDist = d
                    bestX = xx
                }
            }
            return bestDist < 5 ? bestX : nil
        }
        // fallback: one side missing, use learnedWidth
        if let w = fallback {
            return isLeft
                ? CGFloat(domainWidth)/2 - w/2
                : CGFloat(domainWidth)/2 + w/2
        }
        return nil
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
