import AppKit
import Combine
import SwiftUI

// MARK: - Pill mode

enum PillMode: Hashable {
    case recording
    case processing
    case completion(message: String)
}

private extension NSScreen {
    /// Stable per-display identifier, used to key cached notch geometry.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

// MARK: - Notch slab shape

/// Flat top edge (flush with the screen edge the pill emerges from) and
/// rounded bottom corners.
///
/// `UnevenRoundedRectangle(topLeadingRadius: 0, topTrailingRadius: 0, ...)`
/// expresses this directly but is macOS 14+; this project deploys to
/// macOS 13, so the path is built by hand instead of gating the whole pill
/// behind an availability check.
/// `InsettableShape` as well as `Shape` so the recording border can use
/// `.strokeBorder`, which draws the stroke entirely INSIDE the bounds. A
/// plain `.stroke` centers on the path, which would put half the line
/// outside the panel — clipped away at the sides and off-screen at the
/// flush top edge.
struct NotchPillShape: Shape, InsettableShape {
    var bottomRadius: CGFloat
    /// Concave flare at the two top corners. 0 gives square top corners.
    var topFlareRadius: CGFloat = 0
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }

        // Flare pulls the body in from each side, so it can never eat more
        // than half the width; the bottom radius is then clamped against
        // whatever body width is left.
        let flare = max(0, min(topFlareRadius, min(rect.width / 2, rect.height)))
        let bodyLeft = rect.minX + flare
        let bodyRight = rect.maxX - flare
        let corner = max(0, min(bottomRadius, min((bodyRight - bodyLeft) / 2, rect.height - flare)))

        var path = Path()
        // Top edge spans the FULL width — flush with the screen edge.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right concave flare. The control point sits at the body's own
        // top-right, which bows the curve inward and carves the corner out
        // rather than rounding it off.
        path.addQuadCurve(
            to: CGPoint(x: bodyRight, y: rect.minY + flare),
            control: CGPoint(x: bodyRight, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - corner))
        path.addArc(
            center: CGPoint(x: bodyRight - corner, y: rect.maxY - corner),
            radius: corner,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bodyLeft + corner, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: bodyLeft + corner, y: rect.maxY - corner),
            radius: corner,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bodyLeft, y: rect.minY + flare))
        // Top-left concave flare, mirrored.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: bodyLeft, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - SwiftUI pill body (matches Figma node 280-981)

struct TranscriptionPillView: View {
    let mode: PillMode
    let onStop: () -> Void
    /// Live mic level, 0...1, published by TranscriptionService's level-meter
    /// timer. Drives the recording border's intensity. Ignored outside
    /// `.recording`.
    var audioLevel: Float = 0
    /// Width of the physical notch. The label and the trailing indicator are
    /// pushed to opposite ends of the slab with at least this much clear
    /// space between them, so content lands in the menu-bar strips either
    /// side of the notch rather than behind it. 0 on un-notched displays,
    /// where the layout collapses to an ordinary compact pill.
    var notchGapWidth: CGFloat = 0
    /// Distance from the slab's left edge to where the notch begins, in the
    /// slab's own coordinates. Lets the glow skip the span the notch covers.
    var notchLeadingOffset: CGFloat = 0

    var body: some View {
        // Label pinned left, mode indicator pinned right, notch-sized gap
        // between them. Content sits AT menu-bar level beside the notch —
        // never behind it. There is no icon disc: the indicator on the right
        // carries the mode.
        //
        // `.id(mode)` gives each phase its own identity so a
        // mode change is an insert+remove and `contentCrossFade` fires. The
        // key ignores the recording timer's associated value, so identity
        // stays stable second-to-second while recording.
        HStack(spacing: 0) {
            label
            Spacer(minLength: notchGapWidth)
            trailing
        }
        .padding(.leading, DesignTokens.Pill.leadingPadding)
        .padding(.trailing, DesignTokens.Pill.trailingPadding)
        // The flare pulls the body in from both sides; inset the content by
        // the same amount so it sits inside the body, not under the flare.
        .padding(.horizontal, DesignTokens.Pill.notchTopFlareRadius)
        .padding(.vertical, DesignTokens.Pill.verticalPadding)
        .transition(contentCrossFade)
        .id(mode)
        // The content row is exactly the notch's height and is pinned to the
        // TOP of the slab, so the label stays at menu-bar level, level with
        // the notch. Any extra slab height therefore lands entirely BELOW the
        // label as padding, instead of dragging the text down with it.
        .frame(height: DesignTokens.Pill.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black, in: pillShape)
        // Clip to the slab so content can't overflow the rounded corners
        // while the AppKit panel is mid-resize.
        .clipShape(pillShape)
        .overlay(edgeGlow)
        .animation(.easeInOut(duration: DesignTokens.Pill.contentTransitionDuration),
                   value: mode)
    }

    /// Outgoing and incoming content run the SAME modifier in opposite
    /// directions over the same duration, so they cross-fade through each
    /// other — opacity, a slight blur, and a slight scale together. There is
    /// never a frame with nothing on screen.
    private var contentCrossFade: AnyTransition {
        .modifier(
            active: PillContentPhase(hidden: true),
            identity: PillContentPhase(hidden: false)
        )
    }

    /// The slab outline: flat top (flush with the screen edge) + rounded
    /// bottom corners. Shared by the background fill and the clip so they
    /// can never disagree mid-resize.
    private var pillShape: NotchPillShape {
        NotchPillShape(
            bottomRadius: DesignTokens.Pill.notchBottomCornerRadius,
            topFlareRadius: DesignTokens.Pill.notchTopFlareRadius
        )
    }

