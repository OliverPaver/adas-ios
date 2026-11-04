import Foundation
import Vision
import CoreML
import UIKit

/**
 Uses a Core ML model (Stop_sign_test3) to detect stop signs labeled "3".
 Returns a boolean indicating whether a sign is found above a confidence threshold.
 */
class StopSignDetector {
    private let vnModel: VNCoreMLModel?

    init() {
        // Loads the Stop_sign_test3 model
        do {
            let mlModel = try Stop_sign_test3(configuration: MLModelConfiguration()).model
            self.vnModel = try VNCoreMLModel(for: mlModel)
        } catch {
            print("Error loading Stop_sign_test3 model: \(error)")
            self.vnModel = nil
        }
    }

    /**
     Returns true if a stop sign (label "3") is detected with at least
     the specified confidence. Otherwise returns false.
     */
    func detectStopSign(in image: UIImage, confidenceThreshold: Float = 0.5) -> Bool {
        guard let vnModel = vnModel,
              let cgImage = image.cgImage else {
            return false
        }

        var foundStopSign = false

        // Vision request using the stop-sign model
        let request = VNCoreMLRequest(model: vnModel) { request, _ in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            for object in results {
                for label in object.labels {
                    if label.identifier == "3", label.confidence >= confidenceThreshold {
                        foundStopSign = true
                        return
                    }
                }
                if foundStopSign { break }
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Vision request failed: \(error)")
        }

        return foundStopSign
    }
}
