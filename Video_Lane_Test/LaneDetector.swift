
import CoreML
import Accelerate
import simd
import MetalKit
import QuartzCore

/**
 Implements a lane detection pipeline using the LaneNet Core ML model and various
 post-processing steps (morphology, DBSCAN, and polynomial fitting). Produces an
 overlay image for lane visualization, along with polynomial coefficients for
 lane departure checks.
*/
class LaneDetector {
    // MARK: - LaneNet Model
    private let laneNetModel: LaneNet = {
        do {
            print("[DEBUG] Loading LaneNet model...")
            let m = try LaneNet(configuration: MLModelConfiguration())
            print("[DEBUG] LaneNet loaded.")
            return m
        } catch {
            fatalError("Could not load LaneNet: \(error)")
        }
    }()
    
    // Processes only the bottom portion of each frame
    private let bottomCropRatio: CGFloat = 0.60
    
    // Stores a transparent overlay containing lane lines
    private var latestLinesOverlay: UIImage? = nil
    
    // Stores the newest unprocessed frame
    private var latestFrameBuffer: UIImage? = nil
    
    // Indicates whether a frame is currently being processed in the background
    private var isProcessing: Bool = false
    
    // MARK: - EGO Lane Polynomials
    private(set) var egoLeftPoly: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil
    private(set) var egoRightPoly: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil
    
    // Queues
    private let lockQueue = DispatchQueue(label: "com.example.laneDetector.lock")
    private let backgroundQueue = DispatchQueue(label: "com.example.laneDetector.background",
                                               qos: .userInitiated)
    
    init() {
        // Launches a background loop that processes frames asynchronously
        backgroundQueue.async { [weak self] in
            self?.backgroundLoop()
        }
    }
    
    /**
     Called on the main thread with each new camera/video frame. Updates
     the internal frame buffer and returns a composite of the current frame
     and any last known lane overlay.
    */
    func feedFrame(_ uiImage: UIImage) -> UIImage? {
        lockQueue.sync {
            latestFrameBuffer = uiImage
        }
        
        var linesCopy: UIImage?
        lockQueue.sync {
            linesCopy = latestLinesOverlay
        }
        
        // Returns the raw frame if no lane overlay is available
        if let overlay = linesCopy {
            return blend(bg: uiImage, fg: overlay, alpha: 1.0)
        } else {
            return uiImage
        }
    }
    
