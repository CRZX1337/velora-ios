import Foundation

// MARK: - Harness

final class Harness {
    private(set) var failures = 0
    private(set) var checks = 0

    func check(_ condition: Bool, _ name: String) {
        checks += 1
        if condition {
            print("  ok   \(name)")
        } else {
            failures += 1
            print("  FAIL \(name)")
        }
    }

    func close(_ value: Double, _ expected: Double, tolerance: Double, _ name: String) {
        check(abs(value - expected) <= tolerance, "\(name) (\(value) vs \(expected) ± \(tolerance))")
    }

    func section(_ name: String) {
        print("\n\(name)")
    }
}

struct DeterministicRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func unit() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000.0
    }

    mutating func symmetric(_ amplitude: Double) -> Double {
        (unit() * 2 - 1) * amplitude
    }
}

enum Fixtures {
    static let latitudeOrigin = 52.0
    static let longitudeOrigin = 13.0
    static let metresPerDegreeLatitude = 111_320.0

    static func point(
        id: Int,
        t: Double,
        x: Double,
        y: Double,
        accuracy: Double
    ) -> MotionPoint {
        MotionPoint(id: id, t: t, x: x, y: y, accuracy: accuracy)
    }

    static func straight(
        speed: Double,
        seconds: Double,
        rate: Double = 1,
        accuracy: Double,
        noise: Double,
        seed: UInt64,
        jitterY: Bool = true
    ) -> [MotionPoint] {
        var random = DeterministicRandom(seed: seed)
        var points: [MotionPoint] = []
        let count = Int(seconds * rate)
        for index in 0...count {
            let t = Double(index) / rate
            let x = speed * t + random.symmetric(noise)
            let y = jitterY ? random.symmetric(noise) : 0
            points.append(Fixtures.point(
                id: index,
                t: t,
                x: x,
                y: y,
                accuracy: accuracy
            ))
        }
        return points
    }

    static func stationary(
        seconds: Double,
        rate: Double = 1,
        accuracy: Double,
        noise: Double,
        seed: UInt64
    ) -> [MotionPoint] {
        var random = DeterministicRandom(seed: seed)
        var points: [MotionPoint] = []
        let count = Int(seconds * rate)
        for index in 0...count {
            let t = Double(index) / rate
            points.append(Fixtures.point(
                id: index,
                t: t,
                x: random.symmetric(noise),
                y: random.symmetric(noise),
                accuracy: accuracy
            ))
        }
        return points
    }

    static func fix(
        id: Int,
        time: Double,
        x: Double,
        y: Double,
        accuracy: Double,
        nativeSpeed: Double? = nil,
        nativeSpeedAccuracy: Double? = nil
    ) -> TripFix {
        let latitude = latitudeOrigin + y / metresPerDegreeLatitude
        let longitude = longitudeOrigin + x / (metresPerDegreeLatitude * cos(latitudeOrigin * .pi / 180))
        return TripFix(
            id: id,
            latitude: latitude,
            longitude: longitude,
            gpsTime: 1_700_000_000 + time,
            monotonicTime: time,
            horizontalAccuracy: accuracy,
            nativeSpeed: nativeSpeed,
            nativeSpeedAccuracy: nativeSpeedAccuracy
        )
    }

    static func line(
        from start: Double,
        to end: Double,
        speed: Double,
        accuracy: Double,
        noise: Double,
        seed: UInt64
    ) -> [TripFix] {
        var random = DeterministicRandom(seed: seed)
        var fixes: [TripFix] = []
        var time = start
        var index = 0
        while time <= end + 1e-9 {
            fixes.append(Fixtures.fix(
                id: index,
                time: time,
                x: speed * (time - start) + random.symmetric(noise),
                y: random.symmetric(noise),
                accuracy: accuracy
            ))
            time += 1
            index += 1
        }
        return fixes
    }
}

// MARK: - Main

@main
struct SpeedEngineTests {
    static func main() {
        let harness = Harness()

        testRSSNumerics(harness)
        testStationaryWindows(harness)
        testLinearDrift(harness)
        testMovingWindows(harness)
        testOutlierRule(harness)
        testDisjointWindows(harness)
        testSpeedEngineDecoupling(harness)
        testGeometry(harness)
        testRecorderStationary(harness)
        testRecorderMoving(harness)
        testRecorderCurve(harness)
        testRecorderNoFix(harness)
        testRecorderPauseResume(harness)
        testRecorderDoesNotDoubleCommit(harness)
        testNativeDoesNotCloseSegments(harness)
        testGPSStatusResolution(harness)
        testAccessibilityText(harness)
        testDemoDriveProfiles(harness)
        testDemoDriveCustom(harness)
        testDemoDriveRate(harness)
        testDemoDrivePipeline(harness)
        testDemoDriveControls(harness)
        testDemoSignalStates(harness)
        testDemoSessionSeparation(harness)
        testDemoSessionPhases(harness)
        testDemoPlaybackGate(harness)
        testTripControlRouting(harness)

        print("\n\(harness.checks) checks, \(harness.failures) failures")
        if harness.failures > 0 {
            exit(1)
        }
    }

// MARK: - Demo drive

    static func demoConfiguration(
        _ profile: DemoDriveProfile,
        rate: Double = 1,
        accuracy: Double = 6,
        target: Double = 80,
        acceleration: Double = 9,
        duration: TimeInterval = 60
    ) -> DemoDriveConfiguration {
        DemoDriveConfiguration(
            profile: profile,
            rate: rate,
            accuracyMeters: accuracy,
            customTargetKPH: target,
            customAccelerationKPHPerSecond: acceleration,
            customDuration: duration
        )
    }