    // MARK: Edge glow
    //
    // A soft, multi-coloured bloom hugging the BOTTOM edge only — the
    // BorderBeam look adapted to a slab whose top edge is flush with the
    // screen and therefore has no visible border.
    //
    // Shown in EVERY mode, not just recording. The glow is the pill's
    // identity, so gating it on `.recording` made the slab look like a
    // different object once the spinner appeared. Outside recording
    // `audioLevel` is 0, so the level-driven opacity term falls away and the
    // glow sits steady at `glowBaseOpacity` while still breathing. It stays
    // put and breathes vertically; an earlier version slid a highlight
    // left-to-right, which read as busy and distracting.
    // `TimelineView(.animation)` re-evaluates every display frame so the
    // breathe is driven by wall-clock time and stays smooth regardless of
    // how often the audio level or the pill's mode updates.

    private var edgeGlow: some View {
            TimelineView(.animation) { timeline in
                // Slow sine, 0...1. Constant period rather than audio-driven:
                // phase is derived from absolute time, so varying the period
                // would retroactively rewrite it and the glow would jump.
                // Level drives opacity below instead.
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let radians = elapsed * 2 * .pi / DesignTokens.Pill.glowPulsePeriod
                let breathe = CGFloat((sin(radians) + 1) / 2)
                let scale = DesignTokens.Pill.glowPulseMinScale
                    + (1 - DesignTokens.Pill.glowPulseMinScale) * breathe

                // The notch physically blanks the middle of the slab, so a
                // single full-width band reads as a gradient chopped in half.
                // Instead the glow is drawn as two independent segments in
                // the strips either side of the notch, with the notch span
                // left empty. Each segment carries the WHOLE palette across
                // its own width, so both edges show a colour mix rather than
                // each sampling one slice of a shared ramp.
                if notchGapWidth > 0 {
                    HStack(spacing: 0) {
                        glowSegment(scale: scale, anchor: .leading)
                            .frame(width: max(0, notchLeadingOffset))
                        Color.clear
                            .frame(width: notchGapWidth)
                        glowSegment(scale: scale, anchor: .trailing)
                    }
                } else {
                    glowSegment(scale: scale, anchor: nil)
                }
            }
            .clipShape(pillShape)
            // Louder input → brighter glow. Applied outside the TimelineView
            // so the implicit animation can smooth the level meter's 10 Hz
            // steps into continuous movement.
            .opacity(
                DesignTokens.Pill.glowBaseOpacity
                    + Double(normalizedAudioLevel) * DesignTokens.Pill.glowLevelOpacityBoost
            )
            .animation(.easeOut(duration: DesignTokens.Pill.glowLevelSmoothing), value: audioLevel)
            // Purely decorative — must never intercept the stop tap.
            .allowsHitTesting(false)
    }

    /// Palette for the current mode: blue while listening, neutral grey while
    /// processing, red on a failed result. The glow is the fastest-read part
    /// of the pill — colour lands before the label does, especially at the
    /// edge of vision where the notch sits.
    ///
    /// Non-failure completions stay on the listening blue. That covers the
    /// mid-recording warnings ("5 min left", "Almost full"), which flash and
    /// then return to recording — turning those red would read as an error
    /// when nothing has gone wrong.
    private var glowColors: [Color] {
        switch mode {
        case .recording:
            return DesignTokens.Pill.glowColorsListening
        case .processing:
            return DesignTokens.Pill.glowColorsProcessing
        case .completion(let message):
            return Self.isFailureMessage(message)
                ? DesignTokens.Pill.glowColorsFailure
                : DesignTokens.Pill.glowColorsListening
        }
    }

    /// Which completion messages represent a failed outcome. Mirrors the
    /// vocabulary `completionSymbol(for:)` switches on — both must be updated
    /// together when a new message is added.
    static func isFailureMessage(_ message: String) -> Bool {
        switch message {
        case "Failed", "No audio": return true
        default:                   return false
        }
    }

