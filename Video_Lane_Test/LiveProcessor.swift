import AVFoundation

import Combine

class LiveProcessor: NSObject, ObservableObject {
    @Published var processedFrame: UIImage?
    
    // Lane detection
    private let laneDetector = LaneDetector()
    private let laneDepartureManager = LaneDepartureManager()
    @Published var departureState: LaneDepartureManager.DepartureState = .none
    private let laneCollisionManager = LaneCollisionManager()
    @Published var collisionDetected: Bool = false
    
    // Stop sign detection
    private let stopSignDetector = StopSignDetector()
    @Published var stopSignDetected: Bool = false

    // AVFoundation
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "live.capture.queue")
    
    // Frame counter for “every N frames” logic
    private var frameCounter = 0
    
    override init() {
        super.init()
        configureSession()
    }
    
    private func configureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Could not find back camera.")
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                if self.captureSession.canSetSessionPreset(.hd1280x720) {
                    self.captureSession.sessionPreset = .hd1280x720
                }
                
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }
                
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                
                output.setSampleBufferDelegate(self, queue: self.sessionQueue)
                
                if self.captureSession.canAddOutput(output) {
                    self.captureSession.addOutput(output)
                }
                
                // if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
                //    connection.videoOrientation = .landscapeRight
                // }
                
                
            } catch {
                print("Error configuring back camera input: \(error)")
            }
        }
    }
    
    // Public function to start running
    func startRunning() {
        sessionQueue.async {
            self.captureSession.startRunning()
        }
    }
    
    // Public function to stop
    func stopRunning() {
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension LiveProcessor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            // Force orientation to .right to match your portrait upright
            let rawImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
            
            // Resize the image with aspect fill for lane detection
            let targetSize = CGSize(width: 1280, height: 720)
            guard let finalImage = rawImage.resizedAspectFill(to: targetSize) else { return }
            
            // 1) Lane detection -> composite image
            let composite = laneDetector.feedFrame(finalImage)
            
            // 2) Lane departure state
            let leftPoly = laneDetector.egoLeftPoly
            let rightPoly = laneDetector.egoRightPoly
            let (depState, _) = laneDepartureManager.updateDepartureState(leftPoly: leftPoly,
                                                                          rightPoly: rightPoly)
            
            // 3) Stop sign detection every 3 frames
            self.frameCounter += 1
            if self.frameCounter % 3 == 0 {
                // Stop sign detection
                let foundStopSign = stopSignDetector.detectStopSign(in: finalImage)
                
                // Publish updates on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.stopSignDetected = foundStopSign
                }
            }
            
            
            let (collision, _) = laneCollisionManager.updateCollisionState(
                            leftPoly: leftPoly,
                            rightPoly: rightPoly,
                            learnedWidth: laneDepartureManager.getLearnedLaneWidth(),
                            in: finalImage
                        )
            // 4) Publish lane detection image + departureState
            DispatchQueue.main.async { [weak self] in
                self?.processedFrame = composite
                self?.departureState = depState
                self?.collisionDetected = collision
            }
        }
    }
}

import UIKit

extension UIImage {
    /// Returns an image resized with aspect fill to the target size.
    /// The image is scaled uniformly (preserving aspect ratio) and then centered in the target rectangle.
    /// Parts of the image may be cropped.
    func resizedAspectFill(to targetSize: CGSize) -> UIImage? {
        let aspectWidth = targetSize.width / self.size.width
        let aspectHeight = targetSize.height / self.size.height
        let scale = max(aspectWidth, aspectHeight)
        let newSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        
        // Center the new image in the target rect.
        let originX = (targetSize.width - newSize.width) / 2.0
        let originY = (targetSize.height - newSize.height) / 2.0
        let drawRect = CGRect(origin: CGPoint(x: originX, y: originY), size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(targetSize, false, self.scale)
        self.draw(in: drawRect)
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}