    static func demoFixes(
        _ configuration: DemoDriveConfiguration,
        seconds: TimeInterval,
        step: TimeInterval = 0.1
    ) -> [TripFix] {
        var timeline = DemoDriveTimeline(configuration: configuration)
        var fixes: [TripFix] = []
        var id = 0
        let realSeconds = seconds / configuration.effectiveRate
        let iterations = Int((realSeconds / step).rounded())
        for _ in 0..<iterations {
            let sample = timeline.advance(by: step)
            guard sample.hasFix else { continue }
            id += 1
            fixes.append(TripFix(
                id: id,
                latitude: sample.latitude,
                longitude: sample.longitude,
                gpsTime: 1_800_000_000 + sample.elapsed,
                monotonicTime: sample.elapsed,
                horizontalAccuracy: sample.accuracyMeters,
                nativeSpeed: sample.speedKPH / 3.6,
                nativeSpeedAccuracy: 0.5,
                isSimulated: true
            ))
        }
        return fixes
    }

    static func runDemoTrip(
        _ fixes: [TripFix]
    ) -> (recorder: TripRecorder, engine: SpeedEngine, maxKPH: Double, averageKPH: Double) {
        let recorder = TripRecorder()
        let engine = SpeedEngine()
        recorder.start(now: 0)
        var maximum: Double = 0
        for fix in fixes {
            engine.ingest(fix)
            recorder.ingest(fix, now: fix.monotonicTime)
            if let speed = engine.reading.metersPerSecond,
               engine.reading.source != .unavailable {
                maximum = max(maximum, speed * 3.6)
            }
        }
        let end = fixes.last?.monotonicTime ?? 0
        recorder.stop(now: end)
        let active = recorder.activeSeconds(now: end)
        let average = active > 0 ? recorder.distanceMeters / active * 3.6 : 0
        return (recorder, engine, maximum, average)
    }

    static func testDemoDriveProfiles(_ harness: Harness) {
        harness.section("Demo drive: profiles")

        var city = DemoDriveTimeline(configuration: demoConfiguration(.city))
        var cityMax = 0.0
        var cityStopped = false
        for _ in 0..<2_000 {
            let sample = city.advance(by: 0.1)
            cityMax = max(cityMax, sample.speedKPH)
            if sample.speedKPH <= 0.01 { cityStopped = true }
        }
        harness.check(cityMax <= 50.01, "city stays within 0–50 km/h (max \(cityMax))")
        harness.check(cityMax >= 45, "city reaches cruising speed")
        harness.check(cityStopped, "city includes traffic-light stops")
        harness.check(city.distanceMeters > 500, "city records distance over five minutes")
        harness.check(city.latitude > 52.52 && city.longitude > 13.404,
                      "city moves north-east from its origin")

        var highway = DemoDriveTimeline(configuration: demoConfiguration(.highway))
        var highwayMax = 0.0
        var highwayMin = 999.0
        for _ in 0..<2_000 {
            let sample = highway.advance(by: 0.1)
            highwayMax = max(highwayMax, sample.speedKPH)
            if sample.elapsed > 20 { highwayMin = min(highwayMin, sample.speedKPH) }
        }
        harness.check(highwayMax <= 130.01, "highway never exceeds 130 km/h")
        harness.check(highwayMax >= 125, "highway reaches its upper band")
        harness.check(highwayMin <= 100, "highway includes slowdowns")

        var autobahn = DemoDriveTimeline(configuration: demoConfiguration(.autobahn))
        var autobahnMax = 0.0
        for _ in 0..<2_000 {
            autobahnMax = max(autobahnMax, autobahn.advance(by: 0.1).speedKPH)
        }
        harness.check(autobahnMax >= 158, "autobahn reaches the 160 km/h band (max \(autobahnMax))")
        harness.check(autobahnMax <= 160.01, "autobahn stays within 160 km/h")

        var mixed = DemoDriveTimeline(configuration: demoConfiguration(.mixed))
        var mixedMax = 0.0
        var mixedStopped = false
        for _ in 0..<2_000 {
            let sample = mixed.advance(by: 0.1)
            mixedMax = max(mixedMax, sample.speedKPH)
            if sample.speedKPH <= 0.01 { mixedStopped = true }
        }
        harness.check(mixedStopped, "mixed profile includes a full stop")
        harness.check(mixedMax >= 125 && mixedMax <= 130.01,
                      "mixed profile reaches the autobahn band")
    }

    static func testDemoDriveCustom(_ harness: Harness) {
        harness.section("Demo drive: custom profile")

        var ramp = DemoDriveTimeline(configuration: demoConfiguration(
            .custom, target: 30, acceleration: 10, duration: 100
        ))
        let rampSample = ramp.advance(by: 3)
        harness.close(rampSample.speedKPH, 30, tolerance: 0.01, "custom ramp honours acceleration")

        var deceleration = DemoDriveTimeline(configuration: demoConfiguration(
            .custom, target: 50, acceleration: 10, duration: 5
        ))
        deceleration.advance(by: 3)
        deceleration.advance(by: 1)
        let coasting = deceleration.advance(by: 2)
        harness.close(coasting.speedKPH, 20, tolerance: 0.01, "custom profile decelerates after its duration")

        var still = DemoDriveTimeline(configuration: demoConfiguration(
            .custom, target: 0, acceleration: 10, duration: 100
        ))
        let stillSample = still.advance(by: 10)
        harness.check(stillSample.speedKPH == 0, "custom target zero holds still")
        harness.check(stillSample.distanceMeters == 0, "standstill adds no distance")

        var distance = DemoDriveTimeline(configuration: demoConfiguration(
            .custom, target: 100, acceleration: 1_000, duration: 100
        ))
        distance.advance(by: 0.1)
        let covered = distance.advance(by: 9.9).distanceMeters
        harness.close(covered, 277.78, tolerance: 2.0, "custom distance follows speed × time")
        harness.close(distance.distanceMeters / distance.elapsed * 3.6, 100, tolerance: 2,
                      "custom average matches the target speed")

        var maximum = DemoDriveTimeline(configuration: demoConfiguration(
            .custom, target: 120, acceleration: 20, duration: 100
        ))
        var peak = 0.0
        for _ in 0..<300 {
            peak = max(peak, maximum.advance(by: 0.1).speedKPH)
        }
        harness.check(peak >= 119.5 && peak <= 120.01, "custom profile holds its target")

        maximum.setManualTarget(0)
        for _ in 0..<100 { maximum.advance(by: 0.1) }
        harness.check(maximum.currentSpeedKPH == 0, "manual standstill stops the car")
        harness.check(maximum.distanceMeters > 0, "manual standstill keeps the covered distance")
        maximum.setManualTarget(nil)
        harness.check(maximum.currentSpeedKPH == 0, "releasing standstill starts from zero")
    }