    /// One bloom segment: the full violet → magenta → blue → teal ramp across
    /// its own width, strongest at the bottom edge and fading upward, with
    /// both ends softened so it doesn't butt hard against the notch or the
    /// rounded corners.
    private func glowSegment(scale: CGFloat, anchor: HorizontalEdge?) -> some View {
        LinearGradient(
            colors: glowColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: DesignTokens.Pill.glowBandHeight * scale)
        .mask(
            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Weighted toward the slab's OUTER corner rather than centred in the
        // strip: brightest at the far edge, falling away toward the notch, so
        // the light gathers around the rounded corners.
        .mask(
            LinearGradient(
                gradient: Gradient(stops: outerEdgeStops(for: anchor)),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .blur(radius: DesignTokens.Pill.glowBlurRadius)
    }

    /// Mask stops that bias a segment's brightness toward the outer corner.
    private func outerEdgeStops(for anchor: HorizontalEdge?) -> [Gradient.Stop] {
        switch anchor {
        case .leading:   // left strip — bright at its left edge
            return [
                .init(color: .white, location: 0.0),
                .init(color: .white, location: 0.30),
                .init(color: .clear, location: 1.0)
            ]
        case .trailing:  // right strip — bright at its right edge
            return [
                .init(color: .clear, location: 0.0),
                .init(color: .white, location: 0.70),
                .init(color: .white, location: 1.0)
            ]
        case .none:      // un-notched fallback: soften both ends
            return [
                .init(color: .clear, location: 0.0),
                .init(color: .white, location: 0.25),
                .init(color: .white, location: 0.75),
                .init(color: .clear, location: 1.0)
            ]
        }
    }

    /// `audioLevel` is already normalized 0...1 by TranscriptionService, but
    /// clamp defensively so a stray value can't push opacity out of range.
    private var normalizedAudioLevel: Float {
        min(max(audioLevel, 0), 1)
    }

    // MARK: Mode indicator (right of the notch)
    //
    // Replaces the old 24×24 icon disc. The circular disc read as heavy
    // against the notch, so the glyphs now sit bare in the right-hand
    // menu-bar strip.

    @ViewBuilder
    private var iconGlyph: some View {
        switch mode {
        case .recording:
            RecordingLevelMeter(level: normalizedAudioLevel)
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(DesignTokens.Icon.tintMuted)
        case .completion(let message):
            if isPastedCompletion(message) {
                Image("PastedConfirm")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: DesignTokens.Pill.iconGlyphSize,
                        height: DesignTokens.Pill.iconGlyphSize
                    )
                    // .foregroundColor (not .foregroundStyle) — the latter
                    // doesn't always propagate through .renderingMode(.template)
                    // for custom-asset Images on macOS 13/14, leaving the
                    // glyph at full opacity. .foregroundColor + .tint together
                    // covers both old and new SwiftUI tint paths.
                    .foregroundColor(DesignTokens.Icon.tintMuted)
                    .tint(DesignTokens.Icon.tintMuted)
            } else {
                glyph(completionSymbol(for: message))
            }
        }
    }

    /// True iff the message represents a paste-success state. Paste states use
    /// a custom asset (`PastedConfirm`) instead of an SF Symbol so the glyph
    /// matches the design language.
    private func isPastedCompletion(_ message: String) -> Bool {
        message == "Pasted ✓"
    }

    private func glyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: DesignTokens.Pill.iconGlyphSize, weight: .regular))
            .foregroundStyle(DesignTokens.Icon.tintMuted)
    }

    /// Mirrors the strings emitted by `TranscriptionService.showCompletion(_:)`.
    /// `"Pasted ✓"` uses the custom `PastedConfirm` asset (handled above).
    /// Non-verified paste outcomes do not show a pill at all (the dictation
    /// is recoverable in Notes → Recent dictations) so there's no "Saved"
    /// case here.
    private func completionSymbol(for message: String) -> String {
        switch message {
        case "Copied":      return "checkmark"
        case "Failed":      return "xmark"
        case "No audio":    return "mic.slash"
        default:            return "checkmark"
        }
    }

    // MARK: Label (SF Pro 14 regular #A3A3A3)

    @ViewBuilder
    private var label: some View {
        switch mode {
        case .recording:
            // Static word rather than the MM:SS timer. The elapsed seconds
            // still ride along on PillMode.recording for the controller's
            // sizing/phase logic; they're just no longer surfaced here.
            // Shimmer marks the in-progress states; completion messages are
            // results and stay static.
            pillLabel(Self.recordingLabelText).shimmer()
        case .processing:
            pillLabel(Self.processingLabelText).shimmer()
        case .completion(let message):
            pillLabel(message)
        }
    }

    /// Pill copy. Kept as constants so the controller's width measurement
    /// (`sizeForCurrentMode`) can size the slab against the exact same
    /// strings the view renders — they must not drift apart.
    static let recordingLabelText = "Listening…"
    static let processingLabelText = "Processing"

    // MARK: Trailing element

    /// `.fixedSize(horizontal:)` stops the HStack from compressing the label
    /// into an ellipsis.
    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.Pill.labelFontSize, weight: .regular))
            .foregroundStyle(DesignTokens.Typography.itemColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Trailing element

    @ViewBuilder
    private var trailing: some View {
        switch mode {
        case .recording:
            // The live level meter doubles as the stop control — the pill no
            // longer has room for a separate red dot beside it in the
            // right-hand strip. Tap target and accessibility are unchanged.
            indicatorSlot { iconGlyph }
                .contentShape(Rectangle())
                .onTapGesture { onStop() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stop recording")
                .accessibilityAddTraits(.isButton)
        case .processing, .completion:
            indicatorSlot { iconGlyph }
        }
    }

    /// Centres whichever indicator is current inside one fixed-width span.
    ///
    /// The controller sizes the panel against `indicatorReservedWidth`, so the
    /// rendered indicator has to occupy exactly that span too — otherwise the
    /// three indicators (17.5 / 16 / 14pt wide) would each sit at a different
    /// offset inside a slab whose width never changes, and the glyph would
    /// appear to hop sideways on every mode swap.
    private func indicatorSlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: TranscriptionPillView.indicatorReservedWidth)
    }

    /// Width reserved for the right-hand indicator in every mode: the widest
    /// of the level meter, the spinner, and the completion glyph.
    ///
    /// Defined here rather than on the controller because both need it and
    /// they must not disagree — the view lays out against it, the controller
    /// measures the panel with it.
    static let indicatorReservedWidth: CGFloat = {
        let barCount = CGFloat(DesignTokens.Pill.levelMeterBarCount)
        let meter = barCount * DesignTokens.Pill.levelMeterBarWidth
            + max(0, barCount - 1) * DesignTokens.Pill.levelMeterBarSpacing
        // `ProgressView` at `.small` control size renders ~16pt square.
        let spinner: CGFloat = 16
        return max(meter, max(spinner, DesignTokens.Pill.iconGlyphSize))
    }()
}

/// Drives the pill's content cross-fade: opacity + blur + scale, applied in
/// both directions so outgoing and incoming content overlap.
private struct PillContentPhase: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .blur(radius: hidden ? DesignTokens.Pill.contentTransitionBlur : 0)
            .scaleEffect(hidden ? DesignTokens.Pill.contentTransitionScale : 1)
    }
}

