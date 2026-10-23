import Foundation
import Observation

@MainActor
@Observable
final class ApplicationUninstallerViewModel {
    enum State {
        case loadingApplications
        case ready
        case loadingPlan
        case deleting
    }

    var applications: [InstalledApplication] = []
    var selectedApplicationID: URL?
    var plan: ApplicationUninstallPlan?
    var selectedRelatedIDs: Set<URL> = []
    var isApplicationSelected = true
    var state: State = .loadingApplications
    var errorMessage: String?
    var successMessage: String?
    var runningApplicationsAwaitingTermination: [String] = []

    private let service = ApplicationUninstallerService()
    private var cachedPlans: [URL: ApplicationUninstallPlan] = [:]
    private var measuredRelatedIDs: Set<URL> = []
    private var relatedSizeTask: Task<Void, Never>?

    func loadApplications() async {
        relatedSizeTask?.cancel()
        state = .loadingApplications
        applications = await service.installedApplications()
        cachedPlans = [:]
        measuredRelatedIDs = []
        state = .ready
        if let first = applications.first {
            await select(first)
        }
    }

    func select(_ application: InstalledApplication) async {
        relatedSizeTask?.cancel()
        selectedApplicationID = application.id
        plan = nil
        selectedRelatedIDs = []
        isApplicationSelected = true
        errorMessage = nil
        if let cachedPlan = cachedPlans[application.id] {
            plan = cachedPlan
            selectedRelatedIDs = Set(cachedPlan.relatedItems.map(\.id))
            state = .ready
            startPopulatingRelatedSizes(for: application.id)
            return
        }
        state = .loadingPlan
        do {
            let loadedPlan = try await service.plan(for: application)
            guard selectedApplicationID == application.id else { return }
            plan = loadedPlan
            cachedPlans[application.id] = loadedPlan
            selectedRelatedIDs = Set(loadedPlan.relatedItems.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
        state = .ready
        startPopulatingRelatedSizes(for: application.id)
    }

    func toggle(_ item: ApplicationRelatedItem) {
        if !selectedRelatedIDs.insert(item.id).inserted {
            selectedRelatedIDs.remove(item.id)
        }
    }

    func toggleApplicationSelection() {
        isApplicationSelected.toggle()
    }

    private func populateRelatedSizes(for applicationID: URL) async {
        guard let initialPlan = cachedPlans[applicationID] else { return }

        for item in initialPlan.relatedItems where !measuredRelatedIDs.contains(item.id) {
            guard !Task.isCancelled, selectedApplicationID == applicationID else { return }
            let size = await service.size(of: item.url)
            guard !Task.isCancelled, selectedApplicationID == applicationID else { return }
            measuredRelatedIDs.insert(item.id)

            guard let currentPlan = cachedPlans[applicationID] else { continue }

            let updatedItems = currentPlan.relatedItems
                .map { existingItem in
                    guard existingItem.id == item.id else { return existingItem }
                    return ApplicationRelatedItem(
                        id: existingItem.id,
                        url: existingItem.url,
                        category: existingItem.category,
                        size: size,
                        isSizeCalculated: true
                    )
                }
                .sorted { $0.size > $1.size }
            let updatedPlan = ApplicationUninstallPlan(
                application: currentPlan.application,
                relatedItems: updatedItems,
                requiresVendorUninstaller: currentPlan.requiresVendorUninstaller
            )
            cachedPlans[applicationID] = updatedPlan
            if selectedApplicationID == applicationID {
                plan = updatedPlan
            }
        }
    }

    private func startPopulatingRelatedSizes(for applicationID: URL) {
        relatedSizeTask?.cancel()
        relatedSizeTask = Task { [weak self] in
            await self?.populateRelatedSizes(for: applicationID)
        }
    }

    func permanentlyDeleteSelectedApplication() async {
        guard let plan else { return }
        let runningNames = await service.runningApplicationNames(for: plan)
        guard runningNames.isEmpty else {
            runningApplicationsAwaitingTermination = runningNames
            return
        }
        await executeDeletion(of: plan)
    }

    func terminateRunningApplicationsAndDelete() async {
        guard let plan else { return }
        runningApplicationsAwaitingTermination = []
        state = .deleting
        let terminated = await service.terminateRunningApplications(for: plan)
        guard terminated else {
            errorMessage = "Не удалось завершить приложение. Закройте его вручную и повторите удаление."
            state = .ready
            return
        }
        await executeDeletion(of: plan)
    }

    func cancelRunningApplicationTermination() {
        runningApplicationsAwaitingTermination = []
        state = .ready
    }

    private func executeDeletion(of plan: ApplicationUninstallPlan) async {
        state = .deleting
        errorMessage = nil
        do {
            let result = try await service.permanentlyDelete(
                plan: plan,
                removeApplication: isApplicationSelected,
                selectedRelatedIDs: selectedRelatedIDs
            )
            if result.succeeded {
                let removed = result.removedURLs.map(\.lastPathComponent).joined(separator: "\n")
                successMessage = "Удалены:\n\(removed)"
            } else {
                errorMessage = "Удаление выполнено частично:\n" + result.failures.joined(separator: "\n")
            }
            selectedApplicationID = nil
            self.plan = nil
            selectedRelatedIDs = []
            isApplicationSelected = true
            await loadApplications()
        } catch {
            errorMessage = error.localizedDescription
            state = .ready
        }
    }
}