    static func testDemoDriveRate(_ harness: Harness) {
        harness.section("Demo drive: playback rate")

        var normal = DemoDriveTimeline(configuration: demoConfiguration(.city, rate: 1))
        var fast = DemoDriveTimeline(configuration: demoConfiguration(.city, rate: 10))
        let a = normal.advance(by: 5)
        let b = fast.advance(by: 0.5)
        harness.close(a.speedKPH, b.speedKPH, tolerance: 0.0001, "10× reaches the same speed state")
        harness.close(a.distanceMeters, b.distanceMeters, tolerance: 0.0001, "10× covers the same distance")
        harness.close(a.latitude, b.latitude, tolerance: 0.0000001, "10× ends at the same position")
        harness.check(a.elapsed == 5 && b.elapsed == 5, "simulated clock advances by rate × real time")

        let fastFixes = demoFixes(demoConfiguration(.city, rate: 5), seconds: 60)
        harness.close(fastFixes.last?.monotonicTime ?? 0, 60, tolerance: 0.2,
                      "5× playback still produces 60 simulated seconds")
        harness.check((fastFixes.first?.monotonicTime ?? 0) >= 2,
                      "first fix waits for the simulated startup delay")
    }

    static func testDemoDrivePipeline(_ harness: Harness) {
        harness.section("Demo drive: same pipeline")

        let cityFixes = demoFixes(demoConfiguration(.city), seconds: 120)
        let city = runDemoTrip(cityFixes)
        harness.check(city.recorder.distanceMeters > 300,
                      "recorder receives demo distance (\(city.recorder.distanceMeters) m)")
        harness.check(city.maxKPH >= 40, "engine reaches city speed (max \(city.maxKPH))") 
        harness.check(city.averageKPH > 15 && city.averageKPH < 50,
                      "average speed is plausible (\(city.averageKPH) km/h)")
        harness.close(city.recorder.activeSeconds(now: cityFixes.last?.monotonicTime ?? 0),
                      120, tolerance: 1, "trip time follows the demo clock")

        let highwayFixes = demoFixes(demoConfiguration(.highway), seconds: 120)
        let highway = runDemoTrip(highwayFixes)
        harness.check(highway.maxKPH >= 125 && highway.maxKPH <= 130.5,
                      "highway speed survives the engine (max \(highway.maxKPH))")
        harness.check(highway.recorder.distanceMeters > 2_000,
                      "highway distance is recorded (\(highway.recorder.distanceMeters) m)")
    }

    static func testDemoDriveControls(_ harness: Harness) {
        harness.section("Demo drive: pause, resume, reset")

        let fixes = demoFixes(demoConfiguration(.city), seconds: 90)
        let recorder = TripRecorder()
        recorder.start(now: 0)
        for fix in fixes where fix.monotonicTime <= 30 {
            recorder.ingest(fix, now: fix.monotonicTime)
        }
        let beforePause = recorder.distanceMeters
        recorder.pause(now: 30)
        harness.check(recorder.distanceMeters == beforePause, "pause adds no distance")
        harness.check(recorder.activeSeconds(now: 90) == 30, "pause freezes trip time")

        recorder.resume(now: 45)
        for fix in fixes where fix.monotonicTime > 45 {
            recorder.ingest(fix, now: fix.monotonicTime)
        }
        let end = fixes.last?.monotonicTime ?? 90
        recorder.stop(now: end)
        harness.close(recorder.activeSeconds(now: end), 75, tolerance: 1,
                      "pause is excluded from active time")
        harness.check(recorder.distanceMeters > beforePause, "resume continues recording")

        recorder.reset()
        harness.check(recorder.distanceMeters == 0, "reset clears distance")
        harness.check(recorder.activeSeconds(now: end) == 0, "reset clears trip time")
        harness.check(recorder.state == .idle, "reset returns to idle")

        let engine = SpeedEngine()
        engine.ingest(fixes[0])
        engine.reset()
        harness.check(engine.reading.metersPerSecond == nil, "reset clears the speed reading")
    }

