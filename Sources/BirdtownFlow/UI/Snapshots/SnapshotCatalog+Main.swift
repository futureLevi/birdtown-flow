import MurmurKit
import SwiftUI

// Owned by the ui-main agent: main window screens with sample data.
extension SnapshotCatalog {
    static var main: [SnapshotRenderer.Shot] {
        let size = CGSize(width: 1040, height: 700)
        let records = SampleData.records()
        let sample = MainPreview(status: SampleData.readyStatus, firstName: "Levi", orbPhase: Self.orbPhase)
        var firstRun = sample
        firstRun.status?.model = .downloading(0.42)
        var search = sample
        search.historyQuery = "migration"
        var original = sample
        original.originalRecordID = records.first { !$0.corrections.isEmpty }?.id

        return [
            SnapshotRenderer.Shot("home", size: size) { window(.home, records: records, preview: sample) },
            SnapshotRenderer.Shot("home-empty", size: size) { window(.home, records: [], preview: firstRun) },
            SnapshotRenderer.Shot("history", size: size) { window(.history, records: records, preview: sample) },
            SnapshotRenderer.Shot("history-search", size: size) { window(.history, records: records, preview: search) },
            SnapshotRenderer.Shot("history-expanded-original", size: size) {
                window(.history, records: records, preview: original)
            },
            SnapshotRenderer.Shot("dictionary", size: size) { window(.dictionary, records: records, preview: sample) },
            SnapshotRenderer.Shot("snippets", size: size) { window(.snippets, records: records, preview: sample) },
            SnapshotRenderer.Shot("style", size: size) { window(.style, records: records, preview: sample) },
            // The Lab as it opens, and the whole page: editor, test text and results.
            SnapshotRenderer.Shot("lab", size: size) { lab(records: records, preview: sample) },
            SnapshotRenderer.Shot("lab-full", size: CGSize(width: size.width, height: 2_150)) {
                lab(records: records, preview: sample)
            },
            // Every configuration deleted: the Lab invites a new one.
            SnapshotRenderer.Shot("lab-empty", size: size) { labEmpty(records: records, preview: sample) },
            // The sidebar column on its own: macOS 26 hosts it in a glass panel that offscreen
            // rendering can't capture, so it gets a shot of its own (with each status state).
            SnapshotRenderer.Shot("main-sidebar", size: CGSize(width: 4 * Layout.sidebarWidth, height: 520)) {
                sidebars(records: records)
            },
            // The toolbar never renders in window shots, so its contents (a mock of the bar)
            // and the shared controls get a sheet of their own.
            SnapshotRenderer.Shot("main-components", size: CGSize(width: 760, height: 470)) {
                components(records: records)
            },
        ]
    }

    /// A fixed moment in the live orb's turn, so recording states render identically.
    private static let orbPhase: Double = 2.4