// MARK: - Recording level meter
//
// Compact bar meter driven by the live mic level. Bar weights are fixed so
// the shape reads as a meter rather than noise; the level scales them.

private struct RecordingLevelMeter: View {
    let level: Float

    /// Per-bar response weights — the middle bars react hardest, which is
    /// what makes the group read as a level meter rather than a bar chart.
    private static let weights: [CGFloat] = [0.55, 1.0, 0.8, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Pill.levelMeterBarSpacing) {
            ForEach(0..<DesignTokens.Pill.levelMeterBarCount, id: \.self) { index in
                Capsule()
                    .fill(DesignTokens.Icon.tintMuted)
                    .frame(
                        width: DesignTokens.Pill.levelMeterBarWidth,
                        height: barHeight(at: index)
                    )
            }
        }
        .frame(height: DesignTokens.Pill.levelMeterMaxBarHeight)
        // Smooths the level meter's 10 Hz ticks into continuous movement.
        .animation(.easeOut(duration: DesignTokens.Pill.glowLevelSmoothing), value: level)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let weight = Self.weights[index % Self.weights.count]
        let minH = DesignTokens.Pill.levelMeterMinBarHeight
        let maxH = DesignTokens.Pill.levelMeterMaxBarHeight
        return minH + (maxH - minH) * CGFloat(min(max(level, 0), 1)) * weight
    }
}

// MARK: - Floating panel
//
// Always-non-key. The pill is a passive status surface — no keyboard input,
// no focus stealing.

private final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }

    /// Builds a fully configured pill panel.
    ///
    /// `level` is assigned LAST on purpose: `isFloatingPanel = true` resets the
    /// window level to `.floating` (3) as a side effect, so assigning the level
    /// before it is silently discarded — which is exactly how the pill ended up
    /// below full-screen windows. Owning the whole configuration here means a
    /// caller cannot reintroduce that ordering.
    static func configured(contentRect: NSRect, level: NSWindow.Level) -> PillPanel {
        let panel = PillPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        // `.canJoinAllSpaces` puts the panel on every space, including
        // full-screen ones; `.stationary` stops it being dragged along by the
        // space-switch animation; `.fullScreenAuxiliary` lets it sit atop a
        // full-screen window; `.ignoresCycle` keeps it out of Cmd-`.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.level = level
        assert(panel.level == level, "window level was clobbered after assignment")
        return panel
    }

    /// AppKit constrains window frames so they don't cover the menu bar,
    /// which silently pushed the pill DOWN below it — the slab is exactly
    /// notch-height and lives entirely in the menu-bar strip, so the default
    /// constraint moved it out of the notch every time. Returning the
    /// requested rect untouched is what lets it sit flush at the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

// MARK: - Display state + root view

final class PillDisplayState: ObservableObject {
    @Published var mode: PillMode = .processing
    /// Mirror of TranscriptionService.audioLevel (0...1), republished here so
    /// the pill's recording glow can react to mic input.
    @Published var audioLevel: Float = 0
    /// Notch width for the current screen, so the pill can keep that span
    /// clear between its label and its mode indicator. 0 when un-notched.
    @Published var notchGapWidth: CGFloat = 0
    /// Offset from the slab's left edge to the notch — see the pill view.
    @Published var notchLeadingOffset: CGFloat = 0
}

struct PillRootView: View {
    @ObservedObject var state: PillDisplayState
    let onStop: () -> Void

    var body: some View {
        TranscriptionPillView(
            mode: state.mode,
            onStop: onStop,
            audioLevel: state.audioLevel,
            notchGapWidth: state.notchGapWidth,
            notchLeadingOffset: state.notchLeadingOffset
        )
    }
}

// MARK: - Controller

@MainActor
final class TranscriptionFloatingWidgetController: NSObject {

    private weak var transcription: TranscriptionService?
    private var panel: PillPanel?
    private let displayState = PillDisplayState()
    private var cancellables = Set<AnyCancellable>()
    private var panelOpenForWidget = false

    private enum Phase { case none, recording, processing, completion }
    private var phase: Phase = .none

    private var completionWorkItem: DispatchWorkItem?
    /// The completion message currently being held by `completionWorkItem`.
    /// Used to avoid re-scheduling the hide timer on every sync() tick while
    /// the same message stays in `ts.completionMessage` — important for
    /// mid-recording warnings where duration ticks would otherwise reset the
    /// hold indefinitely.
    private var heldCompletionMessage: String?

    /// Bumped on every show/hide animation start. The completion handler of
    /// each animation checks the token: a stale completion (e.g., hide's
    /// orderOut after a new show has started) is skipped.
    private var visibilityAnimationToken: UInt64 = 0
    /// True from the moment hidePanel commits its slide-out animation until
    /// either (a) the animation completes and orderOut runs, or (b) a new
    /// show supersedes it. Distinguishes "panel currently hiding" from
    /// "panel mid slide-in" — both have isVisible=true and possibly
    /// alpha < 1, but only the hiding case wants a re-entrance from a new
    /// show.
    private var hideInFlight = false

    /// Last frame handed to `applyPanelFrame`. `sync()` is driven by the audio
    /// level meter at 10 Hz, and now that the slab's size is constant while
    /// recording it would otherwise kick off a fresh frame animation to the
    /// SAME rect ten times a second — each one cancelling the last, including
    /// the entrance animation. Tracking the requested target lets repeats be
    /// dropped. Cleared on hide so the next show re-applies.
    private var lastRequestedFrame: NSRect?

    /// Re-orders the pill front when the active space changes.
    private var spaceChangeObserver: NSObjectProtocol?

