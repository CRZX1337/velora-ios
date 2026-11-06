import Foundation

/// Display-only interpolation for the speed readout.
///
/// The measurement side publishes discrete values at CoreLocation's cadence.
/// Drawing those values directly makes the dial step and stutter, so the dial is
/// driven by this curve instead: a critically damped approach from wherever the
/// readout currently is toward the newest measured value, evaluable at any
/// instant between two samples.
///
/// The curve carries velocity across retargets, so a new sample bends the motion
/// instead of restarting it. A repeated sample changes nothing. Nothing in the
/// measurement pipeline reads this type: `SpeedEngine`, `TripRecorder` and the
/// trip accounting keep their own values untouched.
struct SpeedDisplayCurve: Equatable, Sendable {
    /// Seconds of response. A step covers ~96% of its distance in 5 x response.
    static let defaultResponse: Double = 0.26
    /// Safety limit for settling, in multiples of `response`. The landing
    /// threshold normally lands first; this only stops a pathological curve.
    static let settleFactor: Double = 20
    /// Remaining distance that is invisible in the readout. Landing on the
    /// measurement here keeps a stopped dial from freezing a fraction short.
    static let landingDistance: Double = 0.02
    /// Rate below which such a remainder may be snapped away.
    static let landingRate: Double = 0.2

    let from: Double
    let to: Double
    let startTime: Double
    let initialVelocity: Double
    let response: Double

    /// A curve that already rests at `target`.
    init(
        target: Double,
        at time: Double = 0,
        response: Double = SpeedDisplayCurve.defaultResponse
    ) {
        let value = Self.sanitized(target)
        self.from = value
        self.to = value
        self.startTime = time.isFinite ? time : 0
        self.initialVelocity = 0
        self.response = Self.sanitizedResponse(response)
    }

    init(
        from: Double,
        to: Double,
        startTime: Double,
        initialVelocity: Double,
        response: Double = SpeedDisplayCurve.defaultResponse
    ) {
        self.from = Self.sanitized(from)
        self.to = Self.sanitized(to)
        self.startTime = startTime.isFinite ? startTime : 0
        self.initialVelocity = initialVelocity.isFinite ? initialVelocity : 0
        self.response = Self.sanitizedResponse(response)
    }

    /// The measured value this curve is travelling toward.
    var target: Double { to }

    /// Whether the drawn value actually has to move.
    private var moves: Bool {
        abs(to - from) > 1e-9 || abs(initialVelocity) > 1e-9
    }

    /// Coefficients of the critically damped solution
    /// `value(t) = to + (a + b * t) * exp(-t / response)`.
    private var coefficients: (a: Double, b: Double) {
        let a = from - to
        return (a, initialVelocity + a / response)
    }

    /// The value the dial draws at `time`. Pure: the same time always yields the
    /// same value, so a redraw can never change what is on screen.
    func value(at time: Double) -> Double {
        let drawn = travel(at: time)
        return isResting(at: time, drawn: drawn) ? to : drawn
    }

    private func travel(at time: Double) -> Double {
        let elapsed = time - startTime
        guard elapsed > 0 else { return from }
        guard moves else { return to }

        let (a, b) = coefficients
        let traveled = (a + b * elapsed) * exp(-elapsed / response)
        return max(0, to + traveled)
    }

    /// Rate of change in target units per second.
    func rate(at time: Double) -> Double {
        let elapsed = time - startTime
        guard elapsed > 0 else { return initialVelocity }
        guard moves else { return 0 }

        let (a, b) = coefficients
        let decay = exp(-elapsed / response)
        return decay * (b - (a + b * elapsed) / response)
    }

    /// Whether the dial can stop redrawing at `time`.
    func isSettled(at time: Double) -> Bool {
        guard moves else { return true }
        return isResting(at: time, drawn: travel(at: time))
    }

    private func isResting(at time: Double, drawn: Double) -> Bool {
        let elapsed = time - startTime
        guard elapsed >= 0 else { return false }
        if elapsed >= response * Self.settleFactor { return true }
        return abs(drawn - to) < Self.landingDistance && abs(rate(at: time)) < Self.landingRate
    }

    /// Bends the curve toward a new measurement without restarting it: the drawn
    /// value is kept exactly and half of the current velocity carries over, which
    /// removes the kink without letting rapid samples overshoot.
    func advanced(
        to target: Double,
        at time: Double,
        response: Double = SpeedDisplayCurve.defaultResponse
    ) -> SpeedDisplayCurve {
        guard target.isFinite, target >= 0 else { return self }

        // A repeated sample must not restart anything.
        if abs(target - to) < 0.0005, !isSettled(at: time) { return self }

        let current = value(at: time)
        let carried = rate(at: time) * 0.5

        if abs(target - current) < 0.0005, abs(carried) < 0.02 {
            return SpeedDisplayCurve(from: target, to: target, startTime: time, initialVelocity: 0, response: response)
        }

        return SpeedDisplayCurve(
            from: current,
            to: target,
            startTime: time,
            initialVelocity: carried,
            response: response
        )
    }

    private static func sanitized(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func sanitizedResponse(_ response: Double) -> Double {
        guard response.isFinite, response > 0 else { return defaultResponse }
        return max(0.01, response)
    }
}