    /**
     The indefinite background loop that checks for new frames to process.
     Processes frames in the pipeline and produces lane overlays.
    */
    private func backgroundLoop() {
        while true {
            autoreleasepool {
                var frameToProcess: UIImage?
                
                // Grabs a frame to process if one is available and not already processing
                lockQueue.sync {
                    if !isProcessing, let f = latestFrameBuffer {
                        frameToProcess = f
                        isProcessing = true
                        latestFrameBuffer = nil
                    }
                }
                
                if let frame = frameToProcess {
                    let frameStart = CACurrentMediaTime()
                    let group = DispatchGroup()
                    group.enter()
                    
                    var newLinesOverlay: UIImage?
                    
                    // Runs lane detection pipeline on a separate queue
                    DispatchQueue.global(qos: .userInitiated).async {
                        newLinesOverlay = self.runFullLanePipeline(frame)
                        group.leave()
                    }
                    
                    // Waits up to 2 seconds for pipeline completion
                    let result = group.wait(timeout: .now() + 2.0)
                    
                    lockQueue.sync {
                        if result == .timedOut {
                            print("[DEBUG] runFullLanePipeline stalled. Resetting state...")
                            self.isProcessing = false
                            self.latestFrameBuffer = nil
                            self.latestLinesOverlay = nil
                            self.egoLeftPoly = nil
                            self.egoRightPoly = nil
                        } else {
                            self.latestLinesOverlay = newLinesOverlay
                            self.isProcessing = false
                            let frameTotal = (CACurrentMediaTime() - frameStart) * 1000
                            print("[TIME] Total per-frame (including queueing): \(frameTotal) ms")
                        }
                    }
                } else {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
    }

    /**
     The full pipeline: crops the bottom portion, resizes to 512x256,
     runs LaneNet, morphological ops, DBSCAN, cluster selection,
     polynomial fitting & drawing, and re-placement.
    */
    private func runFullLanePipeline(_ frame: UIImage) -> UIImage? {
        autoreleasepool {
            let pipelineStart = CACurrentMediaTime()
            var t0 = pipelineStart
            
            // 1) Crop
            guard let cropped = cropBottomPortion(frame, ratio: bottomCropRatio) else { return nil }
            let t1 = CACurrentMediaTime()
            print("[TIME] Crop time: \((t1 - t0) * 1000) ms")
            t0 = t1
            
            // 2) Resize + toMLMultiArray
            guard let resized = cropped.resized(to: CGSize(width: 512, height: 256)),
                  let resizedArr = resized.toMLMultiArrayRGB() else { return nil }
            let t2 = CACurrentMediaTime()
            print("[TIME] Resize + toML array time: \((t2 - t0) * 1000) ms")
            t0 = t2
            
            // 3) Model inference
            guard let output = try? laneNetModel.prediction(input: LaneNetInput(lanenet_input_tensor: resizedArr)) else { return nil }
            let t3 = CACurrentMediaTime()
            print("[TIME] Model inference time: \((t3 - t0) * 1000) ms")
            t0 = t3
            
            // 4) Output conversion
            guard let binFloats = output.lanenet_final_binary_output.toFloatArray(),
                  let embFloats = output.lanenet_final_pixel_embedding_output.toFloatArray() else { return nil }
            let t4 = CACurrentMediaTime()
            print("[TIME] Output → FloatArray time: \((t4 - t0) * 1000) ms")
            t0 = t4
            
            // 5) Morphological cleanup
            let binMask = doMorphPipeline(binFloats, 512, 256)
            let t5 = CACurrentMediaTime()
            print("[TIME] Morph pipeline time: \((t5 - t0) * 1000) ms")
            t0 = t5
            
            // 6) Gather embeddings
            let (coords, feats) = gatherEmbeddings(binMask, embFloats, 512, 256)
            let t6 = CACurrentMediaTime()
            print("[TIME] Gather embeddings time: \((t6 - t0) * 1000) ms")
            t0 = t6
            
            // 7) DBSCAN clustering
            let simdData = feats.map { SIMD4<Double>(Double($0[0]), Double($0[1]), Double($0[2]), Double($0[3])) }
            let clusters = runDBSCANMetal(data: simdData, coords: coords,
                                          epsilon: 0.35, minPoints: 800)
            let t7 = CACurrentMediaTime()
            print("[TIME] DBSCAN clustering time: \((t7 - t0) * 1000) ms")
            t0 = t7
            
            // 8) Identify ego clusters
            let (leftCluster, rightCluster) = findEgoClusters(clusters: clusters,
                                                              width: 512, height: 256)
            let t8 = CACurrentMediaTime()
            print("[TIME] Find ego-clusters time: \((t8 - t0) * 1000) ms")
            t0 = t8
            
            // 9) RANSAC & draw
            let linesOverlaySmall = drawEgoClusters(leftCluster, rightCluster,
                                                    baseSize: CGSize(width: 512, height: 256))
            let t9 = CACurrentMediaTime()
            print("[TIME] RANSAC & draw time: \((t9 - t0) * 1000) ms")
            t0 = t9
            
            // 10) Resize overlay
            guard let overlayResized = linesOverlaySmall?.resized(to: cropped.size) else { return nil }
            let t10 = CACurrentMediaTime()
            print("[TIME] Overlay resize time: \((t10 - t0) * 1000) ms")
            t0 = t10
            
            // 11) Place back into full frame
            let offsetY = frame.size.height * (1.0 - bottomCropRatio)
            let linesFullFrame = placeOverlayInFullFrame(overlayResized,
                                                         fullSize: frame.size,
                                                         offset: CGPoint(x: 0, y: offsetY))
            let pipelineEnd = CACurrentMediaTime()
            print("[TIME] Total pipeline time: \((pipelineEnd - pipelineStart) * 1000) ms")
            
            return linesFullFrame
        }
    }

    // MARK: - Setting Lane Polynomials
    private func setLeftPoly(_ poly: (CGFloat,CGFloat,CGFloat,CGFloat)?) {
        egoLeftPoly = poly
    }
    
    private func setRightPoly(_ poly: (CGFloat,CGFloat,CGFloat,CGFloat)?) {
        egoRightPoly = poly
    }
    
    /**
     Finds two clusters that correspond to the left and right lanes.
     Examines the bottom region of each cluster to see if it is near the center
     of the frame and partitions candidates into left or right sides.
    */
    private func findEgoClusters(clusters: [LaneCluster],
                                 width: Int,
                                 height: Int) -> (LaneCluster?, LaneCluster?) {
        if clusters.isEmpty { return (nil, nil) }
        
        let bottomThreshold = Int(Double(height) * 0.65)
        let centerX = CGFloat(width) / 2.0
        
        var leftCandidates = [(LaneCluster, CGFloat)]()
        var rightCandidates = [(LaneCluster, CGFloat)]()
        
        for c in clusters {
            let bottomPoints = c.points.filter { $0.1 >= bottomThreshold }
            if bottomPoints.isEmpty { continue }
            
            let sumX = bottomPoints.reduce(0.0) { $0 + CGFloat($1.0) }
            let meanX = sumX / CGFloat(bottomPoints.count)
            
            let dx = meanX - centerX
            if dx < 0 {
                let dist = abs(dx)
                leftCandidates.append((c, dist))
            } else {
                let dist = abs(dx)
                rightCandidates.append((c, dist))
            }
        }
        
        leftCandidates.sort { $0.1 < $1.1 }
        rightCandidates.sort { $0.1 < $1.1 }
        
        let leftCluster = leftCandidates.first?.0
        let rightCluster = rightCandidates.first?.0
        
        return (leftCluster, rightCluster)
    }
    
    /**
     Draws the identified left and right clusters by using RANSAC to fit
     cubic curves. Polynomials are stored for external use.
     Returns a small overlay image (512x256) that highlights those lanes.
    */
    private func drawEgoClusters(_ leftC: LaneCluster?,
                                 _ rightC: LaneCluster?,
                                 baseSize: CGSize) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary() else {
            print("[ERROR] Could not set up Metal for drawing EGO clusters.")
            return nil
        }
        
        let w = Int(baseSize.width)
        let h = Int(baseSize.height)
        
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .rgba8Unorm
        desc.width = w
        desc.height = h
        desc.usage = [.shaderWrite, .shaderRead]
        
        guard let overlayTex = device.makeTexture(descriptor: desc) else {
            return nil
        }
        
        guard let clearFn = library.makeFunction(name: "clearOverlayTexture"),
              let drawFn  = library.makeFunction(name: "drawPointsKernel") else {
            return nil
        }
        
        do {
            let clearPipeline = try device.makeComputePipelineState(function: clearFn)
            let drawPipeline  = try device.makeComputePipelineState(function: drawFn)
            
            guard let cmdBuf = queue.makeCommandBuffer() else {
                return nil
            }
            
            // Clears the texture to transparent
            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(clearPipeline)
                encoder.setTexture(overlayTex, index: 0)
                
                let tw = clearPipeline.threadExecutionWidth
                let th = clearPipeline.maxTotalThreadsPerThreadgroup / tw
                let threadsPerGroup = MTLSize(width: tw, height: th, depth: 1)
                let tgW = (w + tw - 1) / tw
                let tgH = (h + th - 1) / th
                let numTG = MTLSize(width: tgW, height: tgH, depth: 1)
                
                encoder.dispatchThreadgroups(numTG, threadsPerThreadgroup: threadsPerGroup)
                encoder.endEncoding()
            }
            
            var linePoints = [LinePoint]()
            
            // Fits polynomials on left cluster
            if let l = leftC {
                if let (A,B,C,D) = doRANSACandDraw(l,
                                                   color: SIMD4<Float>(1,0,0,1),
                                                   width: w,
                                                   height: h,
                                                   into: &linePoints) {
                    setLeftPoly((A,B,C,D))
                } else {
                    setLeftPoly(nil)
                }
            } else {
                setLeftPoly(nil)
            }
            
            // Fits polynomials on right cluster
            if let r = rightC {
                if let (A,B,C,D) = doRANSACandDraw(r,
                                                   color: SIMD4<Float>(0,1,0,1),
                                                   width: w,
                                                   height: h,
                                                   into: &linePoints) {
                    setRightPoly((A,B,C,D))
                } else {
                    setRightPoly(nil)
                }
            } else {
                setRightPoly(nil)
            }
            
            // Skips the draw pass if linePoints is empty
            if linePoints.isEmpty {
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()
                return textureToUIImage(texture: overlayTex)
            }
            
            // Draws line segments onto the overlay texture
            guard let cmdEnc = cmdBuf.makeComputeCommandEncoder() else {
                return nil
            }
            cmdEnc.setComputePipelineState(drawPipeline)
            cmdEnc.setTexture(overlayTex, index: 0)
            
            let totalPoints = linePoints.count
            let lpSize = MemoryLayout<LinePoint>.stride * totalPoints
            guard let lpBuf = device.makeBuffer(bytes: linePoints,
                                                length: lpSize,
                                                options: []) else {
                return nil
            }
            cmdEnc.setBuffer(lpBuf, offset: 0, index: 0)
            
            var lineCount = UInt32(totalPoints)
            guard let lineCountBuf = device.makeBuffer(bytes: &lineCount,
                                                       length: MemoryLayout<UInt32>.size,
                                                       options: []) else {
                return nil
            }
            cmdEnc.setBuffer(lineCountBuf, offset: 0, index: 1)
            
            let tpg = drawPipeline.maxTotalThreadsPerThreadgroup
            let threadsPerGroup = MTLSize(width: tpg, height: 1, depth: 1)
            let numTG = MTLSize(width: (totalPoints + tpg - 1)/tpg,
                                height: 1,
                                depth: 1)
            cmdEnc.dispatchThreadgroups(numTG, threadsPerThreadgroup: threadsPerGroup)
            cmdEnc.endEncoding()
            
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            
            return textureToUIImage(texture: overlayTex)
        } catch {
            print("[ERROR] \(error)")
            return nil
        }
    }
    
    /**
     Applies RANSAC on a given cluster to find a cubic polynomial. Draws the
     resulting line segments into an array of points for later rendering.
    */
    private func doRANSACandDraw(_ cluster: LaneCluster,
                                 color: SIMD4<Float>,
                                 width: Int,
                                 height: Int,
                                 into linePoints: inout [LinePoint])
    -> (CGFloat,CGFloat,CGFloat,CGFloat)?
    {
        let pts = cluster.points.map { CGPoint(x: CGFloat($0.0), y: CGFloat($0.1)) }
        if pts.count < 4 { return nil }
        
        let (_,_,_,_,inliers) = batchRANSACCubic(points: pts,
                                                 totalIters: 200,
                                                 batchSize: 50,
                                                 threshold: 3.0)
        if inliers.count < 4 {
            return nil
        }
        
        if let (A2,B2,C2,D2) = solveCubicLeastSquares(inliers) {
            let xs = inliers.map { $0.x }
            let ys = inliers.map { $0.y }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else {
                return nil
            }
            
            let clampedMinX = max(minX, 0)
            let clampedMaxX = min(maxX, CGFloat(width - 1))
            let clampedMinY = max(minY, 0)
            let clampedMaxY = min(maxY, CGFloat(height - 1))
            
            var started = false
            var prev: CGPoint?
            for xVal in stride(from: clampedMinX, through: clampedMaxX, by: 1) {
                let yVal = cubicEval(x: xVal, A: A2, B: B2, C: C2, D: D2)
                if yVal < clampedMinY || yVal > clampedMaxY {
                    if started { started = false }
                    prev = nil
                    continue
                }
                let pt = CGPoint(x: xVal, y: yVal)
                if !started {
                    started = true
                    prev = pt
                } else if let pp = prev {
                    let seg = rasterizeLineSegment(from: pp, to: pt,
                                                   maxW: width, maxH: height)
                    for sp in seg {
                        linePoints.append(LinePoint(x: UInt16(sp.x),
                                                    y: UInt16(sp.y),
                                                    color: color))
                    }
                    prev = pt
                }
            }
            
            return (A2,B2,C2,D2)
        }
        return nil
    }
    
    /**
     Places a smaller overlay image back into the original frame's coordinates at
     a given offset.
    */
    private func placeOverlayInFullFrame(_ overlay: UIImage,
                                         fullSize: CGSize,
                                         offset: CGPoint) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(fullSize, false, 1.0)
        overlay.draw(in: CGRect(origin: offset, size: overlay.size))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
    }
    
