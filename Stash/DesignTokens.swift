import SwiftUI
import AppKit

enum DesignTokens {
    enum Icon {
        // Background fill states
        static let backgroundRest   = Color.white.opacity(0.06)
        static let backgroundHover  = Color.white.opacity(0.10)

        // Icon tint states
        static let tintRecording    = Color(red: 0.863, green: 0.149, blue: 0.149) // #DC2626
        static let tintPlusButton   = Color.white.opacity(0.45)
        static let tintMuted        = Color.white.opacity(0.72)

        // Active background (mic while recording)
        static let backgroundActive = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    }

    /// Active-state colors for the notes filter bar pill (icon + "F" letter).
    /// Bluish-white at bumped opacity reads "cool/glacial" without going full
    /// cyan — chromaticity collapses below ~0.25 opacity for near-white colors,
    /// so the opacities here are above that floor. If rendering still reads as
    /// neutral gray on dark glass, swap `activeBackground` to a more saturated
    /// cyan as a one-line follow-up.
    enum FilterPill {
        static let activeBackground = Color(red: 0.92, green: 0.95, blue: 1.0).opacity(0.28)
        static let activeBorder     = Color(red: 0.85, green: 0.92, blue: 1.0).opacity(0.42)
        static let activeForeground = Color(red: 0.88, green: 0.94, blue: 1.0)
    }

    enum Spacing {
        static let panel: CGFloat = 20        // outer panel padding
        static let sectionGap: CGFloat = 20   // gap between sections
        static let itemGap: CGFloat = 4       // gap between list rows (where non-flush lists are used)
        static let cardGap: CGFloat = 8       // gap between cards

    }

    /// Geometry shared by every `StashListRow` caller — clipboard, notes, pinned.
    enum Row {
        static let height: CGFloat = 34
        static let horizontalPadding: CGFloat = 8
        static let spacing: CGFloat = 8
        static let cornerRadius: CGFloat = 8
    }

    /// Floating transcription pill (redesign 2026-04-21). Fixed dimensions so Recording,
    /// Processing and Copied states share identical width/height per Figma node 280-981.
    enum Pill {
        // Layout (LTR), notch displays:
        //   [flare][12 lead pad][label][4 inset][ NOTCH ][4 inset][meter][14 trail pad][flare]
        // Width is computed per mode by the controller's sizeForCurrentMode;
        // height is derived from the label's font metrics plus labelBottomGap.
        static let height: CGFloat = 32
        static let iconGlyphSize: CGFloat = 14
        /// Load-bearing: the slab's height is derived from this font's metrics,
        /// so the SwiftUI label and the controller's NSFont measurement must
        /// use the same size.
        static let labelFontSize: CGFloat = 14
        // Asymmetric outer padding — more on the right.
        static let leadingPadding: CGFloat = 12
        static let trailingPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 4
        /// Gap between label and indicator on a display with no notch, where
        /// there is no notch span to reserve.
        static let compactContentGap: CGFloat = 11

        // MARK: Notch-anchored presentation (Dynamic-Island style)
        //
        // The pill hangs flush from the display's physical top edge and is
        // only as tall as the notch, so its content sits AT menu-bar level.
        // The notch (~185pt on a 14" MBP) is far wider than the pill's
        // content, so the label and the mode indicator are pushed to
        // opposite ends and the notch span is left clear between them —
        // otherwise content centered on the notch would be hidden behind it.
        static let notchBottomCornerRadius: CGFloat = 20

        /// Concave flare at the two TOP corners. The slab's top edge runs the
        /// full panel width and the body pulls in by this much just below it,
        /// joined by a curve that bows inward — so the slab appears to splay
        /// outward where it meets the screen edge instead of ending square.
        static let notchTopFlareRadius: CGFloat = 9

        // Clear space either side of the notch, between it and the content
        // sitting in the menu-bar strips left and right of it.
        static let notchContentInset: CGFloat = 4

        /// Gap between the BOTTOM of the label's line box and the slab's
        /// bottom edge. The slab's height is derived from this plus the
        /// measured label metrics, rather than the other way round, so the
        /// gap stays exact if the label font ever changes.
        static let labelBottomGap: CGFloat = 8

        // Entrance / exit motion.
        //
        // Short travel: the slab lifts only a few points out of the notch
        // rather than dropping in from well above it. Curves are plain
        // decelerating eases — an earlier entrance used a control point above
        // 1, which overshoots early in the timing curve and read as a stutter
        // rather than as a spring.
        static let entranceSlideOffset: CGFloat = 5
        static let entranceDuration: CFTimeInterval = 0.30
        static let entranceCurveCP1x: Double = 0.22
        static let entranceCurveCP1y: Double = 1.0
        static let entranceCurveCP2x: Double = 0.36
        static let entranceCurveCP2y: Double = 1.0