    static func testDemoSignalStates(_ harness: Harness) {
        harness.section("Demo drive: GPS signal states")

        let ready = GPSStatusResolution.status(
            measurementAge: 0.5, measurementAccuracy: 6, reportedAccuracy: 6, callbackAge: 0.5
        )
        harness.check(ready == .ready(accuracy: 6), "demo ready state maps to ready")

        let low = GPSStatusResolution.status(
            measurementAge: 0.5, measurementAccuracy: 120, reportedAccuracy: 120, callbackAge: 0.5
        )
        harness.check(low == .inaccurate(accuracy: 120), "demo low accuracy maps to inaccurate")

        let stale = GPSStatusResolution.status(
            measurementAge: 6, measurementAccuracy: 6, reportedAccuracy: 6, callbackAge: 6
        )
        harness.check(stale == .stale(age: 6), "silent demo source turns stale after five seconds")

        let waiting = GPSStatusResolution.status(
            measurementAge: nil, measurementAccuracy: nil, reportedAccuracy: nil, callbackAge: 2
        )
        harness.check(waiting == .waitingForFirstFix, "demo start reports waiting for first fix")

        var outage = DemoDriveTimeline(configuration: demoConfiguration(.city))
        var outageFixes: [TripFix] = []
        var id = 0
        for step in 0..<600 {
            if step == 200 { outage.configuration.signalMode = .outage }
            if step == 400 { outage.configuration.signalMode = .live }
            let sample = outage.advance(by: 0.1)
            guard sample.hasFix else { continue }
            id += 1
            outageFixes.append(TripFix(
                id: id,
                latitude: sample.latitude,
                longitude: sample.longitude,
                gpsTime: 1_800_000_000 + sample.elapsed,
                monotonicTime: sample.elapsed,
                horizontalAccuracy: sample.accuracyMeters,
                nativeSpeed: sample.speedKPH / 3.6,
                nativeSpeedAccuracy: 0.5,
                isSimulated: true
            ))
        }
        let outageTrip = runDemoTrip(outageFixes)
        harness.check(outageTrip.recorder.gapCount >= 1, "signal outage creates a coverage gap")
        harness.check(outageTrip.recorder.gapSeconds >= 15, "outage duration is accounted for")
        harness.check(outageTrip.engine.reading.metersPerSecond != nil,
                      "engine recovers after the signal returns")

        let lowAccuracyFixes = demoFixes(demoConfiguration(.city, accuracy: 120), seconds: 20)
        let lowAccuracyTrip = runDemoTrip(lowAccuracyFixes)
        harness.check(lowAccuracyTrip.recorder.distanceMeters == 0,
                      "low-accuracy fixes add no distance")
        harness.check(lowAccuracyTrip.engine.reading.metersPerSecond == nil,
                      "low-accuracy fixes never fabricate a speed")
    }

    static func testDemoSessionSeparation(_ harness: Harness) {
        harness.section("Demo drive: session separation")

        let demoFixes = demoFixes(demoConfiguration(.city), seconds: 20)
        harness.check(demoFixes.allSatisfy(\.isSimulated), "demo fixes carry the simulated flag")

        let plain = TripFix(
            id: 1, latitude: 52, longitude: 13, gpsTime: 0,
            monotonicTime: 0, horizontalAccuracy: 5
        )
        harness.check(!plain.isSimulated, "live fixes default to the real source")

        let realFixes = demoFixes.map { fix -> TripFix in
            var copy = fix
            copy.isSimulated = false
            return copy
        }
        let demoDistance = runDemoTrip(demoFixes).recorder.distanceMeters
        let realDistance = runDemoTrip(realFixes).recorder.distanceMeters
        harness.check(demoDistance == realDistance, "provenance never changes the maths")
    }

    // MARK: - GPS status

    static func testGPSStatusResolution(_ harness: Harness) {
        harness.section("GPS status resolution")

        func status(
            age: TimeInterval? = nil,
            accuracy: Double? = nil,
            reported: Double? = nil,
            callbackAge: TimeInterval? = nil
        ) -> GPSStatus {
            GPSStatusResolution.status(
                measurementAge: age,
                measurementAccuracy: accuracy,
                reportedAccuracy: reported,
                callbackAge: callbackAge
            )
        }

        // Threshold boundaries: 35 m is still usable, 35.1 m is not.
        harness.check(status(age: 1, accuracy: 5) == .ready(accuracy: 5),
                      "fresh 5 m fix is ready")
        harness.check(status(age: 1, accuracy: 35) == .ready(accuracy: 35),
                      "fresh fix at the 35 m threshold is ready")
        harness.check(status(age: 1, accuracy: 35.1) == .inaccurate(accuracy: 35.1),
                      "fresh fix just above the threshold is inaccurate")
        harness.check(status(age: 1, accuracy: 100) == .inaccurate(accuracy: 100),
                      "fresh 100 m fix is inaccurate, not ready")

        // Fresh and stale readings.
        harness.check(status(age: 5, accuracy: 5) == .ready(accuracy: 5),
                      "fix at the 5 s edge is still fresh")
        harness.check(status(age: 6, accuracy: 5) == .stale(age: 6),
                      "fix older than 5 s is stale")
        harness.check(status(age: 6, accuracy: 100) == .stale(age: 6),
                      "stale reading stays stale even when it is inaccurate")

        // No measurement at all.
        harness.check(status(callbackAge: 1) == .waitingForFirstFix,
                      "recent callback without a measurement is waiting")
        harness.check(status(callbackAge: 10) == .stale(age: 10),
                      "callback without a measurement becomes stale")
        harness.check(status() == .waitingForFirstFix,
                      "no callback and no measurement is waiting")

        // Invalid values must never look like a precise fix.
        harness.check(status(age: 1, accuracy: -3) == .waitingForFirstFix,
                      "negative measurement accuracy is not ready")
        harness.check(status(age: 1, accuracy: .nan) == .waitingForFirstFix,
                      "NaN measurement accuracy is not ready")
        harness.check(status(age: 1, accuracy: 0) == .waitingForFirstFix,
                      "zero measurement accuracy is not ready")
        harness.check(status(age: 1, accuracy: .infinity) == .waitingForFirstFix,
                      "infinite measurement accuracy is not ready")

        // Reported accuracy without a usable measurement keeps the old branch.
        harness.check(status(reported: 100) == .inaccurate(accuracy: 100),
                      "reported accuracy above the threshold is inaccurate")
        harness.check(status(reported: -5) == .waitingForFirstFix,
                      "negative reported accuracy is not inaccurate")
    }

    // MARK: - Accessibility text

