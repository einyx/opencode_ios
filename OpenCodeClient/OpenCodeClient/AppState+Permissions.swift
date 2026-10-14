import Foundation

/// Permission + question responses. Both are async server requests; the
/// SSE channel doesn't replay them, so `refresh*` is called when the user
/// enters a session that was already mid-flight.
extension AppState {
    /// Retire in-flight GET ownership without discarding displayed requests.
    func invalidatePendingRequestEpoch() {
        pendingRequestEpoch &+= 1
        permissionRevision &+= 1
        questionRevision &+= 1
        permissionPollID = nil
        questionPollID = nil
    }

    func respondPermission(_ perm: PendingPermission, response: APIClient.PermissionResponse) async {
        let host = captureHostRequestSnapshot()
        do {
            try await apiClient.respondPermission(sessionID: perm.sessionID, permissionID: perm.permissionID, response: response)
            guard isCurrentHostRequest(host) else { return }
            permissionRevision &+= 1
            pendingPermissions.removeAll { $0.id == perm.id }
            await refreshPendingPermissions()
        } catch {
            guard isCurrentHostRequest(host) else { return }
            connectionError = error.localizedDescription
        }
    }

    /// SSE permission events are not replayed; poll pending permissions so users can enter
    /// an in-progress session and still see the warning.
    func refreshPendingPermissions() async {
        guard isConnected, permissionPollID == nil else { return }
        let host = captureHostRequestSnapshot()
        let revision = permissionRevision
        let id = UUID()
        permissionPollID = id
        defer { if permissionPollID == id { permissionPollID = nil } }
        do {
            let requests = try await apiClient.pendingPermissions()
            guard isCurrentHostRequest(host), permissionPollID == id, permissionRevision == revision else { return }
            pendingPermissions = PermissionController.fromPendingRequests(requests)
        } catch {
            // Keep the current list on errors.
        }
    }

    func respondQuestion(_ request: QuestionRequest, answers: [[String]]) async -> Bool {
        let host = captureHostRequestSnapshot()
        do {
            try await apiClient.replyQuestion(requestID: request.id, answers: answers)
            guard isCurrentHostRequest(host) else { return false }
            questionRevision &+= 1
            pendingQuestions.removeAll { $0.id == request.id }
            return true
        } catch {
            guard isCurrentHostRequest(host) else { return false }
            connectionError = error.localizedDescription
            return false
        }
    }

    func rejectQuestion(_ request: QuestionRequest) async {
        let host = captureHostRequestSnapshot()
        do {
            try await apiClient.rejectQuestion(requestID: request.id)
            guard isCurrentHostRequest(host) else { return }
            questionRevision &+= 1
            pendingQuestions.removeAll { $0.id == request.id }
        } catch {
            guard isCurrentHostRequest(host) else { return }
            connectionError = error.localizedDescription
        }
    }

    func refreshPendingQuestions() async {
        guard isConnected, questionPollID == nil else { return }
        let host = captureHostRequestSnapshot()
        let revision = questionRevision
        let id = UUID()
        questionPollID = id
        defer { if questionPollID == id { questionPollID = nil } }
        do {
            let requests = try await apiClient.pendingQuestions()
            guard isCurrentHostRequest(host), questionPollID == id, questionRevision == revision else { return }
            pendingQuestions = requests
        } catch {
            guard isCurrentHostRequest(host) else { return }
            connectionError = error.localizedDescription
        }
    }
}
