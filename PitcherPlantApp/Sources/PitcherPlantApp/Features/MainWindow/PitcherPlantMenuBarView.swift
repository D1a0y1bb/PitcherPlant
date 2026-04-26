import SwiftUI

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
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    menuSectionTitle("Recent Audits", count: filteredJobs.count)

                    if filteredJobs.isEmpty {
                        CompactEmptyRow(title: "No Audits", subtitle: "Start an audit from the main window")
                    } else {
                        ForEach(filteredJobs) { job in
                            CompactJobRow(job: job) {
                                appState.selectedJobID = job.id
                                appState.selectedMainSidebar = .history
                                openMainWindow()
                            }
                            Divider()
                        }
                    }

                    menuSectionTitle("Reports", count: filteredReports.count)

                    if filteredReports.isEmpty {
                        CompactEmptyRow(title: "No Reports", subtitle: "Finished audits appear here")
                    } else {
                        ForEach(filteredReports) { report in
                            CompactReportRow(report: report) {
                                appState.showReport(report.id)
                                openMainWindow()
                            }
                            Divider()
                        }
                    }
                }
            }
            .frame(height: 280)

            Divider()

            actions
        }
        .frame(width: 340)
        .task {
            await appState.bootstrapIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search audits, reports...", text: $searchText)
                .textFieldStyle(.plain)

            Text("\(filteredJobs.count + filteredReports.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding(12)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await appState.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    appState.selectedMainSidebar = .newAudit
                    openMainWindow()
                } label: {
                    Label("New", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await appState.startAudit()
                        openMainWindow()
                    }
                } label: {
                    Label(appState.isRunningAudit ? "Running" : "Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(appState.isRunningAudit)

                Button {
                    openMainWindow()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                Button {
                    appState.selectedMainSidebar = .settings
                    openMainWindow()
                } label: {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(12)
    }

    private func menuSectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func openMainWindow() {
        openWindow(id: AppWindow.main.rawValue)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CompactJobRow: View {
    let job: AuditJob
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MenuBarStatusDot(status: job.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: job.configuration.directoryPath).lastPathComponent)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(job.status.displayTitle) · \(job.progress)% · \(job.latestMessage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(job.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
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
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(report.sections.count) sections · \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
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
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption)
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