    static func testAccessibilityText(_ harness: Harness) {
        harness.section("Accessibility text")

        harness.check(AccessibilityText.speedLabel == "Speed",
                      "the gauge announces an English label")
        harness.check(AccessibilityText.speedValue("42", spokenUnit: "kilometers per hour")
                        == "42 kilometers per hour",
                      "the gauge announces value and spoken unit")
        harness.check(AccessibilityText.speedValue("—", spokenUnit: "km/h")
                        == AccessibilityText.noReading,
                      "a missing reading is announced as such")
        harness.check(AccessibilityText.metric(title: "MAX", value: "120", unit: "km/h", isApproximate: false)
                        == "MAX 120 km/h",
                      "a metric announces title, value and unit")
        harness.check(AccessibilityText.metric(title: "AVERAGE", value: "80", unit: "km/h", isApproximate: true)
                        == "AVERAGE approximately 80 km/h",
                      "an approximate metric is announced as approximate")
        harness.check(AccessibilityText.metric(title: "TRIP TIME", value: "01:02:03", unit: "", isApproximate: false)
                        == "TRIP TIME 01:02:03",
                      "a metric without a unit has no trailing space")
        harness.check(SpeedUnit.kilometersPerHour.spokenTitle == "kilometers per hour"
                        && SpeedUnit.milesPerHour.spokenTitle == "miles per hour",
                      "units have spoken English names")
        harness.check(!AccessibilityText.speedLabel.contains("Geschwindigkeit")
                        && !AccessibilityText.noReading.contains("Geschwindigkeit"),
                      "no German accessibility string remains")
    }

    // MARK: - Accessibility text
    // MARK: - Numerics

    static func testRSSNumerics(_ harness: Harness) {
        harness.section("RSS numerics")

        let tolerance = MotionMath.invariantTolerance(rss0: 1.0, rss1: 1.0)
        harness.check(tolerance > 0 && tolerance < 1e-6, "invariant tolerance is pure float rounding")

        let clamped = MotionMath.fStatistic(rss0: 1.0 - 1e-15, rss1: 1.0, sampleCount: 10)
        harness.check(clamped == 0, "negative rounding diff clamps to F = 0")

        let inconsistent = MotionMath.fStatistic(rss0: 1.0 - 1e-6, rss1: 1.0, sampleCount: 10)
        harness.check(inconsistent == nil, "real negative diff is reported as inconsistent")

        if let positive = MotionMath.fStatistic(rss0: 2.0, rss1: 1.0, sampleCount: 10) {
            harness.check(positive > 0, "positive diff yields positive F")
        } else {
            harness.check(false, "positive diff yields positive F")
        }

        harness.check(MotionMath.fStatistic(rss0: 1, rss1: 0, sampleCount: 10) == nil,
                      "zero denominator is rejected")
        harness.check(MotionMath.fStatistic(rss0: 1, rss1: 1, sampleCount: 5) == nil,
                      "fewer than six samples is rejected")

        let smallScale = MotionMath.fStatistic(rss0: 1e-9, rss1: 4e-9, sampleCount: 12)
        harness.check(smallScale == nil, "small-scale inconsistency is not hidden by heuristics")
    }

    // MARK: - Windows

    static func testStationaryWindows(_ harness: Harness) {
        harness.section("Stationary windows")

        for seed in UInt64(1)...5 {
            let points = Fixtures.stationary(seconds: 30, accuracy: 8, noise: 4, seed: seed)
            let analysis = MotionMath.analyze(points: points)
            harness.check(analysis.verdict != .moving, "8 m stationary pattern #\(seed) never moves")
            harness.check(analysis.speed < 0.8, "8 m stationary speed stays small #\(seed)")
        }

        let identical = (0...20).map {
            Fixtures.point(id: $0, t: Double($0), x: 0, y: 0, accuracy: 8)
        }
        let identicalAnalysis = MotionMath.analyze(points: identical)
        harness.check(identicalAnalysis.verdict == .stationary, "identical positions are stationary")

        let nearIdentical = (0...20).map {
            Fixtures.point(id: $0, t: Double($0), x: 0.01, y: 0.01, accuracy: 8)
        }
        harness.check(MotionMath.analyze(points: nearIdentical).verdict == .stationary,
                      "near-identical positions are stationary")
    }

    static func testLinearDrift(_ harness: Harness) {
        harness.section("Linear drift")

        for speed in [0.05, 0.10, 0.15, 0.19, 0.20, 0.30] {
            let points = Fixtures.straight(
                speed: speed,
                seconds: 29,
                accuracy: 8,
                noise: 0.05,
                seed: UInt64(100 + Int(speed * 1000))
            )
            let analysis = MotionMath.analyze(points: points)
            harness.check(analysis.verdict != .stationary,
                          "drift \(speed) m/s is not stationary (got \(analysis.verdict.rawValue), \(analysis.reason))")
        }
    }

    static func testMovingWindows(_ harness: Harness) {
        harness.section("Moving windows")

        let moving = Fixtures.straight(
            speed: 1.5,
            seconds: 24,
            accuracy: 4,
            noise: 0.5,
            seed: 7
        )
        let movingAnalysis = MotionMath.analyze(points: moving)
        harness.check(movingAnalysis.verdict == .moving,
                      "1.5 m/s at 4 m is moving (got \(movingAnalysis.verdict.rawValue), \(movingAnalysis.reason))")
        harness.close(movingAnalysis.speed, 1.5, tolerance: 0.35, "speed estimate")

        let slow = Fixtures.straight(
            speed: 0.25,
            seconds: 29,
            accuracy: 8,
            noise: 4,
            seed: 11
        )
        let slowAnalysis = MotionMath.analyze(points: slow)
        harness.check(slowAnalysis.verdict != .stationary, "0.25 m/s with 8 m noise is not stationary")

        let fast = Fixtures.straight(
            speed: 20,
            seconds: 29,
            accuracy: 12,
            noise: 3,
            seed: 21
        )
        harness.check(MotionMath.analyze(points: fast).verdict == .moving, "20 m/s is moving")

        let bigResiduals = Fixtures.straight(
            speed: 1.5,
            seconds: 29,
            accuracy: 18,
            noise: 12,
            seed: 31
        )
        harness.check(MotionMath.analyze(points: bigResiduals).verdict != .stationary,
                      "large residuals never produce stationary")
    }

