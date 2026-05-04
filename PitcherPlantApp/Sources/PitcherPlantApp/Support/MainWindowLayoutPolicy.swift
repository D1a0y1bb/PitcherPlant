import CoreGraphics

struct MainWindowLayoutPolicy {
    enum SidebarAction: Equatable {
        case keep
        case collapse
        case restore
    }

    var collapseWidthWithInspector = AppLayout.sidebarCollapseWidthWithInspector
    var restoreWidthWithInspector = AppLayout.sidebarRestoreWidthWithInspector
    var collapseWidthWithoutInspector = AppLayout.sidebarCollapseWidthWithoutInspector
    var restoreWidthWithoutInspector = AppLayout.sidebarRestoreWidthWithoutInspector

    func sidebarAction(
        windowWidth: CGFloat,
        inspectorVisible: Bool,
        sidebarCollapsed: Bool,
        autoCollapsedSidebar: Bool
    ) -> SidebarAction {
        guard windowWidth > 0 else {
            return .keep
        }

        let collapseWidth = inspectorVisible ? collapseWidthWithInspector : collapseWidthWithoutInspector
        let restoreWidth = inspectorVisible ? restoreWidthWithInspector : restoreWidthWithoutInspector

        if windowWidth <= collapseWidth, sidebarCollapsed == false {
            return .collapse
        }

        if windowWidth >= restoreWidth, sidebarCollapsed, autoCollapsedSidebar {
            return .restore
        }

        return .keep
    }
}

struct MainWindowInspectorTransitionPolicy {
    func disablesSelectionAnimation(
        inspectorVisible: Bool,
        currentItem: MainSidebarItem,
        targetItem: MainSidebarItem
    ) -> Bool {
        inspectorVisible && currentItem.allowsInspector && !targetItem.allowsInspector
    }
}
