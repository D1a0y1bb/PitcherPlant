import Testing
@testable import PitcherPlantApp

@Test
func mainWindowLaunchAndInspectorDefaultSizesUseVisualBaseline() {
    #expect(AppLayout.mainWindowDefaultWidth == 1220)
    #expect(AppLayout.mainWindowDefaultHeight == 704)
    #expect(AppLayout.inspectorDefaultWidth == 340)
    #expect(AppLayout.inspectorIdealWidth == AppLayout.inspectorDefaultWidth)
    #expect(AppLayout.inspectorMaxWidth == 440)
}

@Test
func settingsRootChromePaddingMatchesPresentationContext() {
    #expect(SettingsRootPresentation.standalone.topPadding == 28)
    #expect(SettingsRootPresentation.embeddedInTransparentTitlebar.topPadding == AppLayout.titlebarScrollContentTopPadding)
}

@Test
func mainWindowDisablesSidebarSelectionAnimationWhenInspectorWouldClose() {
    let policy = MainWindowInspectorTransitionPolicy()

    #expect(policy.disablesSelectionAnimation(inspectorVisible: true, currentItem: .workspace, targetItem: .settings))
    #expect(!policy.disablesSelectionAnimation(inspectorVisible: false, currentItem: .workspace, targetItem: .settings))
    #expect(!policy.disablesSelectionAnimation(inspectorVisible: true, currentItem: .settings, targetItem: .workspace))
    #expect(!policy.disablesSelectionAnimation(inspectorVisible: true, currentItem: .workspace, targetItem: .history))
}

@Test
func mainWindowLayoutCollapsesSidebarEarlierWhenInspectorIsVisible() {
    let policy = MainWindowLayoutPolicy()

    #expect(policy.sidebarAction(windowWidth: 820, inspectorVisible: true, sidebarCollapsed: false, autoCollapsedSidebar: false) == .collapse)
    #expect(policy.sidebarAction(windowWidth: 860, inspectorVisible: true, sidebarCollapsed: false, autoCollapsedSidebar: false) == .collapse)
    #expect(policy.sidebarAction(windowWidth: 1040, inspectorVisible: true, sidebarCollapsed: false, autoCollapsedSidebar: false) == .collapse)
    #expect(policy.sidebarAction(windowWidth: 1080, inspectorVisible: true, sidebarCollapsed: false, autoCollapsedSidebar: false) == .collapse)
    #expect(policy.sidebarAction(windowWidth: 1081, inspectorVisible: true, sidebarCollapsed: false, autoCollapsedSidebar: false) == .keep)
}

@Test
func mainWindowLayoutRestoresAutoCollapsedSidebarAtInspectorWideWidth() {
    let policy = MainWindowLayoutPolicy()

    #expect(policy.sidebarAction(windowWidth: 1160, inspectorVisible: true, sidebarCollapsed: true, autoCollapsedSidebar: true) == .keep)
    #expect(policy.sidebarAction(windowWidth: 1219, inspectorVisible: true, sidebarCollapsed: true, autoCollapsedSidebar: true) == .keep)
    #expect(policy.sidebarAction(windowWidth: 1220, inspectorVisible: true, sidebarCollapsed: true, autoCollapsedSidebar: true) == .restore)
}

@Test
func mainWindowLayoutUsesCompactThresholdsWhenInspectorIsHidden() {
    let policy = MainWindowLayoutPolicy()

    #expect(policy.sidebarAction(windowWidth: 820, inspectorVisible: false, sidebarCollapsed: false, autoCollapsedSidebar: false) == .collapse)
    #expect(policy.sidebarAction(windowWidth: 860, inspectorVisible: false, sidebarCollapsed: false, autoCollapsedSidebar: false) == .collapse)
    #expect(policy.sidebarAction(windowWidth: 861, inspectorVisible: false, sidebarCollapsed: false, autoCollapsedSidebar: false) == .keep)
    #expect(policy.sidebarAction(windowWidth: 1040, inspectorVisible: false, sidebarCollapsed: true, autoCollapsedSidebar: true) == .restore)
    #expect(policy.sidebarAction(windowWidth: 1280, inspectorVisible: false, sidebarCollapsed: true, autoCollapsedSidebar: true) == .restore)
}

@Test
func mainWindowLayoutKeepsUserHiddenSidebarHidden() {
    let policy = MainWindowLayoutPolicy()

    #expect(policy.sidebarAction(windowWidth: 1220, inspectorVisible: true, sidebarCollapsed: true, autoCollapsedSidebar: false) == .keep)
    #expect(policy.sidebarAction(windowWidth: 1280, inspectorVisible: true, sidebarCollapsed: true, autoCollapsedSidebar: false) == .keep)
    #expect(policy.sidebarAction(windowWidth: 1040, inspectorVisible: false, sidebarCollapsed: true, autoCollapsedSidebar: false) == .keep)
}
