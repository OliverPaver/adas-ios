import SwiftUI
import PhotosUI

/**
 Displays a video frame-by-frame preview and handles lane departure warnings.
 Allows the user to select a video from Photos to run through the pipeline.
 */
struct VideoContentView: View {
    @StateObject private var videoProcessor = VideoProcessor()
    @State private var selectedItem: PhotosPickerItem?
    
    // Indicates when to show a lane departure warning
    @State private var showDepartureWarning = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 1) Video preview or placeholder
            if let frame = videoProcessor.processedFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 300)
                    .overlay(Text("No video selected"))
            }
            
            // 2) Area for a short lane-departure message
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 30)
                
                if showDepartureWarning {
                    Text("Lane departure detected!")
                        .foregroundColor(.red)
                        .font(.headline)
                }
            }
            
            // 3) Picker for choosing a video from Photos
            PhotosPicker("Select Video", selection: $selectedItem, matching: .videos)
                .onChange(of: selectedItem) { newItem in
                    Task {
                        await videoProcessor.processVideo(from: newItem)
                    }
                }
        }
        .padding()
        // 4) Reacts to changes in departureState to show/hide the warning
        .onReceive(videoProcessor.$departureState) { state in
            switch state {
            case .left, .right:
                showDepartureWarning = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showDepartureWarning = false
                }
            case .none:
                break
            }
        }
    }
}
