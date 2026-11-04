import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    
    // Lane detection processor
    @StateObject private var liveProcessor = LiveProcessor()
    
    @State private var showCollisionIcon = false
    @State private var collisionTimestamp: Date?
    @State private var showLaneDepartureIcon = false
    @State private var departureTimestamp: Date?
    
    var body: some View {
        ZStack(alignment: .top) {
            // Displays the map as the main background
            MapView(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay containing search controls, navigation info, and detection icons
            VStack(spacing: 0) {
                // Shows search UI when not navigating
                if !viewModel.navigationActive {
                    searchBar
                    suggestionList
                }
                
                Spacer()
                
                // Navigation controls and icons arranged at the top
                ZStack(alignment: .topLeading) {
                    navigationControls
                        .padding(.bottom, 24)
                    
                    // Displays warning icons if a route is active
                    if let route = viewModel.currentRoute, viewModel.navigationActive {
                        HStack(spacing: 8) {
                            // Lane departure icon if a lane departure is detected
                            if showLaneDepartureIcon {
                                LaneDepartureIconView()
                            }
                            
                            if  showCollisionIcon {
                                LaneCollisionIconView()
                            }
                            // Stop sign icon if a stop sign is detected
                            if liveProcessor.stopSignDetected {
                                //StopSignIconView()
                            }
                        }
                        .padding(.leading, 20)
                        .offset(y: -60)
                    }
                }
                .onChange(of: liveProcessor.collisionDetected) { newValue in
                    if newValue {
                        // Mark the timestamp and show the icon
                        collisionTimestamp = Date()
                        showCollisionIcon = true

                        // Schedule hiding after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            // Only hide if no newer collision has reset the timestamp
                            if let ts = collisionTimestamp,
                               Date().timeIntervalSince(ts) >= 3 {
                                showCollisionIcon = false
                            }
                        }
                    }
                }
                .onChange(of: liveProcessor.departureState) { newValue in
                    if newValue != .none {
                        // Mark the timestamp and show the icon
                        departureTimestamp = Date()
                        showLaneDepartureIcon = true

                        // Schedule hiding after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            // Only hide if no newer departure has reset the timestamp
                            if let ts = departureTimestamp,
                               Date().timeIntervalSince(ts) >= 3 {
                                showLaneDepartureIcon = false
                            }
                        }
                    }
                }

            }
            
            // Shows the live camera feed (lane detection) at the top if navigation is active
            if viewModel.navigationActive {
                VStack {
                    LiveContentView(liveProcessor: liveProcessor)
                        .padding()
                    
                    Spacer()
                }
                .transition(.move(edge: .top))
            }
        }
        .onAppear {
            // Requests a single location fix if needed
            viewModel.requestSingleLocationIfNeeded()
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            TextField("Search for places", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.vertical, 8)
                .padding(.horizontal)
            
            // Displays a Stop button if already navigating
            if viewModel.navigationState == .navigating {
                Button("Stop") {
                    viewModel.stopNavigation()
                }
                .padding(.trailing)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .padding()
        .shadow(radius: 3)
    }
    
    // MARK: - Suggestion List
    private var suggestionList: some View {
        Group {
            if !viewModel.searchText.isEmpty && !viewModel.searchCompletions.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.searchCompletions, id: \.self) { completion in
                            Button {
                                // Selects a search completion and dismisses the keyboard
                                viewModel.selectCompletion(completion)
                                hideKeyboard()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(completion.title)
                                        .foregroundColor(.primary)
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .shadow(radius: 1)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.4)
                .background(.thickMaterial)
                .cornerRadius(12)
                .padding(.horizontal)
                .transition(.move(edge: .top))
            }
        }
    }
    
    // MARK: - Navigation Controls
    private var navigationControls: some View {
        VStack {
            if let route = viewModel.currentRoute {
                VStack(alignment: .leading) {
                    // Displays ETA, distance, and current speed
                    HStack {
                        VStack(alignment: .leading) {
                            Text("ETA: \(viewModel.eta)")
                                .font(.headline)
                            
                            Text("Distance: \(viewModel.distance)")
                            
                            Text(viewModel.navigationActive
                                 ? "Current Speed: \(viewModel.currentSpeed.toSpeedString())"
                                 : "Ready to navigate")
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Shows navigation buttons (recenter, stop) if navigation is active
                        if viewModel.navigationActive {
                            HStack(spacing: 20) {
                                Button {
                                    viewModel.recenterMap.toggle()
                                } label: {
                                    Image(systemName: "location.fill")
                                        .font(.title2)
                                        .padding(10)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                }
                                
                                Button {
                                    viewModel.stopNavigation()
                                } label: {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.title2)
                                        .padding(10)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .clipShape(Circle())
                                }
                            }
                        } else {
                            // Start navigation button if currently idle
                            Button {
                                viewModel.startNavigation()
                            } label: {
                                VStack {
                                    Image(systemName: "location.fill")
                                        .font(.title)
                                    Text("Go")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .clipShape(Circle())
                            }
                        }
                    }
                    
                    // Lists navigation steps if actively navigating
                    if viewModel.navigationActive {
                        Divider()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(route.steps, id: \.instructions) { step in
                                    if !step.instructions.isEmpty {
                                        Text(step.instructions)
                                            .padding(10)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(.thickMaterial)
                .cornerRadius(12)
                .padding()
                .transition(.move(edge: .bottom))
            }
        }
    }
}

// MARK: - Lane Departure Icon
struct LaneDepartureIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.8))
                .overlay(
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                )
                .frame(width: 50, height: 50)
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.black)
        }
        .shadow(radius: 2)
    }
}

// MARK: Lane Collision Icon
struct LaneCollisionIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 50, height: 50)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.white)
        }
        .shadow(radius: 2)
    }
}


// MARK: - Stop Sign Icon
struct StopSignIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.8))
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .frame(width: 50, height: 50)
            
            Text("STOP")
                .font(.headline)
                .foregroundColor(.white)
        }
        .shadow(radius: 2)
    }
}

// MARK: - Helpers
extension Double {
    func toSpeedString() -> String {
        let validSpeed = self >= 0 ? self : 0
        let measurement = Measurement(value: validSpeed, unit: UnitSpeed.metersPerSecond)
        let converted = measurement.converted(to: .milesPerHour)
        return "\(converted.value.formatted(.number.precision(.fractionLength(0)))) mph"
    }
}

private extension View {
    /// Hides the keyboard by resigning first responder status.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil)
    }
}
