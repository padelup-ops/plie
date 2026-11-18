//
//  HingeEngine.swift
//  RetroCartridge
//
//  Supplies a smoothed hinge angle for visual effects (the CRT tube
//  curvature) and fires a callback when the hinge swings past 90° while
//  unfolding.
//
//  ## Data source
//
//  The primary source is the iOS 27.1 hinge API: `AdaptiveConsoleLayout`
//  forwards `onHingeChange` updates to `updateFromHardware(_:)`, which gives the
//  real angle and status. The system decides the update rate and precision, so
//  the angle still passes through the smoothing spring.
//
//  When no hinge is reported (the hierarchy doesn't provide hinge updates),
//  the engine falls back to the display posture from `PostureManager`: the
//  outer display means closed (0°), and the inner display means open (180°).
//  Posture changes then spring from one to the other, so unfolding still
//  plays a 0° → 180° sweep.
//
//  Per Apple's HIG the hinge angle drives visual effects only, never layout.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class HingeEngine {

    // MARK: - Published State

    /// The smoothed hinge angle (0.0 = closed, 180.0 = fully flat).
    /// Used ONLY for visual effects (CRT shader uniforms, parallax).
    /// MUST NOT be used for layout decisions.
    /// Defaults to flat until a hinge data source reports otherwise.
    private(set) var hingeAngle: Float = 180.0 {
        didSet {
            normalizedAngle = hingeAngle / 180.0
            isPast90Degrees = hingeAngle >= 90.0
            isUnfolding = hingeAngle > oldValue
        }
    }

    /// Normalized angle from 0.0 to 1.0 for easy shader interpolation.
    private(set) var normalizedAngle: Float = 1.0

    /// Indicates if the angle crossed the 90 degree threshold (useful for audio triggers).
    private(set) var isPast90Degrees: Bool = true

    /// Indicates if the device is currently unfolding.
    private(set) var isUnfolding: Bool = false

    // MARK: - Events

    /// Called once each time the hinge swings upward through 90° while
    /// unfolding. Debounced with hysteresis, so hovering around 90° doesn't
    /// retrigger it.
    @ObservationIgnored
    var onUnfoldPast90Degrees: (@MainActor () -> Void)?

    // MARK: - Tuning

    /// Natural frequency of the critically damped smoothing spring, in rad/s.
    /// About 7 rad/s settles a full 0° → 180° sweep in ~0.8 s.
    private static let springFrequency: Float = 7.0
    /// The angle at which the chime fires while unfolding.
    private static let chimeAngle: Float = 90.0
    /// The angle the hinge must fall below before the chime can fire again.
    private static let chimeRearmAngle: Float = 80.0
    /// The minimum time between two chimes.
    private static let chimeCooldown: Duration = .milliseconds(600)
    /// Posture changes this soon after `startListening` are the first display
    /// measurement, not a physical fold. They snap without a sweep or chime.
    private static let launchGracePeriod: Duration = .milliseconds(750)
    /// Target changes smaller than this are sensor noise and are ignored.
    private static let targetDeadband: Float = 0.5

    // MARK: - Internal State

    @ObservationIgnored private var targetAngle: Float = 180.0
    @ObservationIgnored private var velocity: Float = 0.0
    @ObservationIgnored private var animationTask: Task<Void, Never>?

    @ObservationIgnored private var postureManager: PostureManager?
    /// True while `onHingeChange` delivers real hinge data; posture changes are
    /// then ignored.
    @ObservationIgnored private var hasHardwareHinge = false
    @ObservationIgnored private var isListening = false
    @ObservationIgnored private var listeningStart: ContinuousClock.Instant?

    @ObservationIgnored private var isChimeArmed = false
    @ObservationIgnored private var lastChime: ContinuousClock.Instant?

    #if DEBUG
    /// If true, `simulatedAngle` overrides the posture-derived angle (DEBUG only).
    var isSimulated: Bool = false {
        didSet { applySimulation() }
    }

    /// The angle used while `isSimulated` is on (DEBUG only).
    var simulatedAngle: Float = 180.0 {
        didSet { applySimulation() }
    }

    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    #endif

    init() {}

    // MARK: - Lifecycle

    /// Starts deriving the hinge angle from the display posture.
    ///
    /// In DEBUG builds, two launch arguments drive the angle without the
    /// posture, for tuning the shader and the chime:
    /// - `-HingeSimulatedAngle <degrees>` holds a fixed angle.
    /// - `-HingeSimulateSweep YES` folds and unfolds continuously.
    func startListening(following postureManager: PostureManager) {
        stopListening()
        self.postureManager = postureManager
        isListening = true
        listeningStart = .now

        // Start at the current posture without a sweep.
        snap(to: Self.angle(for: postureManager.currentPosture))
        observePosture()

        #if DEBUG
        startDebugSimulationFromLaunchArguments()
        #endif
    }

    /// Stops listening for posture changes and halts any running animation.
    func stopListening() {
        isListening = false
        postureManager = nil
        animationTask?.cancel()
        animationTask = nil
        velocity = 0
        #if DEBUG
        sweepTask?.cancel()
        sweepTask = nil
        #endif
    }

    // MARK: - Angle Input

    /// Sets the raw angle the smoothed `hingeAngle` springs towards.
    func setTargetAngle(_ angle: Float) {
        let clamped = min(max(angle, 0), 180)
        guard abs(clamped - targetAngle) >= Self.targetDeadband else { return }
        targetAngle = clamped
        startAnimatingIfNeeded()
    }

    /// Feeds a hinge update from `onHingeChange`. `nil` means no hinge data is
    /// available, so the engine falls back to the display posture.
    func updateFromHardware(_ hinge: DeviceHinge?) {
        #if DEBUG
        if isSimulated || sweepTask != nil { return }
        #endif
        
        guard let hinge else {
            if hasHardwareHinge {
                hasHardwareHinge = false
                postureDidChange()
            }
            return
        }
        
        hasHardwareHinge = true
        let angle: Float = hinge.status == .closed ? 0 : Float(hinge.angle.degrees)
        if let listeningStart, listeningStart.duration(to: .now) < Self.launchGracePeriod {
            snap(to: angle)
        } else {
            setTargetAngle(angle)
        }
    }
    
    /// Jumps straight to an angle without a sweep or a chime.
    private func snap(to angle: Float) {
        animationTask?.cancel()
        animationTask = nil
        velocity = 0
        targetAngle = min(max(angle, 0), 180)
        hingeAngle = targetAngle
        isUnfolding = false
        isChimeArmed = hingeAngle < Self.chimeRearmAngle
    }

    /// The fallback angle for a posture when no hinge data is available.
    private static func angle(for posture: DevicePosture) -> Float {
        switch posture {
        case .closed: 0
        case .fullyOpen: 180
        }
    }

    // MARK: - Posture Observation

    /// Tracks `postureManager.currentPosture` and re-registers after each change.
    private func observePosture() {
        guard isListening, let postureManager else { return }
        _ = withObservationTracking {
            postureManager.currentPosture
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.postureDidChange()
            }
        }
    }

    private func postureDidChange() {
        guard isListening, let postureManager else { return }
        guard !hasHardwareHinge else {
            observePosture()
            return
        }
        let angle = Self.angle(for: postureManager.currentPosture)

        #if DEBUG
        if isSimulated || sweepTask != nil {
            observePosture()
            return
        }
        #endif

        if let listeningStart, listeningStart.duration(to: .now) < Self.launchGracePeriod {
            snap(to: angle)
        } else {
            setTargetAngle(angle)
        }
        observePosture()
    }

    // MARK: - Smoothing

    /// Runs the smoothing spring on the main actor until it settles.
    private func startAnimatingIfNeeded() {
        guard animationTask == nil else { return }
        animationTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = clock.now
                let elapsed = last.duration(to: now)
                last = now
                let seconds = Float(elapsed.components.seconds)
                    + Float(elapsed.components.attoseconds) / 1e18
                guard let self, self.step(dt: min(seconds, 1.0 / 30.0)) else { break }
            }
            // A cancelled task has already been replaced; don't clear its successor.
            if !Task.isCancelled {
                self?.animationTask = nil
            }
        }
    }

    /// Advances the critically damped spring by `dt` seconds.
    /// - Returns: `true` while the spring is still moving.
    private func step(dt: Float) -> Bool {
        let omega = Self.springFrequency
        let displacement = hingeAngle - targetAngle
        let acceleration = -omega * omega * displacement - 2 * omega * velocity
        velocity += acceleration * dt
        let previous = hingeAngle
        let next = previous + velocity * dt

        if abs(next - targetAngle) < 0.05 && abs(velocity) < 0.5 {
            velocity = 0
            hingeAngle = targetAngle
            isUnfolding = false
            detectChime(from: previous, to: targetAngle)
            return false
        }

        hingeAngle = next
        detectChime(from: previous, to: next)
        return true
    }

    // MARK: - 90° Chime

    /// Fires `onUnfoldPast90Degrees` on an upward crossing of 90°. After it
    /// fires, the hinge must drop below 80° and the cooldown must pass before
    /// it can fire again.
    private func detectChime(from previous: Float, to current: Float) {
        if current < Self.chimeRearmAngle {
            isChimeArmed = true
        }
        guard isChimeArmed,
              previous < Self.chimeAngle,
              current >= Self.chimeAngle else { return }

        let now = ContinuousClock.now
        if let lastChime, lastChime.duration(to: now) < Self.chimeCooldown { return }

        isChimeArmed = false
        lastChime = now
        onUnfoldPast90Degrees?()
    }

    // MARK: - DEBUG Simulation

    #if DEBUG
    private func applySimulation() {
        if isSimulated {
            setTargetAngle(simulatedAngle)
        } else if let postureManager {
            setTargetAngle(Self.angle(for: postureManager.currentPosture))
        }
    }

    /// Reads the DEBUG launch arguments described in `startListening(following:)`.
    private func startDebugSimulationFromLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "HingeSimulateSweep") {
            sweepTask = Task { @MainActor [weak self] in
                // Fold from 180° to 20° and back every 4 seconds.
                var phase: Float = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    phase += 0.05 / 4.0 * 2 * .pi
                    self?.setTargetAngle(100 + 80 * cos(phase))
                }
            }
        } else if defaults.object(forKey: "HingeSimulatedAngle") != nil {
            simulatedAngle = defaults.float(forKey: "HingeSimulatedAngle")
            isSimulated = true
        }
    }
    #endif
}