    /// Blends a foreground image over a background image with a given alpha
    private func blend(bg: UIImage, fg: UIImage, alpha: CGFloat) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(bg.size, false, 1.0)
        bg.draw(in: CGRect(origin: .zero, size: bg.size))
        fg.draw(in: CGRect(origin: .zero, size: bg.size),
                blendMode: .normal,
                alpha: alpha)
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
    }
    
    /// Crops the bottom portion of an image by a given ratio (0..1)
    private func cropBottomPortion(_ image: UIImage, ratio: CGFloat) -> UIImage? {
        let origW = image.size.width
        let origH = image.size.height
        let cropH = origH * ratio
        let cropY = origH - cropH
        let rect = CGRect(x: 0, y: cropY, width: origW, height: cropH)
        
        guard let cg = image.cgImage,
              let cropped = cg.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: cropped,
                       scale: image.scale,
                       orientation: image.imageOrientation)
    }
    
    // MARK: - GPU DBSCAN (Metal)
    func runDBSCANMetal(data: [SIMD4<Double>],
                        coords: [(Int, Int)],
                        epsilon: Double,
                        minPoints: Int) -> [LaneCluster] {
        let floatData: [SIMD4<Float>] = data.map {
            SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), Float($0.w))
        }
        if floatData.isEmpty { return [] }
        let numPoints = UInt32(floatData.count)
        let epsilonSquared = Float(epsilon * epsilon)
        
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("[ERROR] Metal device or command queue unavailable for DBSCAN.")
            return []
        }
        guard let library = device.makeDefaultLibrary() else {
            print("[ERROR] Could not load Metal library for DBSCAN.")
            return []
        }
        
        guard let markCoreFunction = library.makeFunction(name: "markCorePoints"),
              let initLabelsFunction = library.makeFunction(name: "initializeLabels"),
              let propagateFunction = library.makeFunction(name: "propagateLabels") else {
            print("[ERROR] Could not load DBSCAN metal functions.")
            return []
        }
        
        let markCorePipeline = try? device.makeComputePipelineState(function: markCoreFunction)
        let initLabelsPipeline = try? device.makeComputePipelineState(function: initLabelsFunction)
        let propagatePipeline = try? device.makeComputePipelineState(function: propagateFunction)
        
        guard let markP = markCorePipeline,
              let initP = initLabelsPipeline,
              let propP = propagatePipeline else {
            print("[ERROR] Could not create pipeline states for DBSCAN.")
            return []
        }
        
        let dataBuffer = device.makeBuffer(bytes: floatData,
                                           length: floatData.count * MemoryLayout<SIMD4<Float>>.stride,
                                           options: [])
        var numPointsUInt = numPoints
        let numPointsBuffer = device.makeBuffer(bytes: &numPointsUInt,
                                                length: MemoryLayout<UInt32>.size,
                                                options: [])
        var epsSq = Float(epsilonSquared)
        let epsilonBuffer = device.makeBuffer(bytes: &epsSq,
                                              length: MemoryLayout<Float>.size,
                                              options: [])
        var minPointsUInt = UInt32(minPoints)
        let minPointsBuffer = device.makeBuffer(bytes: &minPointsUInt,
                                                length: MemoryLayout<UInt32>.size,
                                                options: [])
        
        var coreFlags = [Int32](repeating: 0, count: Int(numPoints))
        let coreFlagsBuffer = device.makeBuffer(bytes: &coreFlags,
                                                length: MemoryLayout<Int32>.stride * Int(numPoints),
                                                options: [])
        
        var labels = [Int32](repeating: -1, count: Int(numPoints))
        let labelsBuffer = device.makeBuffer(bytes: &labels,
                                             length: MemoryLayout<Int32>.stride * Int(numPoints),
                                             options: [])
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("[ERROR] Could not create command buffer for DBSCAN.")
            return []
        }
        
        let threadsPerGroup = MTLSize(width: markP.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        let numThreadgroups = MTLSize(width: (Int(numPoints) + threadsPerGroup.width - 1) / threadsPerGroup.width,
                                      height: 1,
                                      depth: 1)
        
        // 1) Mark core points
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(markP)
            encoder.setBuffer(dataBuffer, offset: 0, index: 0)
            encoder.setBuffer(coreFlagsBuffer, offset: 0, index: 1)
            encoder.setBuffer(numPointsBuffer, offset: 0, index: 2)
            encoder.setBuffer(epsilonBuffer, offset: 0, index: 3)
            encoder.setBuffer(minPointsBuffer, offset: 0, index: 4)
            encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        // 2) Initialize labels
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(initP)
            encoder.setBuffer(labelsBuffer, offset: 0, index: 0)
            encoder.setBuffer(numPointsBuffer, offset: 0, index: 1)
            encoder.setBuffer(coreFlagsBuffer, offset: 0, index: 2)
            encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
        
        // 3) Propagate labels over multiple iterations
        let iterations = 10
        for _ in 0..<iterations {
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(propP)
                encoder.setBuffer(dataBuffer, offset: 0, index: 0)
                encoder.setBuffer(labelsBuffer, offset: 0, index: 1)
                encoder.setBuffer(numPointsBuffer, offset: 0, index: 2)
                encoder.setBuffer(epsilonBuffer, offset: 0, index: 3)
                encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
                encoder.endEncoding()
            }
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let labelsPointer = labelsBuffer?.contents().bindMemory(to: Int32.self, capacity: Int(numPoints))
        var finalLabels = [Int32](repeating: -1, count: Int(numPoints))
        for i in 0..<Int(numPoints) {
            finalLabels[i] = labelsPointer![i]
        }
        
        // Groups pixels by cluster label
        var clusterDict = [Int: [(Int, Int)]]()
        for i in 0..<finalLabels.count {
            let label = finalLabels[i]
            if label != -1 {
                clusterDict[Int(label), default: []].append(coords[i])
            }
        }
        
        var laneClusters = [LaneCluster]()
        for (label, pts) in clusterDict {
            laneClusters.append(LaneCluster(points: pts, label: label))
        }
        return laneClusters
    }
    
    // MARK: - GPU RANSAC for Cubic Fitting
    private func batchRANSACCubic(points: [CGPoint],
                                  totalIters: Int = 200,
                                  batchSize: Int = 50,
                                  threshold: CGFloat = 3.0)
    -> (CGFloat, CGFloat, CGFloat, CGFloat, [CGPoint])
    {
        if points.count < 4 {
            return (0,0,0,0,[])
        }
        
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(),
              let kernelCheck = library.makeFunction(name: "batchCheckInliersCubic"),
              let kernelSum  = library.makeFunction(name: "sumInliersCubic")
        else {
            print("[ERROR] GPU RANSAC not available. Returning empty.")
            return (0,0,0,0,[])
        }
        
        guard let pipelineCheck = try? device.makeComputePipelineState(function: kernelCheck),
              let pipelineSum   = try? device.makeComputePipelineState(function: kernelSum)
        else {
            print("[ERROR] Could not create RANSAC pipeline states. Empty.")
            return (0,0,0,0,[])
        }
        
        let floatPoints = points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        let numPoints = floatPoints.count
        
        guard let pointsBuf = device.makeBuffer(bytes: floatPoints,
                                                length: MemoryLayout<SIMD2<Float>>.stride * numPoints,
                                                options: [])
        else {
            print("[ERROR] Could not create pointsBuf.")
            return (0,0,0,0,[])
        }
        
        var npUInt = UInt32(numPoints)
        guard let npBuf = device.makeBuffer(bytes: &npUInt,
                                            length: MemoryLayout<UInt32>.size,
                                            options: [])
        else { return (0,0,0,0,[]) }
        
        let thrF = Float(threshold)
        guard let thrBuf = device.makeBuffer(bytes: [thrF],
                                             length: MemoryLayout<Float>.size,
                                             options: [])
        else { return (0,0,0,0,[]) }
        
        let passes = (totalIters + batchSize - 1) / batchSize
        var bestCount = -1
        var bestCoeffs: (CGFloat,CGFloat,CGFloat,CGFloat) = (0,0,0,0)
        var bestInliers = [CGPoint]()
        
        for _ in 0..<passes {
            // Creates random sets of four points and solves for a cubic polynomial
            var modelArr = [SIMD4<Float>]()
            modelArr.reserveCapacity(batchSize)
            var created = 0
            while created < batchSize {
                guard let p1 = points.randomElement(),
                      let p2 = points.randomElement(),
                      let p3 = points.randomElement(),
                      let p4 = points.randomElement() else {
                    continue
                }
                if let (A,B,C,D) = solveCubic(p1, p2, p3, p4) {
                    modelArr.append(SIMD4<Float>(Float(A), Float(B), Float(C), Float(D)))
                    created += 1
                }
            }
            
            let actualBatch = created
            if actualBatch <= 0 { continue }
            
            guard let modelBuf = device.makeBuffer(bytes: modelArr,
                                                   length: MemoryLayout<SIMD4<Float>>.stride * actualBatch,
                                                   options: [])
            else { continue }
            
            var nmUInt = UInt32(actualBatch)
            guard let nmBuf = device.makeBuffer(bytes: &nmUInt,
                                                length: MemoryLayout<UInt32>.size,
                                                options: [])
            else { continue }
            
            let totalThreads = actualBatch * numPoints
            var zeroArr = [Int32](repeating: 0, count: totalThreads)
            guard let inliersBuf = device.makeBuffer(bytes: zeroArr,
                                                     length: MemoryLayout<Int32>.stride * totalThreads,
                                                     options: [])
            else { continue }
            
            var modelCounts = [Int32](repeating: 0, count: actualBatch)
            guard let modelCountsBuf = device.makeBuffer(bytes: &modelCounts,
                                                         length: MemoryLayout<Int32>.stride * actualBatch,
                                                         options: [])
            else { continue }
            
            guard let cmdBuf = queue.makeCommandBuffer(),
                  let encoder1 = cmdBuf.makeComputeCommandEncoder() else { continue }
            
            encoder1.setComputePipelineState(pipelineCheck)
            encoder1.setBuffer(pointsBuf, offset: 0, index: 0)
            encoder1.setBuffer(modelBuf, offset: 0, index: 1)
            encoder1.setBuffer(inliersBuf, offset: 0, index: 2)
            encoder1.setBuffer(npBuf, offset: 0, index: 3)
            encoder1.setBuffer(nmBuf, offset: 0, index: 4)
            encoder1.setBuffer(thrBuf, offset: 0, index: 5)
            
            let w1 = pipelineCheck.maxTotalThreadsPerThreadgroup
            let threadsPerGroup1 = MTLSize(width: w1, height: 1, depth: 1)
            let numTG1 = MTLSize(width: (totalThreads + w1 - 1)/w1,
                                 height: 1,
                                 depth: 1)
            encoder1.dispatchThreadgroups(numTG1, threadsPerThreadgroup: threadsPerGroup1)
            encoder1.endEncoding()
            
            if let encoder2 = cmdBuf.makeComputeCommandEncoder() {
                encoder2.setComputePipelineState(pipelineSum)
                encoder2.setBuffer(inliersBuf, offset: 0, index: 0)
                encoder2.setBuffer(modelCountsBuf, offset: 0, index: 1)
                encoder2.setBuffer(npBuf, offset: 0, index: 2)
                encoder2.setBuffer(nmBuf, offset: 0, index: 3)
                
                let w2 = pipelineSum.maxTotalThreadsPerThreadgroup
                let threadsPerGroup2 = MTLSize(width: w2, height: 1, depth: 1)
                let numTG2 = MTLSize(width: (actualBatch + w2 - 1)/w2,
                                     height: 1,
                                     depth: 1)
                encoder2.dispatchThreadgroups(numTG2, threadsPerThreadgroup: threadsPerGroup2)
                encoder2.endEncoding()
            }
            
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            
            let countsPtr = modelCountsBuf.contents().bindMemory(to: Int32.self, capacity: actualBatch)
            for i in 0..<actualBatch {
                let c = Int(countsPtr[i])
                if c > bestCount {
                    bestCount = c
                    let (AA,BB,CC,DD) = (
                        CGFloat(modelArr[i].x),
                        CGFloat(modelArr[i].y),
                        CGFloat(modelArr[i].z),
                        CGFloat(modelArr[i].w)
                    )
                    
                    var localInliers = [CGPoint]()
                    let offsetM = i * numPoints
                    let inPtr = inliersBuf.contents().bindMemory(to: Int32.self, capacity: totalThreads)
                    for pidx in 0..<numPoints {
                        if inPtr[offsetM + pidx] == 1 {
                            localInliers.append(points[pidx])
                        }
                    }
                    bestCoeffs = (AA,BB,CC,DD)
                    bestInliers = localInliers
                }
            }
        }
        
        return (bestCoeffs.0, bestCoeffs.1, bestCoeffs.2, bestCoeffs.3, bestInliers)
    }
    
    /// Converts a line segment into individual pixel points using Bresenham, clamped to image bounds
    private func rasterizeLineSegment(from p1: CGPoint,
                                      to p2: CGPoint,
                                      maxW: Int,
                                      maxH: Int) -> [CGPoint] {
        let x1 = Int(p1.x), y1 = Int(p1.y)
        let x2 = Int(p2.x), y2 = Int(p2.y)
        
        let dx = abs(x2 - x1)
        let dy = abs(y2 - y1)
        let maxSegment = 5000
        
        if (dx + dy) > maxSegment {
            return []
        }
        
        var result = [CGPoint]()
        result.reserveCapacity(dx + dy + 1)
        
        let sx = (x1 < x2) ? 1 : -1
        let sy = (y1 < y2) ? 1 : -1
        var err = dx - dy
        var xx = x1
        var yy = y1
        
        while true {
            if xx >= 0, xx < maxW, yy >= 0, yy < maxH {
                result.append(CGPoint(x: xx, y: yy))
            }
            if xx == x2 && yy == y2 {
                break
            }
            let e2 = 2*err
            if e2 > -dy {
                err -= dy
                xx += sx
            }
            if e2 < dx {
                err += dx
                yy += sy
            }
        }
        return result
    }
    
    /// Converts a texture's RGBA data back into a UIImage
    private func textureToUIImage(texture: MTLTexture) -> UIImage? {
        let w = texture.width
        let h = texture.height
        let bytesPerPixel = 4
        let pixelCount = w * h
        let length = pixelCount * bytesPerPixel
        
        var rawData = [UInt8](repeating: 0, count: length)
        let region = MTLRegionMake2D(0, 0, w, h)
        texture.getBytes(&rawData,
                         bytesPerRow: w * bytesPerPixel,
                         from: region,
                         mipmapLevel: 0)
        
        guard let provider = CGDataProvider(data: NSData(bytes: &rawData, length: length)) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        
        guard let cgImg = CGImage(width: w,
                                  height: h,
                                  bitsPerComponent: bitsPerComponent,
                                  bitsPerPixel: bitsPerPixel,
                                  bytesPerRow: w * bytesPerPixel,
                                  space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: cgImg)
    }
    
    // MARK: - Morphology and Embeddings
    private func doMorphPipeline(_ binFloats: [Float],
                                 _ width: Int,
                                 _ height: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            mask[i] = binFloats[i] > 0.5 ? 255 : 0
        }
        morphologicalClose(&mask, width: width, height: height)
        removeSmallCC(&mask, width: width, height: height, minArea: 100)
        return mask
    }
    
    private func morphologicalClose(_ mask: inout [UInt8],
                                    width: Int,
                                    height: Int) {
        let kernelSize = 5
        let kernel: [UInt8] = [
            0,0,1,0,0,
            0,1,1,1,0,
            1,1,1,1,1,
            0,1,1,1,0,
            0,0,1,0,0
        ]
        var temp = [UInt8](repeating: 0, count: mask.count)
        
        // Dilate
        mask.withUnsafeMutableBytes { srcPtr in
            temp.withUnsafeMutableBytes { dstPtr in
                var src = vImage_Buffer(data: srcPtr.baseAddress!,
                                        height: vImagePixelCount(height),
                                        width: vImagePixelCount(width),
                                        rowBytes: width)
                var dst = vImage_Buffer(data: dstPtr.baseAddress!,
                                        height: vImagePixelCount(height),
                                        width: vImagePixelCount(width),
                                        rowBytes: width)
                vImageDilate_Planar8(&src, &dst, 0, 0,
                                     kernel,
                                     vImagePixelCount(kernelSize),
                                     vImagePixelCount(kernelSize),
                                     vImage_Flags(kvImageEdgeExtend))
            }
        }
        
        // Erode
        mask.withUnsafeMutableBytes { dstPtr in
            temp.withUnsafeMutableBytes { srcPtr in
                var src = vImage_Buffer(data: srcPtr.baseAddress!,
                                        height: vImagePixelCount(height),
                                        width: vImagePixelCount(width),
                                        rowBytes: width)
                var dst = vImage_Buffer(data: dstPtr.baseAddress!,
                                        height: vImagePixelCount(height),
                                        width: vImagePixelCount(width),
                                        rowBytes: width)
                vImageErode_Planar8(&src, &dst, 0, 0,
                                    kernel,
                                    vImagePixelCount(kernelSize),
                                    vImagePixelCount(kernelSize),
                                    vImage_Flags(kvImageEdgeExtend))
            }
        }
    }
    
    private func removeSmallCC(_ mask: inout [UInt8],
                               width: Int,
                               height: Int,
                               minArea: Int) {
        var visited = [Bool](repeating: false, count: mask.count)
        let offsets = [-1, 1, -width, width, -width-1, -width+1, width-1, width+1]
        for idx in 0..<mask.count {
            if mask[idx] == 255 && !visited[idx] {
                var queue = [idx]
                var comp = [idx]
                visited[idx] = true
                while !queue.isEmpty {
                    let cur = queue.removeFirst()
                    let r = cur / width
                    let c = cur % width
                    for off in offsets {
                        let nei = cur + off
                        if nei < 0 || nei >= mask.count { continue }
                        let nr = nei / width
                        let nc = nei % width
                        if abs(nr - r) <= 1 && abs(nc - c) <= 1 {
                            if mask[nei] == 255 && !visited[nei] {
                                visited[nei] = true
                                queue.append(nei)
                                comp.append(nei)
                            }
                        }
                    }
                }
                if comp.count < minArea {
                    for p in comp {
                        mask[p] = 0
                    }
                }
            }
        }
    }
    
    private func gatherEmbeddings(_ mask: [UInt8],
                                  _ embFloats: [Float],
                                  _ width: Int,
                                  _ height: Int,
                                  embeddingDim: Int = 4)
    -> ([(Int,Int)], [[Float]]) {
        var coords = [(Int,Int)]()
        var feats = [[Float]]()
        
        for row in 0..<height {
            for col in 0..<width {
                let idx = row * width + col
                if mask[idx] == 255 {
                    let base = idx * embeddingDim
                    var vec = [Float](repeating: 0, count: embeddingDim)
                    for d in 0..<embeddingDim {
                        vec[d] = embFloats[base + d]
                    }
                    coords.append((col, row))
                    feats.append(vec)
                }
            }
        }
        return (coords, feats)
    }
    
    // MARK: - LaneCluster and SolveCubic
    struct LaneCluster {
        let points: [(Int,Int)]
        let label: Int
    }
    
    private func solveCubic(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint)
    -> (CGFloat,CGFloat,CGFloat,CGFloat)?
    {
        let (x1,y1) = (Double(p1.x), Double(p1.y))
        let (x2,y2) = (Double(p2.x), Double(p2.y))
        let (x3,y3) = (Double(p3.x), Double(p3.y))
        let (x4,y4) = (Double(p4.x), Double(p4.y))
        
        var M = [
            [x1*x1*x1, x1*x1, x1, 1.0],
            [x2*x2*x2, x2*x2, x2, 1.0],
            [x3*x3*x3, x3*x3, x3, 1.0],
            [x4*x4*x4, x4*x4, x4, 1.0]
        ]
        var R = [y1, y2, y3, y4]
        if !solve4x4(&M, &R) { return nil }
        
        return (CGFloat(R[0]), CGFloat(R[1]), CGFloat(R[2]), CGFloat(R[3]))
    }
    
    private func solve4x4(_ mat: inout [[Double]],
                          _ rhs: inout [Double]) -> Bool {
        let n = 4
        for i in 0..<n {
            var pivot = i
            var mx = abs(mat[i][i])
            for r in i+1..<n {
                let val = abs(mat[r][i])
                if val > mx {
                    mx = val
                    pivot = r
                }
            }
            if pivot != i {
                mat.swapAt(i, pivot)
                rhs.swapAt(i, pivot)
            }
            if abs(mat[i][i]) < 1e-12 {
                return false
            }
            for r in i+1..<n {
                let scale = mat[r][i] / mat[i][i]
                for c in i..<n {
                    mat[r][c] -= scale * mat[i][c]
                }
                rhs[r] -= scale * rhs[i]
            }
        }
        
        for i in (0...3).reversed() {
            var s = rhs[i]
            for c in (i+1)..<4 {
                s -= mat[i][c] * rhs[c]
            }
            rhs[i] = s / mat[i][i]
        }
        return true
    }
    
    private func solveCubicLeastSquares(_ inliers: [CGPoint])
    -> (CGFloat,CGFloat,CGFloat,CGFloat)? {
        if inliers.count < 4 { return nil }
        
        var A11=0.0, A12=0.0, A13=0.0, A14=0.0
        var A22=0.0, A23=0.0, A24=0.0
        var A33=0.0, A34=0.0
        var A44=0.0
        var B1=0.0, B2=0.0, B3=0.0, B4=0.0
        
        for p in inliers {
            let x = Double(p.x), y = Double(p.y)
            let x2 = x*x
            let x3 = x2*x
            
            A11 += x3*x3
            A12 += x3*x2
            A13 += x3*x
            A14 += x3
            
            A22 += x2*x2
            A23 += x2*x
            A24 += x2
            
            A33 += x*x
            A34 += x
            
            A44 += 1.0
            
            B1 += x3*y
            B2 += x2*y
            B3 += x*y
            B4 += y
        }
        
        var mat = [
            [A11, A12, A13, A14],
            [A12, A22, A23, A24],
            [A13, A23, A33, A34],
            [A14, A24, A34, A44]
        ]
        var rhs = [B1, B2, B3, B4]
        
        if !solve4x4(&mat, &rhs) { return nil }
        return (CGFloat(rhs[0]), CGFloat(rhs[1]), CGFloat(rhs[2]), CGFloat(rhs[3]))
    }
    
    /// Evaluates a cubic polynomial at x
    private func cubicEval(x: CGFloat, A: CGFloat, B: CGFloat, C: CGFloat, D: CGFloat) -> CGFloat {
        return A*x*x*x + B*x*x + C*x + D
    }
}

