import Foundation
import CoreLocation

enum LocationServiceError: LocalizedError {
    case permissionDenied
    case unavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied. Enable it in System Settings > Privacy & Security > Location Services."
        case .unavailable:
            return "Unable to get your current location."
        case .timedOut:
            return "Location request timed out. Check app location permission and try again."
        }
    }
}

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocationCoordinate2D, Error>) -> Void)?
    private var isResolving = false
    private var timeoutWorkItem: DispatchWorkItem?
    private let timeoutInterval: TimeInterval = 12

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation(completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        guard CLLocationManager.locationServicesEnabled() else {
            completion(.failure(LocationServiceError.permissionDenied))
            return
        }

        self.completion = completion
        startTimeout()
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isResolving = true
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(LocationServiceError.permissionDenied))
        @unknown default:
            finish(with: .failure(LocationServiceError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !isResolving else { return }
            isResolving = true
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(LocationServiceError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(LocationServiceError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else {
            finish(with: .failure(LocationServiceError.unavailable))
            return
        }
        finish(with: .success(coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocationCoordinate2D, Error>) {
        isResolving = false
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private func startTimeout() {
        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(with: .failure(LocationServiceError.timedOut))
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval, execute: workItem)
    }
}
