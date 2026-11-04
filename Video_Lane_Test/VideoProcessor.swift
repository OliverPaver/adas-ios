import AVFoundation

import PhotosUI
import _PhotosUI_SwiftUI

/**
 Processes a selected video, extracting frames and running them through LaneDetector
 and LaneDepartureManager. Publishes the latest processed frame and lane departure state.
 */
class VideoProcessor: ObservableObject {
    @Published var processedFrame: UIImage?
    
    // Lane detection objects
    private let laneDetector = LaneDetector()
    private let laneDepartureManager = LaneDepartureManager()
    
    // Publishes the latest departure state
    @Published var departureState: LaneDepartureManager.DepartureState = .none
    
    private var assetReader: AVAssetReader?
    
    /**
     Loads the selected video from a PhotosPickerItem, saves it to a temporary file,
     and begins reading frames for processing.
     */
    func processVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("video.mp4")
        do {
            try data.write(to: tempURL)
            startReadingFrames(from: tempURL)
        } catch {
            print("Error saving video: \(error)")
        }
    }
    
    /**
     Creates an AVAssetReader for the given video URL and sets up a track output to retrieve frames.
     */
    private func startReadingFrames(from url: URL) {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        
        do {
            assetReader = try AVAssetReader(asset: asset)
        } catch {
            print("AssetReader error: \(error)")
            return
        }
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        assetReader?.add(output)
        assetReader?.startReading()
        
        processNextFrame()
    }
    
    /**
     Fetches the next frame from the asset reader, converts it to a UIImage, and
     runs the lane detection and departure pipeline. Schedules the next frame read
     with a delay to emulate a ~30 FPS playback.
     */
    private func processNextFrame() {
        autoreleasepool {
            guard let sampleBuffer = assetReader?.outputs.first?.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                assetReader?.cancelReading()
                return
            }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImage = UIImage(cgImage: cgImage)
            
            // 1) Run the lane detection pipeline
            let composite = laneDetector.feedFrame(uiImage)
            
            // 2) Retrieve polynomials for lane departure checks
            let leftPoly = laneDetector.egoLeftPoly
            let rightPoly = laneDetector.egoRightPoly
            
            // 3) Update lane departure state
            let (state, _) = laneDepartureManager.updateDepartureState(leftPoly: leftPoly,
                                                                       rightPoly: rightPoly)
            
            DispatchQueue.main.async { [weak self] in
                self?.processedFrame = composite
                self?.departureState = state
            }
        }
        
        // Emulates reading at ~30 FPS
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.033) {
            self.processNextFrame()
        }
    }
}
