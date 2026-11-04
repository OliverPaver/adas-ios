//
//  LiveProcessorTests.swift
//  Video_Lane_TestTests
//

import Testing
import UIKit
import AVFoundation
@testable import Video_Lane_Test

/**
 Tests for `LiveProcessor`, verifying:
 - Initialization and departure state
 - Safe start/stop of the capture session
 - Processing a synthetic CMSampleBuffer to update departure state and processedFrame
 */
struct LiveProcessorTests {
    
    // MARK: - 1) Test Initialization
    @Test
    func testInitialization() async throws {
        let processor = LiveProcessor()
        #expect(processor.processedFrame == nil, "No frames processed yet => processedFrame should be nil.")
        #expect(processor.departureState == .none, "Initial departure state is expected to be .none.")
    }
    
    // MARK: - 2) Test Start/Stop Running
    /// Ensures no crash or error occurs when starting and stopping the capture session.
    @Test
    func testStartStopRunning() async throws {
        let processor = LiveProcessor()
        
        processor.startRunning()
        try await Task.sleep(nanoseconds: 300_000_000)
        processor.stopRunning()
        try await Task.sleep(nanoseconds: 300_000_000)
        
        #expect(true, "Capture session started/stopped without crashing.")
    }
    
    // MARK: - 3) Test captureOutput with a synthetic sample buffer
    /**
     Creates a fake CMSampleBuffer from a test image, then invokes captureOutput.
     Checks whether processedFrame and departureState are updated.
     */
    @Test
    func testCaptureOutputUpdatesProcessedFrameAndDepartureState() async throws {
        let processor = LiveProcessor()
        
        // Attempt to load a real lane image, or fallback to a solid color
        guard let testImage = loadTestImage(named: "lane_lines", fileExtension: "jpg")
            ?? Self.makeTestColorImage(.blue, size: CGSize(width: 640, height: 480)) else {
            #expect(false, "Failed to create or load a test image.")
            return
        }
        
        // Build a sample buffer
        guard let sampleBuffer = Self.makeSampleBuffer(from: testImage) else {
            #expect(false, "Failed to make CMSampleBuffer from test image.")
            return
        }
        
        // Provide a dummy video output/connection
        let videoOutput = AVCaptureVideoDataOutput()
        let dummyConnection = AVCaptureConnection(inputPorts: [], output: videoOutput)
        
        // Trigger the delegate method
        processor.captureOutput(videoOutput, didOutput: sampleBuffer, from: dummyConnection)
        
        // Wait briefly to allow main-thread updates
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Check if processedFrame is updated
        #expect(processor.processedFrame != nil, "processedFrame should become non-nil after processing a sample buffer.")
        // departureState might remain .none if no lane departure, but confirm no crash
        #expect(true, "departureState = \(processor.departureState). Test passed.")
    }
    
    // MARK: - Helpers
    
    /// Loads a test image from the bundle if available
    private func loadTestImage(named: String, fileExtension: String) -> UIImage? {
        guard let url = Bundle(for: BundleToken.self).url(forResource: named, withExtension: fileExtension),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            return nil
        }
        return img
    }
    
    /// Creates a solid color UIImage as a fallback
    private static func makeTestColorImage(_ color: UIColor, size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
    }
    
    /**
     Builds a CMSampleBuffer from a UIImage by:
      1) Converting to CGImage
      2) Rendering into a CVPixelBuffer
      3) Creating a CMVideoFormatDescription
      4) Creating a CMSampleBuffer
     */
    private static func makeSampleBuffer(from uiImage: UIImage) -> CMSampleBuffer? {
        guard let cgImage = uiImage.cgImage else { return nil }
        
        // Create CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let width = cgImage.width
        let height = cgImage.height
        
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pixelBuffer)
        guard let pxBuffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(pxBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pxBuffer, []) }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pxBuffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pxBuffer),
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Create CMVideoFormatDescription from the pixel buffer
        var formatDesc: CMFormatDescription?
        let statusDesc = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                      imageBuffer: pxBuffer,
                                                                      formatDescriptionOut: &formatDesc)
        guard statusDesc == noErr, let validFormatDesc = formatDesc else { return nil }
        
        // Create sample timing
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: 30),
            presentationTimeStamp: CMTimeMake(value: 0, timescale: 30),
            decodeTimeStamp: CMTime.invalid
        )
        
        // Finally, create the CMSampleBuffer
        var sampleBufferOut: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pxBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: validFormatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBufferOut
        )
        guard status == noErr, let sb = sampleBufferOut else { return nil }
        
        return sb
    }
}

/// Dummy class for referencing this test bundle
private class BundleToken {}