    static func testOutlierRule(_ harness: Harness) {
        harness.section("Outlier handling")

        var six = Fixtures.straight(speed: 2, seconds: 5, accuracy: 4, noise: 0.1, seed: 41)
        six[3] = Fixtures.point(id: 3, t: 3, x: 80, y: 60, accuracy: 4)
        let sixAnalysis = MotionMath.analyze(points: six)
        harness.check(sixAnalysis.verdict == .stabilizing, "six samples minus outlier is invalid")
        harness.check(sixAnalysis.reason == "outlierReducedBelowMinimum",
                      "six-sample limit applies after outlier removal")

        var seven = Fixtures.straight(speed: 2, seconds: 6, accuracy: 4, noise: 0.1, seed: 42)
        seven[3] = Fixtures.point(id: 3, t: 3, x: 80, y: 60, accuracy: 4)
        let sevenAnalysis = MotionMath.analyze(points: seven)
        harness.check(sevenAnalysis.usedCount == 6, "seven samples minus one outlier keeps six")
        harness.check(sevenAnalysis.removedOutlierID == 3, "outlier id is reported")
        harness.check(sevenAnalysis.verdict == .moving, "remaining six samples can still decide")
    }

    static func testDisjointWindows(_ harness: Harness) {
        harness.section("Disjoint windows")

        let engine = SpeedEngine()
        for index in 0...40 {
            let time = Double(index)
            engine.ingest(Fixtures.fix(
                id: index,
                time: time,
                x: 1.5 * time,
                y: 0,
                accuracy: 4
            ))
        }

        let current = Set(engine.diagnostics.currentSampleIDs)
        let previous = Set(engine.diagnostics.previousSampleIDs)
        harness.check(!current.isEmpty && !previous.isEmpty, "both windows exist")
        harness.check(current.isDisjoint(with: previous), "window sample ids are disjoint")
        harness.check(engine.positionMotionStatus == .moving,
                      "position window contributes a moving status")
    }

    static func testSpeedEngineDecoupling(_ harness: Harness) {
        harness.section("Speed reading decoupling")

        let engine = SpeedEngine()
        for index in 0...3 {
            let time = Double(index)
            engine.ingest(Fixtures.fix(
                id: index,
                time: time,
                x: 0,
                y: 0,
                accuracy: 4,
                nativeSpeed: 12.5,
                nativeSpeedAccuracy: 0.3
            ))
        }
        harness.check(engine.reading.metersPerSecond != nil, "valid native reading is displayed")
        harness.check(engine.nativeMotionStatus == .moving, "two consecutive native readings confirm native moving")
        harness.check(engine.positionMotionStatus == .stabilizing,
                      "native evidence does not create a position status")

        let empty = SpeedEngine()
        empty.refresh(now: 10)
        harness.check(empty.reading.source == .unavailable, "no reading yields unavailable, not zero")
        harness.check(empty.reading.metersPerSecond == nil, "unavailable reading has no value")
    }

    // MARK: - Geometry

    static func testGeometry(_ harness: Harness) {
        harness.section("Geometry")

        let oneDegree = MotionMath.haversine(
            latitude1: 0,
            longitude1: 0,
            latitude2: 1,
            longitude2: 0
        )
        harness.close(oneDegree, 111_195, tolerance: 80, "one degree latitude")

        let zero = MotionMath.haversine(latitude1: 10, longitude1: 10, latitude2: 10, longitude2: 10)
        harness.check(zero == 0, "identical coordinates yield zero distance")
    }

    // MARK: - Recorder

    static func testRecorderStationary(_ harness: Harness) {
        harness.section("Recorder: stationary")

        let calm = TripRecorder()
        calm.start(now: 0)
        for index in 0...20 {
            let time = Double(index)
            calm.ingest(Fixtures.fix(id: index, time: time, x: 0, y: 0, accuracy: 8), now: time)
        }
        calm.stop(now: 20)
        harness.check(calm.distanceMeters == 0, "identical positions add no distance")
        harness.check(calm.gapCount == 0, "confirmed stationary is not a coverage gap")
        harness.check(calm.lastResolution == .stationaryZero, "segment resolves as stationaryZero")
        harness.check(calm.ledgerIsBalanced(now: 20), "ledger balanced after stationary stop")

        var random = DeterministicRandom(seed: 77)
        let noisy = TripRecorder()
        noisy.start(now: 0)
        for index in 0...50 {
            let time = Double(index)
            noisy.ingest(Fixtures.fix(
                id: index,
                time: time,
                x: random.symmetric(4),
                y: random.symmetric(4),
                accuracy: 8
            ), now: time)
            noisy.tick(now: time)
        }
        noisy.stop(now: 50)
        harness.check(noisy.distanceMeters < 2, "8 m stationary noise adds no fake distance")
        harness.check(noisy.ledgerIsBalanced(now: 50), "ledger balanced with noisy stationary")
    }

    static func testRecorderMoving(_ harness: Harness) {
        harness.section("Recorder: moving")

        let recorder = TripRecorder()
        recorder.start(now: 0)
        var fixes = Fixtures.line(from: 0, to: 59, speed: 1.5, accuracy: 4, noise: 0.4, seed: 91)
        fixes = fixes.enumerated().map { index, fix in
            var updated = fix
            updated.id = index
            return updated
        }
        for fix in fixes {
            recorder.ingest(fix, now: fix.monotonicTime)
        }
        recorder.stop(now: 59)
        harness.check(recorder.distanceMeters > 80 && recorder.distanceMeters < 100,
                      "distance follows the travelled path (\(recorder.distanceMeters) m)")
        harness.check(recorder.gapCount == 0, "confirmed movement produces no gap")
        harness.check(recorder.lastResolution == .committed, "final segment committed")
        harness.check(recorder.ledgerIsBalanced(now: 59), "ledger balanced after moving stop")

        let average = recorder.distanceMeters / recorder.activeSeconds(now: 59)
        harness.close(average, 1.5, tolerance: 0.25, "average speed")
    }