// MARK: - GPU line data
struct LinePoint {
    var x: UInt16
    var y: UInt16
    var color: SIMD4<Float>
}

// MARK: - MLMultiArray and UIImage Extensions
fileprivate extension Array where Element == UInt8 {
    func toUIImage(width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        
        guard let provider = CGDataProvider(data: NSData(bytes: self, length: self.count)) else {
            return nil
        }
        
        guard let cg = CGImage(width: width,
                               height: height,
                               bitsPerComponent: bitsPerComponent,
                               bitsPerPixel: bitsPerPixel,
                               bytesPerRow: bytesPerRow,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

extension UIImage {
    /// Resizes the image to the specified size without preserving aspect ratio
    func resized(to: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(to, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: to))
        let newImg = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImg
    }
    
    /// Converts an RGB image into an MLMultiArray with shape (1, height, width, 3)
    func toMLMultiArrayRGB() -> MLMultiArray? {
        guard let cgImage = self.cgImage else { return nil }
        let w = cgImage.width
        let h = cgImage.height
        let shape = [1, NSNumber(value: h), NSNumber(value: w), 3]
        
        guard let arr = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bpp = 4
        let bpr = bpp * w
        var rawData = [UInt8](repeating: 0, count: w * h * 4)
        
        guard let ctx = CGContext(data: &rawData,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bpr,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(arr.dataPointer))
        var idx = 0
        
        for row in 0..<h {
            for col in 0..<w {
                let i = (row * w + col) * 4
                let r = Float(rawData[i + 0])
                let g = Float(rawData[i + 1])
                let b = Float(rawData[i + 2])
                
                ptr[idx + 0] = (r - 127.5) / 127.5
                ptr[idx + 1] = (g - 127.5) / 127.5
                ptr[idx + 2] = (b - 127.5) / 127.5
                idx += 3
            }
        }
        return arr
    }
}

extension MLMultiArray {
    /// Converts the MLMultiArray (float32) to a Swift [Float] array if the data type matches
    func toFloatArray() -> [Float]? {
        guard dataType == .float32 else { return nil }
        let c = count
        var arr = [Float](repeating: 0, count: c)
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(dataPointer))
        for i in 0..<c {
            arr[i] = ptr[i]
        }
        return arr
    }
}
