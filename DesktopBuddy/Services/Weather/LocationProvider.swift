import CoreLocation
import Foundation
import os

/// Roughly where the Mac is, for the weather — and only when the user has turned weather on.
///
/// Asks for approximate location (`kCLLocationAccuracyReduced`, a few kilometres): enough for a
/// forecast and no more. Location is read once per refresh, never tracked in the background.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Access: Equatable {
        case notAsked, allowed, denied, restricted, servicesOff
    }

    enum Failure: Error {
        case notAllowed(Access)
        case unavailable
    }

    private let manager = CLLocationManager()
    private var accessWaiters: [CheckedContinuation<Access, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []
    private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "weather")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var access: Access {
        guard CLLocationManager.locationServicesEnabled() else { return .servicesOff }
        switch manager.authorizationStatus {
        case .notDetermined: return .notAsked
        case .restricted: return .restricted
        case .denied: return .denied
        default: return .allowed  // .authorizedAlways / .authorized on macOS
        }
    }

    /// Shows the system's location prompt if it hasn't been answered, and waits for the answer.
    func requestAccess() async -> Access {
        guard access == .notAsked else { return access }
        return await withCheckedContinuation { continuation in
            accessWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One approximate fix. Times out after 20 seconds.
    func currentLocation() async throws -> CLLocation {
        guard access == .allowed else { throw Failure.notAllowed(access) }
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(20))
            self?.finishLocation(.failure(Failure.unavailable))
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
    }

    private func finishLocation(_ result: Result<CLLocation, Error>) {
        let waiters = locationWaiters
        locationWaiters = []
        for waiter in waiters { waiter.resume(with: result) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard access != .notAsked else { return }
            let waiters = accessWaiters
            accessWaiters = []
            for waiter in waiters { waiter.resume(returning: access) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if let location = locations.last { finishLocation(.success(location)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            log.notice("location failed: \(error.localizedDescription, privacy: .public)")
            finishLocation(.failure(Failure.unavailable))
        }
    }
}
