import SwiftUI
import AppKit

struct PitcherPlantMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var appState: AppState
    @State private var searchText = ""

    private var filteredJobs: [AuditJob] {
        let jobs = appState.jobs.sorted { $0.updatedAt > $1.updatedAt }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return Array(jobs.prefix(8))
        }
        return Array(jobs.filter { job in
            [
                URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent,
                job.configuration.directoryPath,
                job.status.displayTitle,
                job.latestMessage
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }.prefix(8))
    }

    private var filteredReports: [AuditReport] {
        let reports = appState.reports.sorted { $0.createdAt > $1.createdAt }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return Array(reports.prefix(5))
        }
        return Array(reports.filter { report in
            [
                report.title,
                report.scanDirectoryPath,
                report.sourcePath
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }.prefix(5))
    }

    var body: some View {
        menuPanelContent
            .frame(width: 360)
            .background(MenuBarPanelMaterial())
            .task {
                await appState.bootstrapIfNeeded()
            }
    }

    @ViewBuilder
    private var menuPanelContent: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                panelContent
            }
        } else {
            panelContent
        }
        #else
        panelContent
        #endif
    }

    private var panelContent: some View {
        VStack(spacing: 12) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    MenuBarGlassSection(title: appState.t("menu.recentAudits"), count: filteredJobs.count) {
                        if filteredJobs.isEmpty {
                            CompactEmptyRow(title: appState.t("menu.noAudits"), subtitle: appState.t("menu.noAuditsDescription"))
                        } else {
                            ForEach(Array(filteredJobs.enumerated()), id: \.element.id) { index, job in
                                CompactJobRow(job: job) {
                                    appState.selectedJobID = job.id
                                    appState.selectedMainSidebar = .history
                                    openMainWindow()
                                }
                                if index < filteredJobs.count - 1 {
                                    Divider().padding(.leading, 30)
                                }
                            }
                        }
                    }

                    MenuBarGlassSection(title: appState.t("reports.title"), count: filteredReports.count) {
                        if filteredReports.isEmpty {
                            CompactEmptyRow(title: appState.t("menu.noReports"), subtitle: appState.t("menu.noReportsDescription"))
                        } else {
                            ForEach(Array(filteredReports.enumerated()), id: \.element.id) { index, report in
                                CompactReportRow(report: report) {
                                    appState.showReport(report.id)
                                    openMainWindow()
                                }
                                if index < filteredReports.count - 1 {
                                    Divider().padding(.leading, 30)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 300)

            actions
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(appState.t("menu.searchPrompt"), text: $searchText)
                .textFieldStyle(.plain)

            Text("\(filteredJobs.count + filteredReports.count)")
                .font(AppTypography.badge)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .modifier(MenuBarGlassSurface(radius: 18))
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await appState.reload() }
                } label: {
                    Label(appState.t("common.refresh"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    appState.selectedMainSidebar = .newAudit
                    openMainWindow()
                } label: {
                    Label(appState.t("common.new"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                Button {
                    if appState.isRunningAudit {
                        appState.cancelAudit()
                    } else {
                        appState.beginAudit()
                        openMainWindow()
                    }
                } label: {
                    Label(
                        appState.isRunningAudit ? appState.t("command.cancelAudit") : appState.t("toolbar.start"),
                        systemImage: appState.isRunningAudit ? "stop.fill" : "play.fill"
                    )
                        .frame(maxWidth: .infinity)
                }

                Button {
                    openMainWindow()
                } label: {
                    Label(appState.t("common.open"), systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                Button {
                    appState.selectedMainSidebar = .settings
                    openMainWindow()
                } label: {
                    Label(appState.t("settings.title"), systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(appState.t("common.quit"), systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(10)
        .modifier(MenuBarGlassSurface(radius: 18))
    }

    private func openMainWindow() {
        openWindow(id: AppWindow.main.rawValue)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarGlassSection<Content: View>: View {
    let title: String
    let count: Int
    let content: Content

    init(title: String, count: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(AppTypography.tableHeader)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(AppTypography.badge)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            VStack(spacing: 0) {
                content
            }
        }
        .modifier(MenuBarGlassSurface(radius: 18))
    }
}

private struct MenuBarGlassSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.separator.opacity(0.18))
                }
        }
        #else
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.stroke(.separator.opacity(0.18))
            }
        #endif
    }
}

private struct MenuBarPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.isEmphasized = true
    }
}

private struct CompactJobRow: View {
    @Environment(AppState.self) private var appState
    let job: AuditJob
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MenuBarStatusDot(status: job.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                        .font(AppTypography.rowPrimary)
                        .lineLimit(1)
                    Text("\(appState.title(for: job.status)) · \(job.progress)% · \(job.latestMessage)")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(job.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CompactReportRow: View {
    @Environment(AppState.self) private var appState
    let report: AuditReport
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: report.isLegacy ? "doc.richtext" : "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(AppTypography.rowPrimary)
                        .lineLimit(1)
                    Text("\(report.sections.count) \(appState.t("reports.sectionSummary")) · \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CompactEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.rowPrimary)
            Text(subtitle)
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuBarStatusDot: View {
    let status: AuditJobStatus

    private var color: Color {
        switch status {
        case .queued: return .secondary.opacity(0.5)
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
