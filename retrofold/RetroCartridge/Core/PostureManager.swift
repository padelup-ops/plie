//
//  PostureManager.swift
//  RetroCartridge
//

import SwiftUI
import Observation

@Observable
final class PostureManager {
    
    /// The device posture, derived from which display the app is on.
    private(set) var currentPosture: DevicePosture = .closed
    
    /// True on the outer (cover) display, false on the inner display.
    private(set) var isCompactWidth: Bool = false
    
    init() {}
    
    /// Updates the posture from the display the app is on, measured by its full
    /// screen size. Unlike size classes this stays stable whatever orientation
    /// the scene is locked in.
    ///
    /// The first measurement at launch is 0×0, before the window has a
    /// size. It's ignored: read as the outer display, it made a launch on
    /// the inner display look like an unfold, which inserted the cartridge
    /// instead of showing the shelf.
    func updateDisplay(fullScreenSize: CGSize) {
        guard fullScreenSize.width > 0, fullScreenSize.height > 0 else { return }
        let display = DuoDisplay(size: fullScreenSize)
        isCompactWidth = display == .outer
        currentPosture = display == .inner ? .fullyOpen : .closed
    }
}

/// Identifies the iPhone Duo display from its full-screen size in points,
/// which works in any orientation: the outer display is ≈466×678 pt and the
/// inner display ≈669×871 pt. The app ships for iPhone Duo only.
enum DuoDisplay: Equatable {
    case outer
    case inner
    
    init(size: CGSize) {
        self = min(size.width, size.height) < 600 ? .outer : .inner
    }
}
