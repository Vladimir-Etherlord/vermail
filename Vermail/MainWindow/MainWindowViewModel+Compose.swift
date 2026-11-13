import Foundation

extension MainWindowViewModel {
    func openCompose(_ request: ComposeRequest) {
        guard let model = makeComposeViewModel(for: request) else {
            lastError = String(localized: "Add an account before composing.")
            return
        }
        composeWindows.open(model: model, preferences: preferencesStore) { [weak self] in
            Task { await self?.reloadMessages() }
        }
    }

    func requestDelete(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        if preferencesStore.preferences.confirmDelete {
            pendingDeleteIDs = ids
            isDeleteConfirmationPresented = true
        } else {
            Task { await delete(ids: ids) }
        }
    }

    func confirmPendingDelete() async {
        let ids = pendingDeleteIDs
        pendingDeleteIDs = []
        isDeleteConfirmationPresented = false
        await delete(ids: ids)
    }

    func cancelPendingDelete() {
        pendingDeleteIDs = []
        isDeleteConfirmationPresented = false
    }
}
