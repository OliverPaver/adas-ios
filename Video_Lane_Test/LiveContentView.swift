import SwiftUI

/**
 Displays the processed live camera feed with a rounded border. If no frame is available,
 shows a gray placeholder. Automatically starts and stops the camera session.
 */
struct LiveContentView: View {
    @StateObject var liveProcessor: LiveProcessor
    
    var body: some View {
        ZStack {
            // Shows the camera frame if available
            if let frame = liveProcessor.processedFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
            } else {
                // Placeholder if no live feed yet
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Text("No live feed yet."))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        )
        .onAppear { liveProcessor.startRunning() }
        .onDisappear { liveProcessor.stopRunning() }
    }
}