    /// One-line dump of everything that decides whether the pill is actually
    /// visible on the current space. `isOnActiveSpace` is the key field: if
    /// it is false, the panel exists but is on a different space; if it's
    /// true and the pill still isn't visible, the problem is z-order or
    /// drawing, not spaces.
    func logPanelState(_ tag: String) {
        #if DEBUG
        guard let panel else { print("[Pill/\(tag)] no panel"); return }
        let screen = NSScreen.main
        print("""
        [Pill/\(tag)] frame=\(panel.frame) level=\(panel.level.rawValue) \
        visible=\(panel.isVisible) alpha=\(panel.alphaValue) \
        onActiveSpace=\(panel.isOnActiveSpace) \
        screenFrame=\(screen?.frame ?? .zero) safeTop=\(screen?.safeAreaInsets.top ?? -1)
        """)
        fflush(stdout)
        #endif
    }

    func attach(transcription: TranscriptionService) {
        // One-time cleanup of the snap-zone key persisted by prior builds
        // that tried to support drag-to-snap on the pill. The pill is now
        // fixed at top-center and nothing reads this key.
        UserDefaults.standard.removeObject(forKey: "TranscriptionPillSnapZone")

        self.transcription = transcription
        transcription.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)
        sync()
    }

    deinit {
        completionWorkItem?.cancel()
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    func setPanelOpenForWidget(_ open: Bool) {
        panelOpenForWidget = open
        sync()
    }

    private func sync() {
        guard let ts = transcription else { hidePanel(); return }

        // Republish the live mic level for the pill's recording border.
        // sync() is already driven by TranscriptionService.objectWillChange,
        // which the level-meter timer fires at 10 Hz, so this lands on every
        // tick. TranscriptionService zeroes audioLevel when recording stops.
        if displayState.audioLevel != ts.audioLevel {
            displayState.audioLevel = ts.audioLevel
        }

        // Keep the reserved notch span in step with the current screen, so
        // moving to/from an external display relays the pill correctly.
        let gap = currentNotchMetrics().notchWidth
        if displayState.notchGapWidth != gap {
            displayState.notchGapWidth = gap
        }

        if panelOpenForWidget {
            cancelAllPendingWork()
            hidePanel()
            phase = .none
            return
        }

        // Completion supersedes recording so mid-recording warnings (85-min,
        // 20-MB) can briefly flash on the pill, then return to recording mode
        // when their hold expires (see expireCompletion). End-of-recording
        // completions ("No audio", "Failed") work the same way,
        // they just see isRecording==false at expiry and hide instead.
        //
        // Ghost-flash guard: residual completion state at the start of a new
        // recording is cleared in TranscriptionService.startRecording
        // (completionMessage = nil), so this ordering does not introduce
        // a stale-completion flash when a new recording begins.
        if let msg = ts.completionMessage {
            let oldPhase = phase
            cancelAllPendingWork(except: .completion)
            phase = .completion
            updateHosted(mode: .completion(message: msg))
            applyPhaseFrame(animated: oldPhase != .none)
            showCollapsedPanelIfNeeded()

            // Only schedule the hide timer when entering completion for a NEW
            // message. Without this guard, every sync() tick (e.g., duration
            // ticking during a mid-recording warning) would re-arm the timer
            // and the completion would never expire.
            if heldCompletionMessage != msg {
                heldCompletionMessage = msg
                completionWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.expireCompletion()
                }
                completionWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
            }
            return
        }

        // Recording supersedes everything below. The takeover runs inside a
        // single Transaction with `disablesAnimations` so SwiftUI sees the
        // mode mutation as one atomic non-animated change — without the wrap,
        // a residual completion-state pill would cross-fade out as the
        // recording view fades in (the user-visible "ghost flash").
        // Subsequent mutations (recording → processing → completion) animate
        // normally.
        if ts.isRecording {
            let oldPhase = phase
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cancelAllPendingWork(except: .recording)
                phase = .recording
                heldCompletionMessage = nil
                // updateHosted FIRST so displayState.mode reflects the new
                // mode by the time applyPhaseFrame measures content for
                // dynamic sizing. applyPhaseFrame still runs before
                // showCollapsedPanelIfNeeded so the slide-in animation
                // captures the canonical phase target.
                updateHosted(mode: .recording)
                applyPhaseFrame(animated: oldPhase != .none)
                showCollapsedPanelIfNeeded()
            }
            return
        }

        if ts.isProcessing {
            let oldPhase = phase
            cancelAllPendingWork(except: .processing)
            phase = .processing
            heldCompletionMessage = nil
            updateHosted(mode: .processing)
            applyPhaseFrame(animated: oldPhase != .none)
            showCollapsedPanelIfNeeded()
            return
        }

        if phase != .completion {
            hidePanel()
            phase = .none
            heldCompletionMessage = nil
        }
    }

    /// Fires when the completion's hold timer expires. Returns the pill to
    /// the right downstream state:
    ///   - recording still active (mid-recording warning case) → recording
    ///   - processing still active (hard-stop completion before async work
    ///     finishes) → processing
    ///   - neither → hide
    /// Without this, the post-completion behaviour would always be "hide,"
    /// which is wrong for both warnings and hard-stop transitions.
    private func expireCompletion() {
        guard phase == .completion else { return }
        completionWorkItem = nil
        heldCompletionMessage = nil
        if let ts = transcription {
            if ts.isRecording {
                phase = .recording
                updateHosted(mode: .recording)
                applyPhaseFrame(animated: true)
                return
            }
            if ts.isProcessing {
                phase = .processing
                updateHosted(mode: .processing)
                applyPhaseFrame(animated: true)
                return
            }
        }
        hidePanel()
        phase = .none
    }

    /// Resize the panel frame to match the current `phase`. Animated when
    /// transitioning between visible phases (e.g., recording → processing),
    /// non-animated on first show (oldPhase == .none) so the panel doesn't
    /// briefly render at a stale size before snapping.
    ///
    /// Recording and processing are deliberately the same size, so in
    /// practice this only animates on the way into a completion message.
    private func applyPhaseFrame(animated: Bool) {
        let size = sizeForCurrentMode()
        applyPhaseAwareFrame(
            size: size,
            animated: animated,
            duration: DesignTokens.Pill.phaseAnimationDuration,
            timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
        )
    }

    /// Pill width is CONSTANT across every mode — sized once, with NSString
    /// font sizing, against the widest label the pill can show. Previously it
    /// was measured per message, which made the slab snap inward when a short
    /// result like "Failed" replaced "Processing".
    ///
    /// Reads `displayState.mode` (which `sync()` sets via `updateHosted`
    /// BEFORE calling applyPhaseFrame), so the size always reflects the
    /// content that's about to be displayed.
    private func sizeForCurrentMode() -> NSSize {
        // The slab is only as tall as the notch, so its content sits AT
        // menu-bar level in the strips either side of the notch. On an
        // un-notched display it falls back to the standard pill height.
        let metrics = currentNotchMetrics()
        // The label is centred inside a content row of `Pill.height` pinned to
        // the slab's top, so its baseline sits at menu-bar level. Height is
        // then derived so exactly `labelBottomGap` remains beneath the label's
        // line box — and never less than the notch band, which the slab must
        // still cover.
        let labelLineHeight = ceil(Self.completionLabelFont.ascender
            - Self.completionLabelFont.descender)
        let labelBottomFromTop = DesignTokens.Pill.height / 2 + labelLineHeight / 2
        let height = max(
            metrics.bandHeight,
            labelBottomFromTop + DesignTokens.Pill.labelBottomGap
        )

        // Width = label (left strip) + clear notch gap + indicator (right
        // strip) + the outer paddings. Long completion messages simply widen
        // the slab further out from the notch.
        // With no notch there is no gap to reserve, so fall back to the
        // ordinary inter-element spacing and the pill stays compact.
        // `leadingContentWidth` already includes one inset, so only the
        // trailing side's inset is added here.
        let gap = metrics.notchWidth > 0
            ? metrics.notchWidth + DesignTokens.Pill.notchContentInset
            : DesignTokens.Pill.compactContentGap
        let width = leadingContentWidth()
            + gap
            + currentIndicatorWidth()
            + DesignTokens.Pill.trailingPadding
            + Self.measurementSafetyMargin
            // Room for the concave flare on each side, so the body keeps the
            // width its content needs and the flares extend beyond it.
            + DesignTokens.Pill.notchTopFlareRadius * 2
        return NSSize(width: width, height: height)
    }

    /// Distance from the slab's left edge to where the notch begins:
    /// leading padding + the label + its clearance from the notch. The
    /// positioning code subtracts this from the notch's left edge so the
    /// label always lands fully inside the left menu-bar strip.
    private func leadingContentWidth() -> CGFloat {
        let labelW: CGFloat
        switch displayState.mode {
        // EVERY mode reserves the same label width, so the slab never resizes
        // or shifts for the whole recording → processing → completion
        // lifecycle: only the text cross-fades. Previously only recording and
        // processing shared a measurement while completion measured its own
        // message, which made the pill snap inward when a result landed.
        //
        // `max` with the live measurement is a clipping guard, not a resize
        // path: every production message is inside `steadyLabelWidth`, so it
        // never engages. Only a DEBUG-menu string long enough to overflow
        // widens the slab, which is the right trade for a debug seam.
        case .recording, .processing:
            labelW = Self.steadyLabelWidth
        case .completion(let msg):
            labelW = max(Self.steadyLabelWidth,
                         measureLabelWidth(msg, font: Self.completionLabelFont))
        }
        return DesignTokens.Pill.leadingPadding
            + labelW
            + DesignTokens.Pill.notchContentInset
    }

    /// Distance from the PANEL's left edge to where the notch begins. Used
    /// both to place the panel and to split the glow, which must agree — so
    /// they read the same value rather than each re-adding the flare.
    private func bodyLeadingOffset() -> CGFloat {
        leadingContentWidth() + DesignTokens.Pill.notchTopFlareRadius
    }

    /// Every label the pill can show in production. The slab reserves the
    /// width of the widest, in EVERY mode, so it never resizes mid-lifecycle.
    ///
    /// Kept beside the strings themselves rather than derived at the call
    /// sites: `showCompletion` takes a free-form `String`, so there is no
    /// compiler check tying these together. A new production message wider
    /// than the current widest must be added here, or the pill will resize
    /// for it — the `max` guard in `leadingContentWidth` keeps it from
    /// clipping in the meantime.
    private static let allPillLabelTexts: [String] = [
        TranscriptionPillView.recordingLabelText,   // "Listening…"
        TranscriptionPillView.processingLabelText,  // "Processing"
        "Pasted ✓",
        "Copied",
        "Failed",
        "No audio",
        "5 min left",
        "Almost full"
    ]

    /// Widest production label — see `allPillLabelTexts`. All inputs are
    /// compile-time constants and the font is static, so this is measured once
    /// rather than on every 10 Hz sync tick.
    private static let steadyLabelWidth: CGFloat =
        allPillLabelTexts
            .map { measure($0, font: completionLabelFont) }
            .max() ?? 0

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Rendered width of the right-hand mode indicator.
    private func currentIndicatorWidth() -> CGFloat {
        switch displayState.mode {
        // Same reasoning as `steadyLabelWidth`: the level meter, the spinner
        // and the completion glyph reserve identical space, so swapping
        // between them cannot nudge the slab. Reads the view's constant so
        // layout and measurement cannot drift.
        case .recording, .processing, .completion:
            return TranscriptionPillView.indicatorReservedWidth
        }
    }

    /// SwiftUI's Text rendering can disagree with NSString.size by a sub-pt
    /// fraction; a 2pt safety margin avoids the very-last character being
    /// clipped by the capsule's rounded right end.
    private static let measurementSafetyMargin: CGFloat = 2

    private static let completionLabelFont = NSFont.systemFont(ofSize: 14, weight: .regular)

    private func measureLabelWidth(_ text: String, font: NSFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }

    private func cancelAllPendingWork(except keep: Phase = .none) {
        if keep != .completion {
            completionWorkItem?.cancel()
            completionWorkItem = nil
        }
    }

    private func updateHosted(mode: PillMode) {
        if displayState.mode != mode { displayState.mode = mode }
        // Recomputed after the mode is set, since the offset depends on the
        // label width for that mode.
        let offset = bodyLeadingOffset()
        if displayState.notchLeadingOffset != offset {
            displayState.notchLeadingOffset = offset
        }
    }

    private func showCollapsedPanelIfNeeded() {
        if panel == nil { buildPanel() }
        guard let panel else { return }

        // Already showing AND not in the middle of a hide → just keep it on
        // top. CRITICAL: do NOT enter the slide+fade entrance here, even if
        // alpha is mid-animation. A phase transition (e.g., recording →
        // processing) has applyPhaseFrame committing an animator.setFrame
        // for the shrink JUST before us; if we then call panel.setFrame
        // directly (as part of slide+fade entrance), we cancel that
        // in-flight animator and the processing-shrink visibly breaks.
        // The earlier (alpha == 1) check was the bug — false during slide-in
        // tail, triggering exactly that cancellation.
        if panel.isVisible && !hideInFlight {
            panel.orderFrontRegardless()
            // A previous fade could have left alpha below 1; never leave the
            // panel on top but invisible.
            if panel.alphaValue < 1 { panel.alphaValue = 1 }
            return
        }

        // Either fully hidden, or mid-hide. Run slide+fade entrance from
        // `openSlideOffset` above the canonical target. `panel.frame` reflects
        // the just-set phase target because `sync()` calls `applyPhaseFrame`
        // immediately before this.
        visibilityAnimationToken &+= 1
        hideInFlight = false
        let token = visibilityAnimationToken

        let target = panel.frame
        let startFrame = target.offsetBy(dx: 0, dy: DesignTokens.Pill.entranceSlideOffset)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = DesignTokens.Pill.entranceDuration
            // Plain decelerating ease — fast out of the notch, settling
            // gently. See the token comments for why there is no overshoot.
            ctx.timingFunction = CAMediaTimingFunction(controlPoints:
                Float(DesignTokens.Pill.entranceCurveCP1x),
                Float(DesignTokens.Pill.entranceCurveCP1y),
                Float(DesignTokens.Pill.entranceCurveCP2x),
                Float(DesignTokens.Pill.entranceCurveCP2y)
            )
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            // Token guard: if a hide superseded this show, ignore.
            guard let self, self.visibilityAnimationToken == token else { return }
            // Pin the end state explicitly. If the fade is ever interrupted
            // or skipped, the panel would otherwise sit on top at alpha 0 —
            // present in the window list but invisible on screen.
            panel.alphaValue = 1
            panel.setFrame(target, display: true)
            self.logPanelState("shown")
        })
    }

    /// Notch geometry for the screen the pill is anchored to.
    ///
    /// All fields are 0 on displays without a notch, which collapses every
    /// consumer back to plain flush-top-center behaviour.
    private struct NotchMetrics {
        /// Height of the notch — the black band drawn above the content row.
        let bandHeight: CGFloat
        /// Horizontal center to align the slab on. Uses the notch's true
        /// center, which is not always exactly the screen's midX.
        let centerX: CGFloat
        /// Width of the notch itself — reserved as clear space between the
        /// label (left strip) and the mode indicator (right strip).
        let notchWidth: CGFloat
        /// Left edge of the notch, used to align the slab's reserved gap
        /// with the notch rather than centering the slab on it.
        let notchMinX: CGFloat
    }

    /// `safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are
    /// all macOS 12+, so they need no availability gate at our macOS 13
    /// deployment target. On a notched display the auxiliary areas are the
    /// menu-bar strips either side of the notch; the gap between them IS the
    /// notch. When either is nil (external monitor, non-notched Mac) we fall
    /// back to screen-center with no band.
    private func notchMetrics(for screen: NSScreen) -> NotchMetrics {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = right.minX - left.maxX
            if notchWidth > 0 {
                return NotchMetrics(
                    bandHeight: screen.safeAreaInsets.top,
                    centerX: (left.maxX + right.minX) / 2,
                    notchWidth: notchWidth,
                    notchMinX: left.maxX
                )
            }
        }
        return NotchMetrics(bandHeight: 0, centerX: screen.frame.midX, notchWidth: 0, notchMinX: 0)
    }

    /// Metrics for the pill's current anchor screen, or a no-notch default.
    ///
    /// Cached per display: the notch is physical hardware, so the numbers can
    /// only change when the screen layout does. `sync()` runs at the level
    /// meter's 10 Hz, and this otherwise re-queried NSScreen on every tick.
    private func currentNotchMetrics() -> NotchMetrics {
        guard let screen = NSScreen.main else {
            return NotchMetrics(bandHeight: 0, centerX: 0, notchWidth: 0, notchMinX: 0)
        }
        let id = screen.displayID
        if let cached = cachedNotchMetrics[id] { return cached }
        let metrics = notchMetrics(for: screen)
        cachedNotchMetrics[id] = metrics
        return metrics
    }

    private var cachedNotchMetrics: [CGDirectDisplayID: NotchMetrics] = [:]

    /// Position the panel flush against the display's physical top edge,
    /// centered on the notch, so it reads as emerging from it. The pill is
    /// not draggable; this is the only anchor it ever uses.
    ///
    /// Note this anchors to `screen.frame` (physical bounds), NOT
    /// `visibleFrame` (which starts below the menu bar) — that difference is
    /// what makes the slab touch the top edge rather than float under it.
    private func applyPhaseAwareFrame(
        size: CGSize,
        animated: Bool,
        duration: TimeInterval = DesignTokens.Pill.frameAnimationDuration,
        timingFunction: CAMediaTimingFunction? = nil
    ) {
        guard let screen = NSScreen.main else { return }

        let metrics = notchMetrics(for: screen)
        // Align the slab's reserved GAP with the notch, rather than centering
        // the slab on it. The label and the indicator have different widths,
        // so a centered slab would slide the wider one (the label) partly
        // under the notch. Un-notched displays just center.
        let unclampedX = metrics.notchWidth > 0
            // leadingContentWidth is measured to the BODY's left edge, and the
            // body now starts one flare-width in from the panel, so shift the
            // panel left by that much to keep the notch gap aligned.
            ? metrics.notchMinX - bodyLeadingOffset()
            : metrics.centerX - size.width / 2
        // Clamp so an unusually wide slab can't hang off a narrow display.
        let x = min(max(unclampedX, screen.frame.minX), screen.frame.maxX - size.width)
        let y = screen.frame.maxY - size.height
        let target = NSRect(x: x, y: y, width: size.width, height: size.height)
        applyPanelFrame(target, animated: animated, duration: duration, timingFunction: timingFunction)
    }

    /// Animate panel frame over the given duration. When `timingFunction`
    /// is nil, falls back to the cubic-bezier from DesignTokens (heavy
    /// ease-out, used by drag-snap settle).
    private func applyPanelFrame(
        _ frame: NSRect,
        animated: Bool,
        duration: TimeInterval = DesignTokens.Pill.frameAnimationDuration,
        timingFunction: CAMediaTimingFunction? = nil
    ) {
        guard let panel else { return }
        // Already heading here — leave the in-flight animation alone.
        if let last = lastRequestedFrame, last.equalTo(frame) { return }
        lastRequestedFrame = frame
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = timingFunction ?? CAMediaTimingFunction(controlPoints:
                    Float(DesignTokens.Pill.frameAnimationCurveCP1x),
                    Float(DesignTokens.Pill.frameAnimationCurveCP1y),
                    Float(DesignTokens.Pill.frameAnimationCurveCP2x),
                    Float(DesignTokens.Pill.frameAnimationCurveCP2y)
                )
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }

        // Slide+fade exit: lift the panel `closeSlideOffset` upward as it
        // fades to alpha=0, then orderOut. `hideInFlight` lets a subsequent
        // show distinguish "panel currently hiding" from "panel mid slide-in"
        // and re-run slide+fade entrance only for the former.
        visibilityAnimationToken &+= 1
        hideInFlight = true
        let token = visibilityAnimationToken

        // Next show must re-apply its frame rather than being treated as a
        // repeat of the target we're animating away from.
        lastRequestedFrame = nil
        let endFrame = panel.frame.offsetBy(dx: 0, dy: DesignTokens.Pill.exitSlideOffset)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = DesignTokens.Pill.exitDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints:
                Float(DesignTokens.Pill.exitCurveCP1x),
                Float(DesignTokens.Pill.exitCurveCP1y),
                Float(DesignTokens.Pill.exitCurveCP2x),
                Float(DesignTokens.Pill.exitCurveCP2y)
            )
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            // Token guard: if a show superseded this hide, don't orderOut —
            // the show animation is bringing the panel back.
            guard let self, self.visibilityAnimationToken == token else { return }
            panel?.orderOut(nil)
            self.hideInFlight = false
        })
    }

    private func buildPanel() {
        let initialSize = sizeForCurrentMode()
        let w = initialSize.width
        let h = initialSize.height
        // Shielding level is the highest level AppKit exposes — above the
        // menu bar, above full-screen windows, above Mission Control. The
        // pill is a transient status surface that must never be occluded.
        // Trade-off: it also draws over context menus and Mission Control.
        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        let p = PillPanel.configured(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            level: level
        )

        // Re-assert front when the active space changes. `.canJoinAllSpaces`
        // is normally enough on its own, but if anything does reorder the
        // panel during a switch into (or out of) a full-screen space, this
        // puts it back on top without waiting for the next sync().
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                panel.orderFrontRegardless()
                self.logPanelState("spaceChange")
            }
        }

        let root = PillRootView(
            state: displayState,
            onStop: { [weak self] in self?.transcription?.stopRecording() }
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        host.autoresizingMask = [.width, .height]

        p.contentView = host
        panel = p

        restorePosition()
    }

    /// Position the pill at its fixed notch anchor. The pill is not
    /// draggable; there's no per-user position to restore. Uses the
    /// mode-derived size rather than the static fallback so the very first
    /// placement already accounts for the notch band and minimum slab width.
    private func restorePosition() {
        applyPhaseAwareFrame(size: sizeForCurrentMode(), animated: false)
    }
}
