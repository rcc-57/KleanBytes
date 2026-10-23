import AppKit
import SwiftUI

struct ContentView: View {
    let model: DiskScannerViewModel
    @State private var showsQuickScanSettings = false
    @State private var showsUninstaller = false

    var body: some View {
        @Bindable var model = model

        ZStack {
            if showsUninstaller {
                ApplicationUninstallerView { message in
                    model.message = message
                    model.refreshDiskInformation()
                    showsUninstaller = false
                }
                .transition(.opacity)
            } else {
                switch model.appState {
                case .start:
                    StartView(
                        volume: model.volume,
                        message: model.message,
                        hasFullDiskAccess: model.hasFullDiskAccess,
                        quickScanAction: model.startQuickScan,
                        quickScanSettingsAction: { showsQuickScanSettings = true },
                        fullScanAction: model.startFullScan,
                        uninstallerAction: { showsUninstaller = true }
                    )
                    .transition(.opacity)
                case .scanning:
                    ScanningView(
                        currentPath: model.currentPath,
                        progress: model.scanningProgress,
                        isPreparing: model.isPreparingScan,
                        cancelAction: model.cancelScan
                    )
                    .transition(.opacity)
                case .results:
                    if let directory = model.currentDirectory,
                       let scanMode = model.activeScanMode {
                        ResultsView(
                            directory: directory,
                            canNavigateBack: model.canNavigateBack,
                            checkedIDs: model.checkedIDs,
                            selectedNodes: model.selectedNodes,
                            isDeletingSelection: model.isDeletingSelection,
                            unlockedIDs: model.unlockedIDs,
                            quickScanConfiguration: model.quickScanConfiguration,
                            scanMode: scanMode,
                            selection: $model.selectedID,
                            backAction: model.navigateBack,
                            rescanAction: model.returnToStart,
                            openAction: model.open,
                            toggleChecked: model.toggleChecked,
                            removeFromSelection: model.removeFromSelection,
                            toggleQuickScanMembership: model.toggleQuickScanMembership,
                            unlockAction: { node in await model.unlock(node) },
                            lockAction: model.lock,
                            revealAction: model.revealInFinder,
                            makeDeletionPlan: model.makeDeletionPlan,
                            deleteSelectedAction: model.permanentlyDeleteSelection,
                            finishDeletionAction: model.finishDeletionFlow
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: model.appState)
        .animation(.easeInOut(duration: 0.4), value: showsUninstaller)
        .frame(minWidth: 920, maxWidth: 920, minHeight: 620, maxHeight: 620)
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            ) {
                guard !Task.isCancelled else { break }
                model.refreshDiskInformation()
            }
        }
        .sheet(isPresented: $showsQuickScanSettings) {
            QuickScanSettingsView(
                configuration: model.quickScanConfiguration,
                configurationChanged: model.updateQuickScanConfiguration,
                resetAction: model.resetQuickScanConfiguration
            )
        }
        .alert(
            "Ошибка KleanBytes",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

}

#Preview {
    ContentView(model: DiskScannerViewModel())
}
