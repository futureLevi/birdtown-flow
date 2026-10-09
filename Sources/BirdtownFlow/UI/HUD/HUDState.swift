import AppKit
import SwiftUI

/// Which part of the HUD the pointer is over. Tracked by `HUDController` (the panel is never
/// key, so SwiftUI hover tracking can't be relied on) and fed back in as plain state.
enum HUDHover: Sendable, Equatable {
    case pill
    case stop
    case cancel
}

/// Everything the HUD draws, as a plain value. The live panel builds one from
/// `DictationController`; snapshots build them by hand, so every state can be reviewed.
struct HUDState: Equatable, Sendable {
    /// Mirrors `DictationController.Phase`, decoupled so previews need no controller.
    enum Phase: Equatable, Sendable {
        case idle
        case listening
        case transcribing
        case polishing
        case done
        case cancelled
        case failed(String)
    }

    /// The visual state: what shape the pill takes.
    enum Kind: Equatable, Sendable {
        case hidden
        case idle
        case hint
        case listening
        case handsFree
        case transcribing
        case polishing
        case done
        case cancelled
        case failed
    }

    var phase: Phase
    var showsIdlePill = true
    var isHandsFree = false
    var level: Float = 0
    /// Recent levels, oldest first.
    var levels: [Float] = []
    var recordingStartedAt: Date?
    var hover: HUDHover?
    /// The push-to-talk key, as the user sees it ("fn", "Right ⌥").
    var keyName = "fn"
    var appName: String?
    /// Why a finished dictation went to the clipboard ("Copied · press ⌘V to paste").
    /// Shown beside the check; `nil` when the text was typed.
    var notice: String?
    /// What clicking a failure or a notice does ("Show in History"). `nil` when the message
    /// has no next step; otherwise the pill takes clicks and shows a trailing chevron.
    var actionLabel: String?

