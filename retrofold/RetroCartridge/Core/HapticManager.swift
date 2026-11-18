//
//  HapticManager.swift
//  RetroCartridge
//

import CoreHaptics
import Observation
import SwiftUI

@Observable
final class HapticManager {
    
    private var engine: CHHapticEngine?
    
    init() {}
    
    /// Prepares the CoreHaptics engine and handles graceful error recovery.
    func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("Haptics not supported on this device.")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            
            engine?.stoppedHandler = { reason in
                print("Haptic engine stopped due to: \(reason.rawValue)")
            }
            
            engine?.resetHandler = { [weak self] in
                do {
                    try self?.engine?.start()
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }
            
            try engine?.start()
        } catch {
            print("Haptic engine creation error: \(error)")
        }
    }
    
    /// Plays a predefined haptic pattern.
    func playHaptic(_ type: HapticEventType) {
        guard let engine = engine else { return }
        
        var events = [CHHapticEvent]()
        
        switch type {
        case .buttonPress:
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
            
        case .cartridgeInsert:
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
            
        case .hingeClick:
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
            
        case .gameEvent:
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        }
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
}