        static let exitSlideOffset: CGFloat = 4
        static let exitDuration: CFTimeInterval = 0.20
        static let exitCurveCP1x: Double = 0.40
        static let exitCurveCP1y: Double = 0.0
        static let exitCurveCP2x: Double = 0.70
        static let exitCurveCP2y: Double = 1.0

        // MARK: Recording glow
        //
        // A soft, heavily-blurred warm glow along the BOTTOM edge of the
        // slab while recording. Deliberately NOT a full border stroke (a
        // crisp outline read as harsh) and NOT a sliding highlight (lateral
        // motion read as busy) — it sits in place and breathes vertically.
        //
        // The breathe is a slow sine on wall-clock time. The live audio
        // level modulates opacity on top of it, which reacts smoothly.
        // `glowLevelSmoothing` bridges the level meter's 10 Hz ticks so the
        // glow breathes rather than stepping.
        static let glowBandHeight: CGFloat = 18
        static let glowBlurRadius: CGFloat = 10
        /// Seconds for one full breathe (dim → bright → dim).
        static let glowPulsePeriod: TimeInterval = 2.6
        /// Band height at the dimmest point of the breathe, as a fraction of
        /// `glowBandHeight`. Keeps the glow present rather than blinking out.
        static let glowPulseMinScale: CGFloat = 0.62
        static let glowBaseOpacity: Double = 0.65
        static let glowLevelOpacityBoost: Double = 0.40
        static let glowLevelSmoothing: TimeInterval = 0.12
        // The glow carries STATE, not just decoration — it is readable from
        // the corner of the eye before the label is. Each ramp runs saturated
        // → pale across a segment's own width, with two interpolated stops so
        // the bloom reads as a gradient rather than two flat ends, and all
        // three land at the same visual weight through the same blur and mask.

        /// Listening — the original "Sexy Blue" ramp, #007BFF → #B0E0E6.
        static let glowColorsListening: [Color] = [
            Color(red: 0.000, green: 0.482, blue: 1.000),  // #007BFF
            Color(red: 0.231, green: 0.584, blue: 0.980),  // #3B95FA
            Color(red: 0.463, green: 0.686, blue: 0.957),  // #76AFF4
            Color(red: 0.690, green: 0.878, blue: 0.902)   // #B0E0E6
        ]

        /// Processing — neutral greyscale, #6E6E73 → #F2F2F7. Deliberately
        /// colourless: the work is indeterminate, so the pill should read as
        /// "busy" without implying an outcome.
        static let glowColorsProcessing: [Color] = [
            Color(red: 0.431, green: 0.431, blue: 0.451),  // #6E6E73
            Color(red: 0.596, green: 0.596, blue: 0.616),  // #98989D
            Color(red: 0.780, green: 0.780, blue: 0.800),  // #C7C7CC
            Color(red: 0.949, green: 0.949, blue: 0.969)   // #F2F2F7
        ]

        /// Failure — #FF3B30 → #FFC4C0, mirroring the blue ramp's structure so
        /// the swap reads as a colour change rather than a brightness one.
        static let glowColorsFailure: [Color] = [
            Color(red: 1.000, green: 0.231, blue: 0.188),  // #FF3B30
            Color(red: 1.000, green: 0.384, blue: 0.349),  // #FF6259
            Color(red: 1.000, green: 0.541, blue: 0.522),  // #FF8A85
            Color(red: 1.000, green: 0.769, blue: 0.753)   // #FFC4C0
        ]

        // MARK: Recording level meter (right of the notch)
        static let levelMeterBarCount: Int = 4
        static let levelMeterBarWidth: CGFloat = 2.5
        static let levelMeterBarSpacing: CGFloat = 2.5
        static let levelMeterMinBarHeight: CGFloat = 3
        static let levelMeterMaxBarHeight: CGFloat = 14

        // Panel-frame animation — cubic-bezier(0.22, 1, 0.36, 1) over 400ms.
        // Used by the drag-to-snap reposition. Tuned to read as a deliberate
        // settle into the snap corner rather than a hard snap.
        static let frameAnimationDuration: TimeInterval = 0.40
        static let frameAnimationCurveCP1x: Double = 0.22
        static let frameAnimationCurveCP1y: Double = 1.0
        static let frameAnimationCurveCP2x: Double = 0.36
        static let frameAnimationCurveCP2y: Double = 1.0

        // Phase-change animation — recording → processing (shrink to circle)
        // and back (expand). 0.27s easeInEaseOut. The pill content uses an
        // asymmetric transition so the capsule's geometry (rounded corners)
        // morphs first, then content fades in — see contentInsertionDelay /
        // contentInsertionDuration below.
        static let phaseAnimationDuration: TimeInterval = 0.27