    static func testRecorderCurve(_ harness: Harness) {
        harness.section("Recorder: curve")

        let recorder = TripRecorder()
        recorder.start(now: 0)
        var fixes: [TripFix] = []
        var time = 0
        var id = 0
        // 15 s east, then 30 s north: path 67.5 m, direct chord about 50 m.
        while time <= 15 {
            fixes.append(Fixtures.fix(id: id, time: Double(time), x: 1.5 * Double(time), y: 0, accuracy: 4))
            time += 1
            id += 1
        }
        let turnTime = time - 1
        var travelled = 0.0
        while time <= 45 {
            travelled += 1.5
            let t = Double(time)
            fixes.append(Fixtures.fix(
                id: id,
                time: t,
                x: 1.5 * Double(turnTime),
                y: travelled,
                accuracy: 4
            ))
            time += 1
            id += 1
        }
        for fix in fixes {
            recorder.ingest(fix, now: fix.monotonicTime)
        }
        recorder.stop(now: 45)
        harness.check(recorder.distanceMeters > 55,
                      "curve distance uses intermediate points (\(recorder.distanceMeters) m)")
        harness.check(recorder.distanceMeters < 75, "curve distance is not inflated")

        let direct = MotionMath.haversine(
            latitude1: fixes.first?.latitude ?? 0,
            longitude1: fixes.first?.longitude ?? 0,
            latitude2: fixes.last?.latitude ?? 0,
            longitude2: fixes.last?.longitude ?? 0
        )
        harness.check(recorder.distanceMeters > direct + 5,
                      "path sum is larger than the direct chord")
    }

    static func testRecorderNoFix(_ harness: Harness) {
        harness.section("Recorder: GPS outage")

        let recorder = TripRecorder()
        recorder.start(now: 0)
        recorder.tick(now: 50)
        recorder.stop(now: 50)
        harness.check(recorder.distanceMeters == 0, "no positions add no distance")
        harness.check(recorder.gapSeconds > 40, "outage is recorded as a coverage gap")
        harness.check(recorder.ledgerIsBalanced(now: 50), "ledger balanced without fixes")

        let interrupted = TripRecorder()
        interrupted.start(now: 0)
        interrupted.ingest(Fixtures.fix(id: 0, time: 0, x: 0, y: 0, accuracy: 4), now: 0)
        interrupted.pause(now: 5)
        interrupted.resume(now: 100)
        interrupted.stop(now: 120)
        harness.check(abs(interrupted.activeSeconds(now: 120) - 25) < 0.2,
                      "paused time is not active time")
        harness.check(interrupted.ledgerIsBalanced(now: 120), "ledger balanced after resume")
    }

    static func testRecorderPauseResume(_ harness: Harness) {
        harness.section("Recorder: pause and resume")

        let recorder = TripRecorder()
        recorder.start(now: 0)
        for fix in Fixtures.line(from: 0, to: 20, speed: 1.5, accuracy: 4, noise: 0.3, seed: 55) {
            recorder.ingest(fix, now: fix.monotonicTime)
        }
        recorder.pause(now: 20)
        let distanceAtPause = recorder.distanceMeters
        harness.check(recorder.lastResolution != nil, "pause resolves the open segment")
        harness.check(recorder.pendingSeconds(now: 20) == 0, "pause leaves no pending segment")

        recorder.resume(now: 100)
        for fix in Fixtures.line(from: 20, to: 40, speed: 1.5, accuracy: 4, noise: 0.3, seed: 56) {
            var updated = fix
            updated.id += 100
            updated.monotonicTime += 80
            updated.gpsTime += 80
            recorder.ingest(updated, now: updated.monotonicTime)
        }
        recorder.stop(now: 120)
        harness.check(recorder.distanceMeters >= distanceAtPause, "distance never decreases")
        harness.check(recorder.ledgerIsBalanced(now: 120), "ledger balanced after resume and stop")
    }

    static func testRecorderDoesNotDoubleCommit(_ harness: Harness) {
        harness.section("Recorder: idempotency")

        let recorder = TripRecorder()
        recorder.start(now: 0)
        for fix in Fixtures.line(from: 0, to: 40, speed: 2, accuracy: 4, noise: 0.2, seed: 66) {
            recorder.ingest(fix, now: fix.monotonicTime)
        }
        recorder.stop(now: 40)
        let distance = recorder.distanceMeters
        let gaps = recorder.gapCount
        recorder.stop(now: 40)
        recorder.stop(now: 41)
        harness.check(recorder.distanceMeters == distance, "repeated stop does not add distance")
        harness.check(recorder.gapCount == gaps, "repeated stop does not add gaps")
    }

    static func testNativeDoesNotCloseSegments(_ harness: Harness) {
        harness.section("Native evidence cannot close segments")

        let engine = SpeedEngine()
        let recorder = TripRecorder()
        recorder.start(now: 0)

        for index in 0...10 {
            let time = Double(index)
            let fix = Fixtures.fix(
                id: index,
                time: time,
                x: 0,
                y: 0,
                accuracy: 19,
                nativeSpeed: 0,
                nativeSpeedAccuracy: 0.2
            )
            engine.ingest(fix)
            recorder.ingest(fix, now: time)
        }

        harness.check(engine.nativeMotionStatus == .stationary, "native stationary is available")
        harness.check(engine.positionMotionStatus == .stabilizing,
                      "an incomplete position window cannot confirm motion")
        harness.check(recorder.segmentStatus == .stabilizing,
                      "native evidence does not create a segment verdict")

        recorder.stop(now: 10)
        harness.check(recorder.distanceMeters == 0, "no distance from native evidence")
        harness.check(recorder.lastResolution == .gap, "segment without position evidence is a gap")

        // Positions in the 20-35 m band are distance-eligible only.
        let coarseEngine = SpeedEngine()
        let coarseRecorder = TripRecorder()
        coarseRecorder.start(now: 0)
        for index in 0...20 {
            let time = Double(index)
            let fix = Fixtures.fix(
                id: index,
                time: time,
                x: 1.2 * time,
                y: 0,
                accuracy: 30,
                nativeSpeed: 1.2,
                nativeSpeedAccuracy: 0.1
            )
            coarseEngine.ingest(fix)
            coarseRecorder.ingest(fix, now: time)
        }
        harness.check(coarseEngine.positionMotionStatus == .stabilizing,
                      "30 m positions cannot confirm motion")
        coarseRecorder.stop(now: 20)
        harness.check(coarseRecorder.distanceMeters == 0,
                      "30 m positions contribute no distance without confirmation")
        harness.check(coarseRecorder.lastResolution == .gap,
                      "unconfirmed coarse positions become a gap")
    }