    var kind: Kind {
        switch phase {
        case .idle:
            if !showsIdlePill { return .hidden }
            return hover == nil ? .idle : .hint
        case .listening: return isHandsFree ? .handsFree : .listening
        case .transcribing: return .transcribing
        case .polishing: return .polishing
        case .done: return .done
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    var isLive: Bool {
        switch kind {
        case .listening, .handsFree, .transcribing, .polishing: true
        default: false
        }
    }

    /// States that accept the pointer: the idle pill (hover hint, click to start), the
    /// hands-free controls, and a message with a next step. Everything else lets clicks fall
    /// through to the app below.
    var isInteractive: Bool {
        switch kind {
        case .idle, .hint, .handsFree: true
        case .done, .failed: hasAction
        default: false
        }
    }

    /// A message pill (a failure, or a notice beside the check) that links somewhere.
    var hasAction: Bool {
        guard actionLabel != nil else { return false }
        switch kind {
        case .failed: return true
        case .done: return notice != nil
        default: return false
        }
    }

    var accessibilityDescription: String {
        switch kind {
        case .hidden, .idle, .hint: return "Birdtown Flow is ready. Hold \(keyName) to dictate."
        case .listening, .handsFree:
            if let appName { return "Listening. Dictating into \(appName)." }
            return "Listening"
        case .transcribing: return "Transcribing"
        case .polishing: return "Polishing"
        case .done: return notice ?? "Inserted"
        case .cancelled: return "Cancelled"
        case .failed: return failureMessage ?? "Something went wrong"
        }
    }
}

/// Pill geometry, shared by the SwiftUI view (layout) and the panel (hit-testing), so the
/// clickable regions always match what's drawn.
@MainActor
enum HUDMetrics {
    static var barsWidth: CGFloat {
        let count = CGFloat(Layout.HUD.barCount)
        return count * Layout.HUD.barWidth + (count - 1) * Layout.HUD.barSpacing
    }

    /// Centre of the pill's left end cap: glyphs sit here so they're concentric with the curve.
    static var capCentre: CGFloat { Layout.HUD.height / 2 }

    static let hintLead = "Click or hold"
    static let hintTrail = "to dictate"

    static func pillSize(for state: HUDState) -> CGSize {
        let height = Layout.HUD.height
        switch state.kind {
        case .hidden, .idle:
            return Layout.HUD.idleSize
        case .hint:
            return CGSize(width: hintWidth(keyName: state.keyName), height: Layout.HUD.hintHeight)
        case .listening, .transcribing, .polishing:
            // One width for the whole utterance: releasing the key changes what the bars do,
            // not the size of the thing on screen.
            return CGSize(width: Layout.HUD.listeningWidth, height: height)
        case .handsFree:
            return CGSize(width: Layout.HUD.handsFreeWidth, height: height)
        case .done:
            if let notice = state.notice {
                return messageSize(notice, lineLimit: Layout.HUD.failureLineLimit, hasAction: state.hasAction)
            }
            return CGSize(width: height, height: height)
        case .cancelled:
            return CGSize(width: height, height: height)
        case .failed:
            return messageSize(state.failureMessage ?? "", lineLimit: Layout.HUD.failureLineLimit,
                               hasAction: state.hasAction)
        }
    }

    /// A glyph and text up to `messageMaxWidth`, and a trailing chevron when the message links
    /// somewhere. A message that fits stays on one line at the standard height; a longer one
    /// wraps to at most `lineLimit` lines and the pill grows taller (up to `messageMaxHeight`)
    /// rather than cutting off the end of the sentence.
    static func messageSize(_ message: String, lineLimit: Int = 1, hasAction: Bool = false) -> CGSize {
        let text = min(textWidth(message, pointSize: Layout.HUD.labelPointSize), Layout.HUD.messageMaxWidth)
        var width = Layout.HUD.contentPadding * 2 + Layout.HUD.failureGlyph + Spacing.s + text
        if hasAction {
            width += Spacing.s + Layout.HUD.actionDisc
        }
        var height = Layout.HUD.height
        let lines = messageLines(message, lineLimit: lineLimit)
        if lines > 1 {
            let font = NSFont.systemFont(ofSize: Layout.HUD.labelPointSize, weight: .medium)
            let bounds = (message as NSString).boundingRect(
                with: CGSize(width: Layout.HUD.messageMaxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let textHeight = min(ceil(bounds.height), lineHeight * CGFloat(lines))
            height = min(max(height, textHeight + Spacing.s * 2), Layout.HUD.messageMaxHeight)
        }
        return CGSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    /// How many lines a message is drawn on: one when it fits `messageMaxWidth`, otherwise
    /// `lineLimit`. Deciding here (not in SwiftUI) keeps the text and the pill's size in step.
    static func messageLines(_ message: String, lineLimit: Int) -> Int {
        let fits = textWidth(message, pointSize: Layout.HUD.labelPointSize) <= Layout.HUD.messageMaxWidth
        return fits ? 1 : max(1, lineLimit)
    }

    /// The pill's frame inside the panel, in AppKit (y-up) coordinates.
    static func pillFrame(for state: HUDState) -> CGRect {
        let size = pillSize(for: state)
        return CGRect(
            x: (Layout.HUD.panelSize.width - size.width) / 2,
            y: Layout.HUD.shadowMargin,
            width: size.width,
            height: size.height
        )
    }

    /// What the pointer is over, given a point in panel coordinates (y-up).
    static func hitTest(_ point: CGPoint, state: HUDState) -> HUDHover? {
        let frame = pillFrame(for: state)
        switch state.kind {
        case .idle, .hint:
            let slop = Layout.HUD.hitSlop
            return frame.insetBy(dx: -slop, dy: -slop).contains(point) ? .pill : nil
        case .handsFree:
            guard frame.contains(point) else { return nil }
            let x = point.x - frame.minX
            let layout = handsFreeLayout(width: frame.width)
            let reach = Layout.HUD.buttonSize / 2 + Spacing.xxs
            if abs(x - layout.cancel) <= reach { return .cancel }
            if abs(x - layout.stop) <= reach { return .stop }
            return .pill
        case .done, .failed:
            guard state.hasAction else { return nil }
            return frame.contains(point) ? .pill : nil
        default:
            return nil
        }
    }

    /// Horizontal centres of the hands-free elements, in pill coordinates.
    struct HandsFreeLayout {
        var cancel: CGFloat
        var bars: CGFloat
        var timer: CGFloat
        var stop: CGFloat
    }

    static func handsFreeLayout(width: CGFloat) -> HandsFreeLayout {
        // Both buttons are concentric with the pill's end caps.
        let cancel = capCentre
        let stop = width - capCentre
        let timerTrailing = stop - Layout.HUD.buttonSize / 2 - Spacing.s
        let timer = timerTrailing - Layout.HUD.timerWidth / 2
        let barsLeading = cancel + Layout.HUD.buttonSize / 2 + Spacing.s
        let barsTrailing = timerTrailing - Layout.HUD.timerWidth - Spacing.s
        return HandsFreeLayout(cancel: cancel, bars: (barsLeading + barsTrailing) / 2, timer: timer, stop: stop)
    }

    /// Measured widths by key name. The hint is hit-tested on every pointer move over the pill,
    /// and the key name rarely changes, so each one is measured once.
    private static var hintWidths: [String: CGFloat] = [:]

    /// Where the bars sit while listening or thinking: centred between the orb's edge and the
    /// pill's right end, so the space on either side of them matches.
    static func listeningBarsX(width: CGFloat) -> CGFloat {
        (capCentre + Layout.HUD.orb / 2 + width) / 2
    }

    static func hintWidth(keyName: String) -> CGFloat {
        if let cached = hintWidths[keyName] { return cached }
        let label = Layout.HUD.labelPointSize
        let keycap = textWidth(keyName, pointSize: Layout.HUD.keycapPointSize, weight: .semibold)
            + Layout.HUD.keycapPadding * 2
        let width = Layout.HUD.contentPadding * 2
            + textWidth(hintLead, pointSize: label)
            + textWidth(hintTrail, pointSize: label)
            + keycap
            + Layout.HUD.hintSpacing * 2
        // A couple of points of slack: AppKit and SwiftUI round glyph advances differently.
        let result = (width + Spacing.xxs * 2).rounded(.up)
        hintWidths[keyName] = result
        return result
    }

    static func textWidth(_ text: String, pointSize: CGFloat, weight: NSFont.Weight = .medium) -> CGFloat {
        let font = NSFont.systemFont(ofSize: pointSize, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// "0:42", "12:05".
    static func elapsedText(since start: Date?, now: Date) -> String {
        let seconds = elapsedSeconds(since: start, now: now)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Whole seconds recorded so far; 0 before recording starts.
    static func elapsedSeconds(since start: Date?, now: Date) -> Int {
        guard let start else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }

    /// The elapsed time as VoiceOver should say it: "42 seconds", "1 minute, 5 seconds".
    static func elapsedSpoken(since start: Date?, now: Date) -> String {
        let seconds = elapsedSeconds(since: start, now: now)
        // Asked for on every frame of the hands-free timeline; the text changes once a second.
        if let last = lastSpoken, last.seconds == seconds { return last.text }
        let text = Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        lastSpoken = (seconds, text)
        return text
    }

    private static var lastSpoken: (seconds: Int, text: String)?
}
