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
        } else {
            Task { await delete(ids: ids) }
        }
    }

    func confirmPendingDelete() async {
        let ids = pendingDeleteIDs
        pendingDeleteIDs = []
        await delete(ids: ids)
    }

    func cancelPendingDelete() {
        pendingDeleteIDs = []
    }
}