        // Asymmetric content-swap transition timings. When mode changes,
        // the OLD content fades out fast (`contentRemovalDuration`) so the
        // capsule reads as "empty" while the AppKit panel resizes, then
        // the NEW content fades in (`contentInsertionDuration`) after a
        // small delay (`contentInsertionDelay`) so the rounded corners
        // reach their target shape before text appears.
        // Label swaps (Listening… → Processing) cross-fade with a slight
        // blur + scale, both directions running together over the same
        // duration. Symmetric on purpose: the earlier fade-out-then-pause-
        // then-fade-in left frames with nothing on screen, which read as the
        // pill blacking out mid-transition.
        static let contentTransitionDuration: TimeInterval = 0.26
        static let contentTransitionBlur: CGFloat = 4
        static let contentTransitionScale: CGFloat = 0.92

        // Completion hold durations — how long the pill displays a completion
        // message before hiding (or returning to recording for mid-recording
        // warnings). `completionDefaultHold` matches the historical 1.6s
        // behaviour for end-of-recording results ("Pasted ✓", "No audio",
        // "Failed"). `completionWarningHold` is the longer hold used for
        // mid-recording warnings (85-min, 20-MB) so the user has time to
        // read them while the recording continues.
        static let completionDefaultHold: TimeInterval = 1.6
        static let completionWarningHold: TimeInterval = 3.5
    }

    enum Typography {
        // Primary list item text (clipboard rows, pinned cards, notes rows).
        // SF Pro weight 510 from Figma maps to the closest SwiftUI weight: .medium.
        static let itemFont = Font.system(size: 11.6, weight: .medium)
        static let itemColor = Color(hex: "#A3A3A3")
        static let itemLineHeight: CGFloat = 15.467

        // Section headers (Pinned, Recent Files, Recent Notes, date groups).
        static let sectionFont = Font.system(size: 11, weight: .semibold)
        static let sectionColor = Color(hex: "#525252")

        // Tab bar labels (All / Clipboard / Notes / Files) and the notes
        // filter bar title/count — SF Pro 14 / regular (design spec).
        static let tabLabelFont = Font.system(size: 14, weight: .regular)

        // Note editor — body text and heading levels.
        // Body: 15 pt regular, 20 pt line height (≈ 1.33 multiple).
        static let bodyFont = Font.system(size: 15, weight: .regular)
        static let bodyLineHeight: CGFloat = 20

        static let h1Font = Font.system(size: 24, weight: .semibold)
        static let h2Font = Font.system(size: 20, weight: .semibold)
        static let h3Font = Font.system(size: 17, weight: .semibold)

        // AppKit equivalents (NSTextView needs NSFont, not SwiftUI Font).
        // Keep both in lockstep with the SwiftUI sizes above.
        static let bodyNSFont: NSFont = .systemFont(ofSize: 15, weight: .regular)
        static let h1NSFont: NSFont = .systemFont(ofSize: 24, weight: .semibold)
        static let h2NSFont: NSFont = .systemFont(ofSize: 20, weight: .semibold)
        static let h3NSFont: NSFont = .systemFont(ofSize: 17, weight: .semibold)
        static let inlineCodeNSFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    enum PanelAnimation {
        /// Open: fade 0 → 1 with a 10 pt downward settle. Ease-in-out, ~20%
        /// faster than the earlier 0.32s — the prior duration felt sluggish
        /// per test feedback.
        static let openDuration: CFTimeInterval = 0.26
        /// Close: fade 1 → 0 with an 8 pt upward lift. Ease-in-out, slightly
        /// faster than open so dismissal reads as quick.
        static let closeDuration: CFTimeInterval = 0.21
        /// Panel starts 10 pt above its final y on open.
        static let openSlideOffset: CGFloat = 10
        /// Panel ends 8 pt above its start y on close.
        static let closeSlideOffset: CGFloat = 8
    }

    enum FileShelf {
        // Finder-style selection visual. Colors come from system NSColor at
        // render time so the user's accent setting + light/dark appearance
        // are honored automatically.
        static let iconBackdropInset: CGFloat = 4
        static let iconBackdropCornerRadius: CGFloat = 6
        static let labelBackdropCornerRadius: CGFloat = 4
        static let labelBackdropPaddingH: CGFloat = 4
        static let labelBackdropPaddingV: CGFloat = 2

        // Vertical gap between the 48×48 thumbnail and the filename label.
        // Sized so the selection-state accent fill behind the filename has
        // visible breathing room above it instead of kissing the thumbnail
        // bottom edge (the fill extends `labelBackdropPaddingV` above the
        // text baseline, so this gap should comfortably exceed that).
        static let mediaToFilenameGap: CGFloat = 10
    }
}

// MARK: - Color(hex:) helper

extension Color {
    /// Initialises a Color from a hex string like "#A3A3A3" or "A3A3A3".
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double( v        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
