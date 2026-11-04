//
//  MapViewModel.swift
//  Map_App
//
//  Created by Oliver Paver on 2/3/25.
//

import SwiftUI
import MapKit
import Combine
import CoreLocation

class MapViewModel: NSObject, ObservableObject {
    // MARK: - Published State
    @Published var searchText = ""
    @Published var searchCompletions: [MKLocalSearchCompletion] = []
    @Published var locations: [Location] = []
    @Published var selectedLocation: Location?
    @Published var currentRoute: MKRoute?
    @Published var currentSpeed: Double = 0
    @Published var eta: String = ""
    @Published var distance: String = ""
    @Published var navigationState: NavigationState = .idle
    @Published var userLocation: CLLocation?
    @Published var recenterMap = false
    @Published var navigationActive = false {
        didSet {
            if navigationActive {
                locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                locationManager.startUpdatingLocation()
                maybeStartHeadingUpdates()
            } else {
                locationManager.stopUpdatingHeading()
                locationManager.stopUpdatingLocation()
                
                if navigationState == .idle {
                    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                    locationManager.requestLocation()
                }
            }
        }
    }
    
    // MARK: - Private
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private var currentDirections: MKDirections?
    private var headingUpdatesActive = false
    private var finalDestination: CLLocationCoordinate2D?
    private let offRouteThreshold: CLLocationDistance = 50.0
    
    private lazy var searchCompleter: MKLocalSearchCompleter = {
        let completer = MKLocalSearchCompleter()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        return completer
    }()
    
    // MARK: - Init
    override init() {
        super.init()
        setupLocationManager()
        setupSearchBinding()
    }
    
    // MARK: - Location Manager Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
        
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
            locationManager.authorizationStatus == .authorizedAlways {
            locationManager.requestLocation()
        }
    }
    
    // MARK: - Search Binding
    private func setupSearchBinding() {
        $searchText
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    self.searchCompletions = []
                    self.locations = []
                } else {
                    self.searchCompleter.queryFragment = query
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Single Location
    func requestSingleLocationIfNeeded() {
        guard navigationState == .idle else { return }
        locationManager.requestLocation()
    }
    
    // MARK: - Route Calculation
    func calculateRoute(to destination: CLLocationCoordinate2D) {
        finalDestination = destination
        DispatchQueue.main.async {
            self.searchText = ""
            self.searchCompletions = []
            self.locations = []
        }
        
        guard let userLocation = userLocation else { return }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        
        currentDirections?.cancel()
        currentDirections = MKDirections(request: request)
        
        navigationState = .searching
        currentDirections?.calculate { [weak self] response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Routing error: \(error.localizedDescription)")
                    self.navigationState = .idle
                    return
                }
                
                guard let response = response, !response.routes.isEmpty else {
                    self.navigationState = .idle
                    return
                }
                
                let bestRoute = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime })
                
                if let route = bestRoute {
                    self.currentRoute = route
                    self.updateRouteInfo(route: route)
                    self.navigationState = .navigating
                } else {
                    self.currentRoute = nil
                    self.navigationState = .idle
                }
            }
        }
    }
    
    private func updateRouteInfo(route: MKRoute) {
        distance = Measurement(value: route.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated))
        
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        eta = formatter.string(from: route.expectedTravelTime) ?? ""
    }
    
    // MARK: - Navigation Control
    func startNavigation() {
        navigationActive = true
        navigationState = .navigating
    }
    
    func stopNavigation() {
        navigationActive = false
        currentRoute = nil
        navigationState = .idle
        selectedLocation = nil
        distance = ""
        eta = ""
    }
}

