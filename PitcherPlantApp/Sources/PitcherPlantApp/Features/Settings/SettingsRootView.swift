import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsGroup("通用", icon: "gearshape.fill") {
                    VStack(spacing: 0) {
                        SettingsRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("工作区目录")
                                    .fontWeight(.medium)
                                Text(appState.workspaceRoot.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        SettingsDivider()
                        SettingsRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("最近报告")
                                    .fontWeight(.medium)
                                Text(appState.latestReport?.title ?? "暂无")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SettingsGroup("迁移", icon: "clock.arrow.circlepath") {
                    VStack(spacing: 0) {
                        SettingsRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("旧版导入摘要")
                                    .fontWeight(.medium)
                                Text(summaryText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var summaryText: String {
        guard let summary = appState.lastMigrationSummary else {
            return "尚未产生迁移记录。"
        }
        return "任务 \(summary.importedJobs) 条，报告 \(summary.importedReports) 份，指纹 \(summary.importedFingerprints) 条，白名单 \(summary.importedWhitelistRules) 条。"
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}
