import MurmurKit
import SwiftUI

/// Home's quiet "This week": the week's word count, large, with what it took and what it
/// saved in small type beneath. A card with a breath of teal in its far corner, no badges and
/// no gradients. The count rolls up when it appears (and just shows under Reduce Motion).
struct WeekSummary: View {
    let stats: DictationStats

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week")
                .font(Typography.headline)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, Layout.Home.weekTitleBottom)
            Text(shown, format: .number)
                .font(Typography.weekNumeral)
                .tracking(Tracking.weekNumeral)
                .foregroundStyle(Palette.heading)
                .contentTransition(.numericText(value: Double(shown)))
            Text(stats.wordsThisWeek == 1 ? "word dictated" : "words dictated")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, Layout.Home.weekLabelTop)
            Text("\(stats.totalWords.formatted()) all time")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, Layout.Home.weekNoteTop)
            VStack(alignment: .leading, spacing: 0) {
                RowDivider()
                HStack(alignment: .top, spacing: Layout.Home.weekDetailSpacing) {
                    detail(value: paceValue, label: paceLabel)
                    Spacer(minLength: 0)
                    detail(value: streakValue, label: "Current streak")
                }
                .padding(.top, Layout.Home.weekDetailInset)
            }
            .padding(.top, Layout.Home.weekDetailTop)
            // Saved time is all-time (unlike the week's count), so the line says "saved", not "this week".
            Text("\(minutesSavedText) saved vs. typing.")
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.Home.weekFootTop)
        }
        .padding(.horizontal, Layout.Home.weekInsetSide)
        .padding(.vertical, Layout.Home.weekInsetVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [.clear, Palette.tealSoft.opacity(Layout.Home.weekTealMix)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .cardSurface()
        .onAppear { roll(to: stats.wordsThisWeek) }
        .onChange(of: stats.wordsThisWeek) { _, newValue in roll(to: newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
        .accessibilityValue(spokenSummary)
    }

    private func detail(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Typography.groupTitle)
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Words

    private var paceValue: String {
        stats.averageWPM > 0 ? "\(stats.averageWPM) wpm" : "No pace yet"
    }

    private var paceLabel: String {
        guard stats.averageWPM > 0 else { return "Measured on longer dictations" }
        let speedup = Double(stats.averageWPM) / Double(DictationStats.typingWPM)
        return "\(speedup.formatted(.number.precision(.fractionLength(1))))× typing pace"
    }

    private var streakValue: String {
        stats.dayStreak == 1 ? "1 day" : "\(stats.dayStreak) days"
    }

    private var minutesSavedText: String {
        stats.minutesSaved == 1 ? "1 minute" : "\(stats.minutesSaved) minutes"
    }

    private var spokenSummary: String {
        [
            "\(stats.wordsThisWeek.formatted()) \(stats.wordsThisWeek == 1 ? "word" : "words") dictated",
            "\(stats.totalWords.formatted()) all time",
            "\(paceValue), \(paceLabel)",
            "\(streakValue), current streak",
            "\(minutesSavedText) saved versus typing",
        ].joined(separator: ". ")
    }

    private func roll(to target: Int) {
        guard !reduceMotion else {
            shown = target
            return
        }
        withAnimation(Motion.countUp) { shown = target }
    }
}