// MARK: - CLLocationManagerDelegate
extension MapViewModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if !navigationActive {
                manager.requestLocation()
            }
        case .denied, .restricted:
            print("Location access denied or restricted")
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }
        userLocation = latestLocation
        currentSpeed = max(latestLocation.speed, 0)
        
        if navigationState == .navigating, let route = currentRoute {
            let distanceToRoute = route.polyline.closestDistance(to: latestLocation.coordinate)
            
            if distanceToRoute > offRouteThreshold, let finalDest = finalDestination {
                navigationState = .rerouting
                calculateRoute(to: finalDest)
            } else {
                maybeStartOrStopHeadingUpdates(currentSpeed: currentSpeed)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Called if heading updates are active
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Heading Updates Control
extension MapViewModel {
    private func maybeStartHeadingUpdates() {
        guard !headingUpdatesActive else { return }
        locationManager.startUpdatingHeading()
        headingUpdatesActive = true
    }
    
    private func maybeStopHeadingUpdates() {
        guard headingUpdatesActive else { return }
        locationManager.stopUpdatingHeading()
        headingUpdatesActive = false
    }
    
    private func maybeStartOrStopHeadingUpdates(currentSpeed: Double) {
        if currentSpeed < 0.5 {
            maybeStopHeadingUpdates()
        } else {
            maybeStartHeadingUpdates()
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension MapViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var completions = completer.results
        
        if let userLoc = userLocation {
            completions.sort {
                guard let loc1 = $0.placemarkLocation, let loc2 = $1.placemarkLocation else {
                    return false
                }
                let dist1 = loc1.distance(from: userLoc)
                let dist2 = loc2.distance(from: userLoc)
                return dist1 < dist2
            }
        }
        self.searchCompletions = completions
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
    }
}

// MARK: - Selecting a Search Suggestion
extension MapViewModel {
    func selectCompletion(_ completion: MKLocalSearchCompletion) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let localSearch = MKLocalSearch(request: searchRequest)
        
        localSearch.start { [weak self] response, error in
            guard let self = self else { return }
            if let error = error {
                print("Local Search Error: \(error.localizedDescription)")
                return
            }
            if let mapItem = response?.mapItems.first {
                let name = mapItem.name ?? "Unknown Place"
                let coordinate = mapItem.placemark.coordinate
                let location = Location(name: name, coordinate: coordinate)
                
                DispatchQueue.main.async {
                    self.selectedLocation = location
                    self.calculateRoute(to: coordinate)
                }
            }
        }
    }
}

// MARK: - Helper to approximate coordinate (not guaranteed)
fileprivate extension MKLocalSearchCompletion {
    var placemarkLocation: CLLocation? {
        return nil
    }
}


import MapKit

extension MKPolyline {
    /// Returns the shortest distance (in meters) from the given coordinate to any segment of this polyline.
    func closestDistance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let targetMapPoint = MKMapPoint(coordinate)
        var minDistance = CLLocationDistance.greatestFiniteMagnitude
        
        for i in 0..<pointCount - 1 {
            let pt1 = points()[i]
            let pt2 = points()[i + 1]
            let segmentStart = MKMapPoint(x: pt1.x, y: pt1.y)
            let segmentEnd = MKMapPoint(x: pt2.x, y: pt2.y)
            
            let distance = MKMapPoint.closestDistance(
                from: targetMapPoint,
                toLineSegment: (segmentStart, segmentEnd)
            )
            if distance < minDistance {
                minDistance = distance
            }
        }
        return minDistance
    }
}

extension MKMapPoint {
    /// Returns the perpendicular distance from `point` to the line segment defined by `(start, end)`.
    static func closestDistance(from point: MKMapPoint,
                                toLineSegment segment: (start: MKMapPoint, end: MKMapPoint)) -> Double {
        let (start, end) = (segment.start, segment.end)
        let lineLengthSq = pow(end.x - start.x, 2) + pow(end.y - start.y, 2)
        
        if lineLengthSq == 0 {
            return point.distance(to: start)
        }
        
        let t = max(
            0,
            min(
                1,
                ((point.x - start.x) * (end.x - start.x) +
                 (point.y - start.y) * (end.y - start.y)) / lineLengthSq
            )
        )
        
        let projectionX = start.x + t * (end.x - start.x)
        let projectionY = start.y + t * (end.y - start.y)
        let projection = MKMapPoint(x: projectionX, y: projectionY)
        
        return point.distance(to: projection)
    }
}
