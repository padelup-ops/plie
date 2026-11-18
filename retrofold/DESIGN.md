# DESIGN.md — iPhone Duo platform reference

A reference for designing and building Foldcade on iPhone Duo. It collects Apple's official guidance together with what we measured ourselves on the simulator. Apple's statements are quoted or paraphrased with their source. Our own findings are marked **Measured**.

- **Research date:** 2026-09-23
- **Toolchain:** Xcode 27.1 beta (27A9269), iOS 27.1 SDK, iPhone Duo simulator on the iOS 27.1 runtime
- **Launch:** iPhone Duo ships on 2026-10-23 running iOS 27.1

## Sources

| Source | Topics |
| :--- | :--- |
| [Get ready for iPhone Duo](https://developer.apple.com/iphone-duo/) | Hub: videos, labs, tools |
| [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) | Poses, vertical controls, reserved regions, games |
| [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo) | Resizing, bars, arrangements, reserved regions |
| Tech talk 111466, [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/) | Poses, controls on the side, immersive layouts, fold avoidance |
| Tech talk 111461, [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) | **SDK behavior, orientation per display**, safe areas |
| Tech talk 111462, [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/) | Vertical bars in depth |
| Tech talk 111463, [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/) | Reserved regions, `ArrangementView` |
| Tech talk 111464, [Leverage multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/) | Hinge API, multitasking, scene accessories |
| Tech talk 111465, [Build a great camera experience](https://developer.apple.com/videos/play/tech-talks/111465/) | Camera (not relevant to this app) |
| [Xcode 27.1 beta release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes) | Simulator known issues |

The Group Lab recordings (meet-with-apple/285, 286) have no published transcript.

---

## 1. Hardware and geometry

**Outer display (5.4")**
- Its natural orientation is portrait, with the **hinge along the left edge** and the **camera in the top-right corner**.
- It is "wider and shorter than a traditional iPhone."
- The camera occlusion is always present.

**Inner display (7.6", roughly 3:4)**
- Its natural orientation is landscape, with the **hinge running vertically through the middle** and the camera top-right.
- The camera sits behind the display and is only visible while it's active.

**Measured with the iOS 27.1 SDK:**

| | Scene size (pt) | Safe area insets (t, l, b, r) | Notes |
| :--- | :--- | :--- | :--- |
| Outer, interface `.landscapeLeft` | 678 × 466 | 0, 0, 34, 84 | 84 pt side column on the trailing edge |
| Outer, interface `.landscapeRight` | 678 × 466 | 0, 84, 34, 0 | the column moves with the hardware |
| Inner, interface `.portraitUpsideDown` | 669 × 951 | 82, 0, 34, 0 | status bar strip on top; the hinge is at y = 475.5 |

- Pixel sizes: outer panel 1398 × 2034 px, inner panel 2007 × 2853 px, both at 3×.
- With the older iOS 27.0 SDK, the app was *excluded* from the 80 pt column. See §3.

---

## 2. Poses

The poses are closed, partially folded like a book, set on a table like a laptop (inner display facing you), standing on its edges (tent), and fully open.

- **Table (laptop) pose:** "The top region works well for content that benefits from visibility at a distance. The bottom region works well for interactive controls." (111463) "Media can sit at the top, while tappable controls live on a stable base at the bottom." (111466) Our CRT-above, controls-below console matches this pose.
- **Consistency across poses:** "If you decide to do a special layout for this pose, just be sure it has all the same controls and general hierarchy as other poses. You don't want to tie functionality to a specific pose." (111466)
- **Tent pose:** "iPhone Duo is a great opportunity to support landscape orientation, as people may want to set the phone down like a tent." (111461)
- **Partially folded:** interactive elements are nudged away from the fold, and system components (sheets, alerts, menus, toolbar buttons) do this automatically. "Scrollable content doesn't need to avoid this region." (111466)

---

## 3. SDK version determines screen space (critical)

From 111461 ("Build with the latest SDK", 0:30):

| Built with | Outer display (closed) | Inner display (open) |
| :--- | :--- | :--- |
| iOS 26 SDK or earlier | App uses only the space **left of the status bar and camera** | "a familiar size and aspect ratio" (scaled) |
| iOS 27 SDK | same as above | "extends to the left of the status bar area" |
| **iOS 27.1 SDK** | "**extends to the edge of the screen**" | full screen |

"Standard navigation and toolbar buttons now lay out vertically under the status bar" only when built with 27.1.

**Measured:** with the 27.0 SDK, the scene was 678 × 386 on the outer display and 669 × 871 on the inner display. The 80 pt column was black and couldn't be drawn into. Stretching the window didn't help, because content was clipped to the scene. With the 27.1 SDK both scenes are full screen.

**Rule:** always build with the iOS 27.1 SDK (Xcode 27.1+) or later.

---

## 4. Interface orientation (critical)

From 111461:

- **Outer display:** "Interface orientation on the outer display behaves like any other iPhone." It honors `supportedInterfaceOrientations`.
- **Inner display:** "Interface orientation on the inner display behaves differently. **The inner display doesn't honor your supported interface orientations.**"
- **`UIRequiresFullScreen`:** "iPhone Duo will continue to honor the UIRequiresFullScreen key, but your app will still resize when someone opens or closes their iPhone Duo." And: "iPhone Duo respects your supported interface orientations, but **your app will scale on the inner display**, including in Split View multitasking." This is the letterboxing we saw earlier.
- **Layout decisions:** "avoid checking interface orientation for layout decisions. Use size classes instead."

From the HIG (Best practices): "**Make your game playable in every device pose.** You can choose to lock to either portrait or landscape orientation, but be sure to fill the screen as the device pose changes. … Prefer changing the aspect ratio over letterboxing or pillarboxing in games; if you can't avoid letterboxing or pillarboxing, add artwork to the padding area to help the experience feel full screen."

**Measured with the 27.1 SDK:**
- `prefersInterfaceOrientationLocked = true` on the root controller reports `effectiveGeometry.isInterfaceOrientationLocked == false`, even though the scene is centered, screen-sized and not occluded. It was `true` only with the 27.0 SDK, in legacy mode.
- A per-display `supportedInterfaceOrientations` of `.portrait` on the inner display was ignored: the scene came up `.portraitUpsideDown`. This matches the talk.
- The outer display rotated between `.landscapeLeft` and `.landscapeRight` with an all-orientations mask. A single-orientation mask should hold there, per the talk.
- The user verified the inner display in landscape (book pose) in Device Hub: the adaptive split puts the CRT and the controls side by side.

**Resolution (see §10):**
- **Outer display:** locked to `.landscapeLeft` (hinge on top). Verified in Device Hub.
- **Inner display:** the layout adapts to the system orientation and always splits at the fold (option A). Counter-rotating to pin the layout (option B) was rejected, and `FixedOrientation` was removed.

---

## 5. Vertical bars (the "status bar column")

**What moves to the side**
- On iPhone Duo, the Dynamic Island, the status bar, and the app's navigation, toolbar and tab bar items share one hardware-aligned column.
- "toolbars, tab bars, and navigation controls that are typically at the top and bottom of the display move to the side."
- Items keep their top-to-bottom order. "Toolbar buttons at the top of your app move to the top of this vertical space, while toolbar buttons on the bottom move to the bottom… if you have a tab bar, it stays bottom aligned."
- The column "stays on the same side of the device in right-to-left languages."

**Where bars are vertical and where they aren't**

| Display / interface | Bars |
| :--- | :--- |
| Outer, portrait or landscape | Vertical, on the side (camera edge) |
| Inner, landscape | Vertical, on the side |
| **Inner, portrait** | **Horizontal**: "The only pose where we've kept horizontal bars is on the inner display in portrait." |
| Split views | Only the detail column goes vertical |
| Sheets | Outer: vertical. Inner: horizontal, or vertical for trailing-placed sheets |

**How to opt in**
- Build with the 27.1 SDK.
- Use the bars of a navigation container: SwiftUI `NavigationStack`/`NavigationSplitView`/`TabView` plus `.toolbar { }`; UIKit `UINavigationController`/`UITabBarController` with `toolbarItems`/`navigationItem`.
- Custom `UIToolbar`, `UINavigationBar` and `UITabBar` bars are ignored.

**What an item needs to go vertical**
- **An icon plus a title**, e.g. `Label("Store", systemImage: "bag.fill")`.
  - "If your item has a title and doesn't have an icon, the system doesn't present it vertically."
  - "If your item uses a custom view rather than a title or icon, the system doesn't present it vertically." Use `.axisBehavior(.verticalPreferred)` to allow a custom view, and design it to fit the fixed column width.
- **Keep an item horizontal:** `.axisBehavior(.horizontalOnly)`, e.g. for items that switch between a symbol and text.
- **Order:** Back/Close at the top (`ToolbarItem(placement: .cancellationAction)`), then prominent actions (`.topBarPinnedTrailing`), then the rest (`.bottomBar` items go to the bottom of the column).
- **Spacers:** flexible spacers are zero-size vertically; don't add manual spacing. Group items with `ToolbarItemGroup`.
- **Overflow:** items overflow bottom to top. Use `.visibilityPriority(.high)`, `ToolbarOverflowMenu`, and `.toolbarVerticalCompressionBehavior(...)`.
- **Detecting a vertical bar:** `@Environment(\.toolbarVerticalEdge)` (nil when bars can't go vertical); UIKit `traitCollection.verticalBarEdge`.
- **Opting out:** `.toolbarVerticalBehavior(.disabled)`, for example a Calculator-style app that should expand fully.
- **No scroll-edge background:** a vertical bar has no scroll-edge background by default. It gains one with Reduce Transparency, so keep content legible under it.
- **Text-only titles** stay in a horizontal bar. "Keep text-based buttons to a minimum. Labels that include text stay in a horizontal bar."

**Measured:**
- Built with 27.1 and wrapped in `NavigationStack`, the outer display showed `Label` items (Skins, Store) **vertically in the side column**.
- A custom `Text("RETRO CARTRIDGE")` item stayed horizontal and floated over the content, so the app name became a `navigationTitle` instead. It shows as a small title at the top-leading corner. (Removed on 2026-10-17: the library header already prints the name.)
- The shipped setup is a `ToolbarItemGroup(placement: .topBarTrailing)` with the two labels.
- Built with 27.0, every item floated horizontally inside the window.

---

## 6. Full-screen and immersive layouts

- "Consider using the full display width for interfaces where bars aren't necessary. Some layouts can span the full display, which works well for visual, immersive interfaces that don't scroll, as long as nothing conflicts with the Dynamic Island or the status bar. Calculator, for example, occupies the full width of the display." (HIG)
- "Some UI should still center on the full display though, no offset. That works well for immersive, highly visual interfaces that don't scroll, as long as you're sure interactive elements won't be blocked by controls on the right." (111466)
- Mix approaches: a full-bleed background with inset interactive content. Extend backgrounds under a vertical bar with `.backgroundExtensionEffect()` (SwiftUI) or `UIBackgroundExtensionView` (UIKit).
- Safe areas are asymmetric; never assume opposite insets are equal (111461). Use `bounds.inset(by: safeAreaInsets)`.
- Use `ConcentricRectangle()` to match the display's corner radius.
- For custom bars or edge-to-edge UI, use **reserved regions** (§7) to maximize space without colliding with system UI.
- Don't use `UIScreen.main` ("ambiguous and will be deprecated"). Use `window.windowScene.screen`.

---

## 7. Reserved regions and arrangement views (iOS 27.1)

**Reserved regions** (111463)
- **Division:** the fold. It is active only while partially folded, and zero-width when flat.
- **Occlusion:** a camera. The outer camera is always present; the inner camera only while active.
- Only active regions are returned by default; use `.includeInactive` for high-level decisions such as an even number of grid columns.

```swift
// SwiftUI
GeometryReader { proxy in
    let folds = proxy.reservedRegions(kind: .division, options: .includeInactive)
    let cameras = proxy.reservedRegions(kind: .occlusion)
    let frames = folds.map(\.frame)
}
// UIKit
let regions = view.reservedRegions(kind: .division)
```

**Displacement patterns:** move elements individually or as a unit, avoid excessive movement, and don't displace continuously scrolling content.

**`ArrangementView`** (SwiftUI) / **`UIArrangementViewController`** (UIKit)
- A primary + secondary container that adapts to size and to the fold.
- `.split` splits horizontally when wider than tall, vertically when taller than wide, and adjusts to the fold. Restrict it with `.split.axes(.horizontal)`.
- `.overlay` stacks the views; when partially folded it puts them side by side, relative to the fold.
- Don't put it inside scroll views or lists, and don't put navigation containers inside it.

```swift
NavigationStack {
    ArrangementView { PrimaryView() } secondary: { SecondaryView() }
        .arrangementViewStyle(.split)
}
```

---

## 8. Hinge API (iOS 27.1)

"Hinge data is observed live, and is ideal for driving interactions or effects. **For layout, use the arrangement and region APIs.**" (111464)

```swift
// SwiftUI
.onHingeChange { oldContext, newContext in
    // hinge is nil on devices without one
    if let hinge = newContext.hinge, hinge.status == .partiallyOpen {
        effect = map(hinge.angle)   // continuous angle
    }
}
// UIKit
let interaction = UIHingeInteraction { _, update in
    guard let hinge = update.hinge else { return }   // nil when leaving a hinge-providing hierarchy
    use(hinge.angle /* radians */, hinge.status /* .closed / .partiallyOpen / .fullyOpen */)
}
view.addInteraction(interaction)
```

The update rate and precision are system policy; prefer `status` when you only need closed, partial or fully open.

---

## 9. Multitasking, scenes, simulator

- "All apps participate in multitasking on iPhone Duo": side-by-side Split View on the inner display, plus a stacked video + app layout. With Split View, the vertical controls sit on each app's outer edge.
- New windows can't be created on the outer display. Handle scene-request errors, e.g. with `UIWindowSceneActivationAction`.
- Scene accessories (`.sceneAccessory`, `CameraCaptureAccessory`) show content on another display. The camera one only works for camera apps.
- **Device Hub:** open, close, rotate and fold with the control buttons.
  - Known issues: slow first launch; no StandBy; most app extensions don't run.
  - **Measured:** `xcrun simctl io <UDID> screenshot --display=1` captures the **outer** display and `--display=3` the **inner** one, both in interface orientation. The iOS 27.1 runtime only supports iPhone Duo. `xcodebuild test` hung on the Duo with the 27.0 SDK (legacy mode) but runs fine with the 27.1 SDK.

---

## 10. Decisions for Foldcade

**Decided on 2026-09-23 (the user chose option A):**
- **Inner display follows the HIG.** The console adapts to the system orientation and always splits at the fold:
  - CRT above, controls below in portrait (laptop/clamshell pose);
  - side by side in landscape (book pose).
  - The fold comes from `reservedRegions(kind: .division, options: .includeInactive)` (`FoldSplit` in `FullScreenLayout.swift`), and each half pads its own outer safe-area edges.
- **Outer display is locked to `.landscapeLeft`,** which puts the hinge on top (`ConsoleHostingController.supportedInterfaceOrientations`).
- **Removed:** `prefersInterfaceOrientationLocked` and the counter-rotating `FixedOrientation`.

**Implemented:**

| Area | Implementation |
| :--- | :--- |
| Toolchain | Deployment target and SDK iOS 27.1 (Xcode 27.1+) |
| Toolbar | `NavigationStack` root, no `navigationTitle`; the app icon (`BrandIcon`) as a decorative `.topBarLeading` item. `Label` items in two `.topBarTrailing` groups: Skins/Screen/Labels (`.visibilityPriority(.high)`) and Store/Records, which go vertical in the side column. Hidden over a running console. The library's custom header buttons were removed. |
| Hinge | `onHingeChange` → `HingeEngine.updateFromHardware(_:)` (real angle and status), with a fallback to the display posture. It drives the CRT curvature and the 90° chime. |
| Appearance | The window forces the dark style so the title and glass bars read on the dark console |
| Status bar | Visible, and part of the safe area. Each console half respects its own edge insets. |

**Decided on 2026-09-29 (Phase 1 design), following the HIG sections quoted above:**
- **Screen toolbar item:** `Label("Screen", systemImage: "tv")` joins Skins and Store in the same `ToolbarItemGroup` (icon + title, grouped, no manual spacing). The screen overlay is reachable on both displays, like the others ("Create a consistent experience across displays").
- **Pause menu inside the tube:** it changes the screen and the session, so it sits in the CRT ("Locate controls near the content they affect") and works the same in every pose.
- **Neon shell edge:** drawn with `ConcentricRectangle()` so it follows the display's corners (§6).
- **Cover attract mode:** a full-bleed, faded background behind inset content ("letting a background image or header span the full width while scrollable content stays inset"), faded toward the vertical toolbar column so its items keep their contrast.
- **Hinge:** still visuals only. The cover's "unfold to play" prompt was kept rather than animating it with the hinge, because the outer display goes dark as the device opens.

**Decided on 2026-09-29 (Phase 2):**
- **Lunar Hinge uses the hinge as input.** §8: "Hinge data is observed live, and is ideal for driving interactions or effects." Thrust grows as the device folds up to 30° past the most-open angle of the attempt, so it works from any starting pose; the smoothed `HingeEngine.hingeAngle` is used. §2 / HIG: "You don't want to tie functionality to a specific pose", so ▲ and A always thrust too. The hinge is still never used for layout.

**Decided on 2026-09-29 (Phase 4, Duo polish):**
- **Toolbar groups and priorities.** HIG: "Group related toolbar items instead of spacing them manually" and "Assign each item a visibility priority… starting with whole groups". Two `ToolbarItemGroup`s: Skins and Screen with `.visibilityPriority(.high)`, then Store and Records. Items overflow from bottom to top, so Records, the least used, goes first.
- **Occlusion.** HIG: "For custom components, ReservedRegion… provide[s] a way to reposition content away from reserved regions"; "when the camera activates, the UI moves aside". `avoidingOcclusion()` pads the console halves and overlay panels in from the nearest edge by the reach of active `.occlusion` regions (`OcclusionInsets`). The cover needs nothing extra: its content stays in the safe area, and "When controls are on the side, the system automatically accounts for" the outer camera.
- **`ArrangementView` evaluated, not adopted for the console.** Apple recommends it ("Consider an arrangement view when your layout already resembles one"), and the console is a split. But a split arrangement picks its axis and ratio itself and doesn't expose where it splits. The console needs the split exactly on the fold (verified 2026-09-23), with the shell continuous behind both halves and the hinge groove drawn on the split line. `FoldSplit` gets that from the same `.division` reserved region Apple offers custom layouts. The HIG phrasing is "prefer", so the custom layout stays. Revisit if `ArrangementView` gains a way to read or pin its split.

**Decided on 2026-09-29 (Phase 5, music, accessibility, languages):**
- **VoiceOver play.** The console's controls carry `.allowsDirectInteraction`, so a VoiceOver user can play in real time by touch, as with any game. Every control also works with a double tap, and the D-Pad has named actions, so nothing depends on direct touch.
- **Reduce Transparency.** Backgrounds become more opaque, as with the system's own bars (§5). Translucent shells and cartridges are drawn solid, overlay backdrops go nearly opaque, and the faded attract mode stays off.
- **Localization.** English only since 2026-10-14. The overlay pixel font (Silkscreen) lacks Turkish letters, so the earlier Turkish translation was removed. Casing follows English rules (`uppercased()`). Strings still go through a String Catalog, and labels scale down with `minimumScaleFactor`, so a language can return with a font that covers it.

**Decided on 2026-09-29 (Phase 6, designer, cartridges, text size):**
- **Labels toolbar item.** The designer is customization, so Labels joins Skins and Screen in the high-priority group ("Group related toolbar items"); Store and Records still overflow first. Like the other overlays, it's reachable on both displays. The grid is smaller on the cover (15 pt pixels) than inside (22 pt), and a stroke is saved when the finger lifts.
- **VoiceOver drawing.** The grid takes direct touches (`.allowsDirectInteraction`), as the console controls do; swatches are named by the role of their color.
- **Dynamic Type and Bold Text.** Overlay and library text follows the body style's size steps and gets heavier with Bold Text; at accessibility sizes one-line text wraps instead of shrinking. The console's printed text is part of the hardware and scales with the console, not the text size.

**Decided on 2026-09-29 (Phase 7, intro):**
- **An in-hierarchy intro, not a sheet,** like the other overlays: it opens on whichever display the app starts on and keeps the retro look. It's short (five pages), can be closed at any point, and can be replayed from Records.
- **Unfolding waits for the intro.** It explains unfolding, so a cartridge going in mid-read would cut it off. While it shows, unfolding only moves it to the inner display. Its last button inserts the selected cartridge.

**Verified by the user in Device Hub (2026-09-23):**
- Closed with the hinge on top, the outer display comes up in landscape.
- Opened like a laptop, the CRT is above and the controls are below, with the split on the fold.
- Opened like a book, the CRT and the controls sit side by side.
- While partially folding, the CRT curvature follows the real hinge angle, and the chime plays at 90°.

Hardware checks still pending: all of the above on a real iPhone Duo once available.
