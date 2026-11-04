//
//  MapView.swift
//  Map_App
//
//  Created by Oliver Paver on 2/3/25.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.setUserTrackingMode(.none, animated: false)
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateRouteOverlay(mapView: mapView)
        updateAnnotations(mapView: mapView)
        
        if viewModel.navigationActive {
            if viewModel.recenterMap {
                mapView.setUserTrackingMode(.followWithHeading, animated: true)
                // Defers published-state mutation off the immediate update cycle
                DispatchQueue.main.async {
                    viewModel.recenterMap = false
                }
            }
            if mapView.userTrackingMode != .followWithHeading {
                mapView.userTrackingMode = .followWithHeading
            }
        } else {
            if let location = viewModel.userLocation, viewModel.selectedLocation == nil {
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                mapView.setRegion(region, animated: true)
            }
        }
    }
    
    private func updateRouteOverlay(mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays)
        
        if let route = viewModel.currentRoute {
            mapView.addOverlay(route.polyline)
            if !viewModel.navigationActive {
                mapView.setVisibleMapRect(
                    route.polyline.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 100, left: 50, bottom: 200, right: 50),
                    animated: true
                )
            }
        }
    }
    
    private func updateAnnotations(mapView: MKMapView) {
        mapView.removeAnnotations(mapView.annotations)
        
        if let selected = viewModel.selectedLocation {
            let annotation = MKPointAnnotation()
            annotation.coordinate = selected.coordinate
            annotation.title = selected.name
            mapView.addAnnotation(annotation)
            mapView.selectAnnotation(annotation, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is MKPolyline {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}