    private static func components(records: [HistoryRecord]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            toolbarMock
            HStack(spacing: Spacing.m) {
                Button("Continue Setup") {}.buttonStyle(.flowPrimary).controlSize(.small)
                Button("Open Settings") {}.buttonStyle(.flowSecondary)
                Button("All history") {}.buttonStyle(.flowGhost)
            }
            HStack(spacing: Spacing.s) {
                FilterChip(title: "All", isSelected: true) {}
                FilterChip(title: "Failed", symbol: "exclamationmark.triangle", count: 2, isSelected: false) {}
                FilterChip(title: "Polished", symbol: "sparkles", count: 6, isSelected: false) {}
                Badge(text: "Polished · Claude", symbol: "sparkles")
                Badge(text: "Chosen", tone: .accent)
                Badge(text: "Failed", symbol: "exclamationmark.triangle.fill", tone: .danger)
            }
            HStack(alignment: .top, spacing: Spacing.m) {
                Card(isSelected: true) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Selected card").font(Typography.headline).foregroundStyle(Palette.ink)
                        Text("Signal blue ring over a soft wash.").font(Typography.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack(spacing: Spacing.s) {
                            Text("Hold").font(Typography.callout).foregroundStyle(Palette.inkSecondary)
                            KeyCap(label: "fn")
                            StatusDot(color: Palette.success)
                            StatusDot(color: Palette.danger)
                        }
                        SpectrumProgressBar(progress: 0.42)
                    }
                }
                StatTile(label: "Pace", value: 152, unit: "wpm", caption: "3.4× faster than typing")
            }
            .fixedSize(horizontal: false, vertical: true)
            SearchField(text: .constant("migration"), prompt: "Search words or apps")
                .frame(width: Layout.Main.searchFieldWidth)
        }
        .padding(Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .environment(previewModel(records: records, section: .home))
        .transaction { $0.disablesAnimations = true }
    }

    /// The window's toolbar as macOS lays it out: traffic lights, the sidebar button and
    /// Settings on the left, the wordmark centred. Only the wordmark is the real view; the
    /// glass buttons are drawn here because offscreen rendering can't capture the toolbar.
    private static var toolbarMock: some View {
        ZStack {
            HStack(spacing: Spacing.s) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Palette.hairlineStrong).frame(width: MockChrome.light, height: MockChrome.light)
                }
                Spacer().frame(width: Spacing.l)
                ForEach(["sidebar.left", "gearshape"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(Typography.bodyEmphasis)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: MockChrome.button, height: MockChrome.button)
                        .background(Circle().fill(Palette.surface))
                        .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
                }
                Spacer()
            }
            ToolbarWordmark()
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: MockChrome.bar)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.canvas))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .strokeBorder(Palette.hairline, lineWidth: Layout.Main.hairline))
    }

    /// Sizes of the system chrome the toolbar mock draws: traffic lights, glass buttons, the bar.
    private enum MockChrome {
        static let light: CGFloat = 12
        static let button: CGFloat = 32
        static let bar: CGFloat = 52
    }

    /// The Lab mid-session: a draft open, three styles assigned and four results.
    private static func lab(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records, lab: SampleData.labState)
        model.section = .lab
        model.settings.polishProvider = .claudeCode
        model.bench.preview(selected: SampleData.labDraft.id, draft: SampleData.labDraft, runs: SampleData.labRuns())
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    /// The Lab with no configurations left.
    private static func labEmpty(records: [HistoryRecord], preview: MainPreview) -> some View {
        let model = AppModel.preview(records: records, lab: PolishLabState())
        model.section = .lab
        model.settings.polishProvider = .claudeCode
        model.bench.preview(selected: nil, draft: nil, runs: [])
        return MainView()
            .environment(model)
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }

    private static func sidebars(records: [HistoryRecord]) -> some View {
        let ready = SampleData.readyStatus
        var noAccess = ready
        noAccess.accessibility = false
        noAccess.model = .downloading(0.42)
        var recording = ready
        recording.isRecording = true
        var failed = ready
        failed.model = .failed("The model files are damaged. Birdtown Flow will download them again.")
        return HStack(spacing: 0) {
            ForEach(Array([ready, noAccess, recording, failed].enumerated()), id: \.offset) { index, status in
                MainSidebar(status: status)
                    .environment(previewModel(records: records, section: index == 0 ? .home : .history))
                    .environment(\.mainPreview, MainPreview(orbPhase: Self.orbPhase))
                    .frame(width: Layout.sidebarWidth)
                    .background(Palette.sunken)
            }
        }
        .transaction { $0.disablesAnimations = true }
    }

    private static func previewModel(records: [HistoryRecord], section: SidebarSection) -> AppModel {
        let model = AppModel.preview(records: records)
        model.section = section
        return model
    }

    /// The main window on `section`, backed by an in-memory model. Animations are disabled
    /// so count-ups and fades are captured at rest.
    private static func window(_ section: SidebarSection, records: [HistoryRecord], preview: MainPreview) -> some View {
        MainView()
            .environment(previewModel(records: records, section: section))
            .environment(\.mainPreview, preview)
            .transaction { $0.disablesAnimations = true }
    }
}
