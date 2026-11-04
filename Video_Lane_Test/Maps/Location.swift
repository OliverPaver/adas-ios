//
//  Location.swift
//  Map_App
//
//  Created by Oliver Paver on 2/3/25.
//

import Foundation
import CoreLocation
import MapKit

struct Location: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct RouteInfo {
    let distance: Measurement<UnitLength>
    let expectedTravelTime: TimeInterval
    let steps: [String]
}

// MARK: - Navigation State
enum NavigationState {
    case idle
    case searching
    case navigating
    case rerouting
}