    // MARK: - Demo session reliability

    static func testDemoSessionPhases(_ harness: Harness) {
        harness.section("Demo session: phases and idempotency")

        var state = DemoSessionState()
        harness.check(state.phase == .idle, "a new demo session starts idle")
        harness.check(!state.hasSession && !state.isRunning && !state.isPaused && !state.isStopped,
                      "idle exposes no active flags")

        harness.check(state.begin(), "start moves an idle session to running")
        harness.check(state.isRunning && state.hasSession, "running session is active")
        harness.check(!state.begin(), "starting an active session is rejected")
        harness.check(!state.resume(), "resuming a running session is rejected")

        harness.check(state.pause(), "pause moves a running session to paused")
        harness.check(state.phase == .paused && state.isPaused, "paused session reports paused")
        harness.check(!state.pause(), "pausing a paused session is rejected")
        harness.check(!state.begin(), "starting a paused session is rejected")

        harness.check(state.resume(), "resume moves a paused session to running")
        harness.check(state.isRunning && !state.isPaused, "resumed session reports running")
        harness.check(!state.resume(), "resuming a running session twice is rejected")

        harness.check(state.pause(), "second pause is accepted from running")
        harness.check(state.resume(), "second resume is accepted from paused")
        harness.check(state.stop(), "stop moves a running session to stopped")
        harness.check(state.phase == .stopped && state.isStopped && state.isPaused && !state.isRunning,
                      "stopped session is visible without running")
        harness.check(!state.stop(), "stopping a stopped session is rejected")
        harness.check(state.resume(), "a stopped session can resume")

        harness.check(state.reset(), "reset clears an active session")
        harness.check(state.phase == .idle && !state.hasSession, "reset returns to idle")
        harness.check(!state.reset(), "resetting an idle session is a no-op")

        var sequence = DemoSessionState()
        _ = sequence.begin()
        _ = sequence.pause()
        _ = sequence.resume()
        _ = sequence.pause()
        _ = sequence.resume()
        let sequenceReset = sequence.reset()
        harness.check(sequenceReset && sequence.phase == .idle,
                      "start-pause-resume-pause-resume-reset completes")

        var rapid = DemoSessionState()
        var rapidValid = true
        for _ in 0..<25 {
            rapidValid = rapid.begin()
                && rapid.pause()
                && rapid.resume()
                && rapid.stop()
                && rapid.reset()
                && rapidValid
        }
        harness.check(rapidValid, "25 rapid full cycles all succeed in order")
        harness.check(rapid.phase == .idle && !rapid.hasSession,
                      "rapid cycles leave no active session")
    }

    static func testDemoPlaybackGate(_ harness: Harness) {
        harness.section("Demo playback: generation gate")

        var gate = DemoPlaybackGate()
        harness.check(gate.generation == 0, "gate starts without a generation")

        let first = gate.begin()
        harness.check(first == 1 && gate.isCurrent(first), "first loop token is current")

        gate.end()
        harness.check(!gate.isCurrent(first), "ending playback invalidates the old token")

        let second = gate.begin()
        harness.check(second == 3, "a restart advances past the invalidated token")
        harness.check(!gate.isCurrent(first), "an old token cannot step a new run")
        harness.check(gate.isCurrent(second), "the restarted token is current")

        let third = gate.begin()
        harness.check(!gate.isCurrent(second), "two rapid starts leave only one current token")
        harness.check(gate.isCurrent(third), "the newest token remains current")

        gate.end()
        harness.check(!gate.isCurrent(third), "pause/reset rejects the newest token too")

        var tokens = Set<Int>()
        var unique = true
        for _ in 0..<50 {
            let token = gate.begin()
            unique = tokens.insert(token).inserted && unique
            gate.end()
        }
        harness.check(unique, "50 playback restarts never reuse a token")
        harness.check(tokens.count == 50, "every playback restart has its own generation")
    }

    static func testTripControlRouting(_ harness: Harness) {
        harness.section("Trip controls: source routing")

        harness.check(
            TripControlRouting.target(for: .start, demoEnabled: true, demoSessionActive: false) == .demo,
            "start uses the demo source when demo mode is enabled"
        )
        harness.check(
            TripControlRouting.target(for: .start, demoEnabled: false, demoSessionActive: false) == .live,
            "start uses live GPS when demo mode is disabled"
        )
        harness.check(
            TripControlRouting.target(for: .start, demoEnabled: true, demoSessionActive: true) == .demo,
            "start stays with the demo source while a session is active"
        )
        harness.check(
            TripControlRouting.target(for: .start, demoEnabled: false, demoSessionActive: true) == .live,
            "a stale demo flag cannot capture a new live start"
        )

        for action in [TripControlAction.pause, .resume, .reset] {
            harness.check(
                TripControlRouting.target(for: action, demoEnabled: true, demoSessionActive: true) == .demo,
                "\(action.rawValue) follows the active demo session"
            )
            harness.check(
                TripControlRouting.target(for: action, demoEnabled: true, demoSessionActive: false) == .live,
                "\(action.rawValue) stays live without a demo session"
            )
            harness.check(
                TripControlRouting.target(for: action, demoEnabled: false, demoSessionActive: false) == .live,
                "\(action.rawValue) uses live GPS when demo mode is off"
            )
        }
    }
}
