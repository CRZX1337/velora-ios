@preconcurrency import CoreLocation
import Combine
import Foundation

private struct LocationFailure: Sendable {
    let code: Int
    let domain: String
    let description: String
}

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    /// Demo mode replaces only the origin of the locations. Everything below
    /// the ingestion funnels through the same `process` method as a live
    /// CLLocationManager callback.
    private(set) var isDemoSource = false
    private var nowProvider: () -> Date = { .now }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var servicesEnabled: Bool
    @Published private(set) var lastMeasurementDate: Date?
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var isReceivingUpdates = false

    // Diagnostics are limited to status metadata. Coordinates are never retained
    // for the UI or for logs.
    @Published private(set) var startUpdatesCallCount = 0
    @Published private(set) var lastStartUpdatesDate: Date?
    @Published private(set) var locationCallbackCount = 0
    @Published private(set) var lastCallbackDate: Date?
    @Published private(set) var lastRawFixDate: Date?
    @Published private(set) var lastReportedAccuracy: Double?
    @Published private(set) var lastReportedSpeed: Double?
    @Published private(set) var lastReportedSpeedAccuracy: Double?
    @Published private(set) var lastErrorCode: Int?
    @Published private(set) var lastErrorDomain: String?
    @Published private(set) var lastErrorDescription: String?
    @Published private(set) var lastErrorDate: Date?

    /// Every accepted CoreLocation callback is forwarded exactly once. All
    /// filtering and decision making happens in the speed engine and recorder.
    var onFix: ((TripFix) -> Void)?

    private let manager: CLLocationManager
    private var wantsLocationUpdates = false
    private var nextFixID = 1

    override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        servicesEnabled = CLLocationManager.locationServicesEnabled()
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    var canReceiveLocation: Bool {
        isDemoSource
            || (servicesEnabled && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways))
    }

    var status: GPSStatus {
        if isDemoSource {
            return receptionStatus(now: nowProvider())
        }

        guard servicesEnabled else { return .servicesDisabled }

        switch authorizationStatus {
        case .notDetermined:
            return .permissionRequired
        case .denied, .restricted:
            return .permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            return .permissionDenied
        }

        return receptionStatus(now: nowProvider())
    }

    /// Classification after the services and authorization gates. The live and
    /// demo sources share this decision table without exception.
    private func receptionStatus(now: Date) -> GPSStatus {
        if let lastErrorCode,
           let lastErrorDate,
           lastErrorDate > (lastCallbackDate ?? .distantPast),
           lastErrorCode != CLError.locationUnknown.rawValue {
            return .error(
                code: lastErrorCode,
                description: lastErrorDescription ?? "Unknown CoreLocation error"
            )
        }

        if let lastStartUpdatesDate,
           isReceivingUpdates,
           (lastCallbackDate ?? .distantPast) < lastStartUpdatesDate {
            return .waitingForFirstFix
        }

        guard let lastCallbackDate else {
            return (isReceivingUpdates || startUpdatesCallCount > 0)
                ? .waitingForFirstFix
                : .starting
        }

        // The classification itself lives in GPSStatusResolution: accuracy is
        // evaluated before freshness, so a fresh but coarse fix reports low
        // accuracy instead of being announced as a usable GPS fix.
        return GPSStatusResolution.status(
            measurementAge: lastMeasurementDate.map { now.timeIntervalSince($0) },
            measurementAccuracy: horizontalAccuracy,
            reportedAccuracy: lastReportedAccuracy,
            callbackAge: now.timeIntervalSince(lastCallbackDate)
        )
    }

    func requestPermission() {
        guard !isDemoSource else { return }
        refreshAuthorization()
        guard servicesEnabled, authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        refreshAuthorization()
        wantsLocationUpdates = true
        beginUpdatesIfPossible()
    }

    func stopUpdates() {
        wantsLocationUpdates = false
        if !isDemoSource {
            manager.stopUpdatingLocation()
        }
        isReceivingUpdates = false
        lastMeasurementDate = nil
        horizontalAccuracy = nil
    }

    // MARK: - Demo source

    /// Swaps the source without touching the processing path. The demo clock is
    /// used for freshness decisions so accelerated playback stays coherent.
    func enterDemoSource(now: @escaping () -> Date) {
        guard !isDemoSource else { return }
        stopUpdates()
        isDemoSource = true
        nowProvider = now
        servicesEnabled = true
        clearDemoFailure()
    }

    func leaveDemoSource() {
        guard isDemoSource else { return }
        stopUpdates()
        clearDemoFailure()
        isDemoSource = false
        nowProvider = { .now }
        refreshAuthorization()
    }

    /// Injects a synthetic fix with the exact same filtering, diagnostics and
    /// TripFix construction as a CoreLocation callback.
    func feedDemoSample(_ location: CLLocation, monotonicTime: Double) {
        guard isDemoSource, wantsLocationUpdates, isReceivingUpdates else { return }
        process(location, now: nowProvider(), monotonic: monotonicTime, isSimulated: true)
    }

    func reportDemoFailure(code: Int = 0, description: String = "Simulated GPS signal loss") {
        guard isDemoSource else { return }
        record(failure: LocationFailure(code: code, domain: "VeloraDemo", description: description))
    }

    func clearDemoFailure() {
        lastErrorCode = nil
        lastErrorDomain = nil
        lastErrorDescription = nil
        lastErrorDate = nil
    }

    func refreshAuthorization() {
        guard !isDemoSource else { return }
        let enabled = CLLocationManager.locationServicesEnabled()
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization

        // Assign only when something actually changed. Assigning every second
        // published five times per second across the dashboard for no reason.
        if servicesEnabled != enabled { servicesEnabled = enabled }
        if authorizationStatus != status { authorizationStatus = status }
        if accuracyAuthorization != accuracy { accuracyAuthorization = accuracy }

        if !canReceiveLocation, isReceivingUpdates {
            stopUpdates()
        } else if canReceiveLocation, wantsLocationUpdates, !isReceivingUpdates {
            beginUpdatesIfPossible()
        }
    }

    private func beginUpdatesIfPossible() {
        guard wantsLocationUpdates, !isReceivingUpdates else { return }

        if isDemoSource {
            lastMeasurementDate = nil
            horizontalAccuracy = nil
            startUpdatesCallCount += 1
            lastStartUpdatesDate = nowProvider()
            isReceivingUpdates = true
            return
        }

        guard canReceiveLocation else { return }
        lastMeasurementDate = nil
        horizontalAccuracy = nil
        startUpdatesCallCount += 1
        lastStartUpdatesDate = nowProvider()
        isReceivingUpdates = true
        manager.startUpdatingLocation()
    }

    private func process(
        _ location: CLLocation,
        now: Date,
        monotonic: Double,
        isSimulated: Bool = false
    ) {
        locationCallbackCount += 1
        lastCallbackDate = now
        lastRawFixDate = location.timestamp
        lastReportedAccuracy = location.horizontalAccuracy.isFinite && location.horizontalAccuracy >= 0
            ? location.horizontalAccuracy
            : nil
        lastReportedSpeed = location.speed.isFinite && location.speed >= 0
            ? location.speed
            : nil
        lastReportedSpeedAccuracy = location.speedAccuracy.isFinite && location.speedAccuracy >= 0
            ? location.speedAccuracy
            : nil

        guard location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite,
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy > 0
        else { return }

        lastMeasurementDate = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy

        let fix = TripFix(
            id: nextFixID,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            gpsTime: location.timestamp.timeIntervalSince1970,
            monotonicTime: monotonic,
            horizontalAccuracy: location.horizontalAccuracy,
            nativeSpeed: location.speed.isFinite ? location.speed : nil,
            nativeSpeedAccuracy: location.speedAccuracy.isFinite ? location.speedAccuracy : nil,
            isSimulated: isSimulated
        )
        nextFixID += 1
        onFix?(fix)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.refreshAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.process(
                newest,
                now: .now,
                monotonic: ProcessInfo.processInfo.systemUptime
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        let failure = LocationFailure(
            code: nsError.code,
            domain: nsError.domain,
            description: nsError.localizedDescription
        )
        Task { @MainActor [weak self] in
            self?.record(failure: failure)
        }
    }

    private func record(failure: LocationFailure) {
        lastErrorCode = failure.code
        lastErrorDomain = failure.domain
        lastErrorDescription = failure.description
        lastErrorDate = nowProvider()
    }
}
