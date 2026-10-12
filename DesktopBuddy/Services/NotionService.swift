import Foundation
import Observation
import BuddyCore
import BuddyIntegrations
import os

/// Notion, via an internal-integration or personal access token kept in the Keychain.
/// "Connected" only after the token has been verified against Notion.
@Observable
final class NotionService {
    enum Status: Equatable {
        case disconnected
        case verifying
        case connected
        /// The saved token stopped working (revoked, or the integration was removed).
        case needsReconnect
    }

    private(set) var status: Status = .disconnected
    /// Workspace (integration token) or person (personal token) the token belongs to.
    private(set) var identity: String?
    /// Databases the token can see.
    private(set) var dataSources: [NotionDataSource] = []
    /// Schema of the database being set up.
    private(set) var schema: NotionSchema?
    /// Saved once the user confirms it; nil until then.
    private(set) var mapping: NotionMapping?
    /// Open tasks from the mapped database — candidates for today's plan.
    private(set) var openTasks: [NotionTask] = []
    private(set) var lastUpdated: Date?
    private(set) var problem: String?
    private(set) var isLoading = false

    var isConnected: Bool { status == .connected }
    var isReady: Bool { isConnected && mapping != nil }

    @ObservationIgnored private var token: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "notion")

    private enum Key {
        static let token = "notion.token"
        static let mapping = "notion.mapping"
        static let identity = "notion.identity"
    }

    init(persistent: Bool = true, defaults: UserDefaults = .standard) {
        self.persistent = persistent
        self.defaults = defaults
        // Notion is paused (Features.notion), so don't touch the Keychain for it at launch.
        guard persistent, Features.notion else { return }
        Task { [weak self] in
            guard let saved = await Keychain.stringInBackground(for: Key.token), let self, self.token == nil else { return }
            self.token = saved
            self.status = .connected
            self.identity = defaults.string(forKey: Key.identity)
            self.mapping = defaults.data(forKey: Key.mapping).flatMap { try? JSONDecoder().decode(NotionMapping.self, from: $0) }
        }
    }

    // MARK: - Connect

    /// Verifies the token with Notion before storing it, then lists the databases it can see.
    func connect(token raw: String) async {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        status = .verifying
        problem = nil
        do {
            let data = try await HTTP.send(NotionAPI.meRequest(token: candidate))
            token = candidate
            identity = NotionAPI.decodeIdentity(data)
            if persistent {
                Keychain.set(candidate, for: Key.token)
                defaults.set(identity, forKey: Key.identity)
            }
            status = .connected
            await loadDataSources()
        } catch IntegrationError.unauthorized {
            status = .disconnected
            problem = "Notion didn't accept that token. Check you copied the whole secret."
        } catch {
            status = .disconnected
            problem = (error as? IntegrationError)?.userMessage ?? error.localizedDescription
        }
    }

    /// Forgets the token, the mapping and every fetched task. Tasks already added to
    /// today's list stay as ordinary local tasks.
    func disconnect() {
        Keychain.remove(Key.token)
        defaults.removeObject(forKey: Key.mapping)
        defaults.removeObject(forKey: Key.identity)
        token = nil
        identity = nil
        dataSources = []
        schema = nil
        mapping = nil
        openTasks = []
        lastUpdated = nil
        problem = nil
        status = .disconnected
    }

    // MARK: - Setup

    func loadDataSources() async {
        await run {
            var all: [NotionDataSource] = []
            var cursor: String?
            repeat {
                let data = try await HTTP.send(NotionAPI.searchDataSourcesRequest(token: $0, cursor: cursor))
                let page = try NotionAPI.decodeDataSources(data)
                all += page.sources
                cursor = page.nextCursor
            } while cursor != nil && all.count < 200
            dataSources = all
            if all.isEmpty {
                problem = "No databases are shared with this integration yet. In Notion, open your task database › ••• › Connections and add it."
            }
        }
    }

    /// Loads a database's columns and returns a suggested mapping for the user to confirm.
    func schemaAndSuggestion(for source: NotionDataSource) async -> NotionMapping? {
        var suggestion: NotionMapping?
        await run {
            let data = try await HTTP.send(NotionAPI.dataSourceRequest(id: source.id, token: $0))
            let schema = try NotionAPI.decodeSchema(data)
            self.schema = schema
            suggestion = NotionMapping.suggested(for: source, schema: schema)
            if suggestion == nil { problem = "“\(source.title)” has no title column, so it can't be used for tasks." }
        }
        return suggestion
    }

    func save(_ mapping: NotionMapping) async {
        self.mapping = mapping
        if persistent, let data = try? JSONEncoder().encode(mapping) {
            defaults.set(data, forKey: Key.mapping)
        }
        await refreshTasks()
    }

    // MARK: - Tasks

    /// Open tasks from the mapped database (first few hundred, soonest due first).
    func refreshTasks() async {
        guard let mapping else { return }
        await run {
            var all: [NotionTask] = []
            var cursor: String?
            repeat {
                let data = try await HTTP.send(NotionAPI.queryOpenTasksRequest(mapping: mapping, token: $0, cursor: cursor))
                let page = try NotionAPI.decodeTasks(data, mapping: mapping)
                all += page.tasks.filter { !$0.isDone }
                cursor = page.nextCursor
            } while cursor != nil && all.count < 300
            openTasks = all
            lastUpdated = .now
        }
    }

    /// Fresh title, due date and done state for tasks already on today's list.
    func currentState(of refs: [ExternalTaskRef]) async -> [ExternalTaskRef: (title: String, deadline: Date?, isDone: Bool)] {
        guard let mapping, let token, status == .connected else { return [:] }
        var updates: [ExternalTaskRef: (title: String, deadline: Date?, isDone: Bool)] = [:]
        for ref in refs.prefix(25) where ref.source == .notion {
            guard let data = try? await HTTP.send(NotionAPI.pageRequest(id: ref.id, token: token)),
                  let task = try? NotionAPI.decodeTask(data, mapping: mapping) else { continue }
            updates[ref] = (task.title, task.due, task.isDone)
        }
        return updates
    }

    /// Marks a page done in Notion. Only called after the user confirms.
    func markDone(_ ref: ExternalTaskRef) async throws {
        guard let mapping, let token else { throw IntegrationError.notConnected }
        guard let request = NotionAPI.markDoneRequest(pageID: ref.id, mapping: mapping, token: token) else {
            throw IntegrationError.invalidResponse("This database has no status column mapped.")
        }
        do {
            _ = try await HTTP.send(request)
            openTasks.removeAll { $0.id == ref.id }
        } catch IntegrationError.unauthorized {
            status = .needsReconnect
            throw IntegrationError.unauthorized
        }
    }

    // MARK: -

    private func run(_ work: (String) async throws -> Void) async {
        guard let token else { status = .disconnected; return }
        isLoading = true
        defer { isLoading = false }
        do {
            problem = nil
            try await work(token)
        } catch IntegrationError.unauthorized {
            status = .needsReconnect
            problem = "Notion no longer accepts the saved token. Paste a new one to reconnect."
        } catch let error as IntegrationError {
            problem = error.userMessage
            log.error("Notion request failed: \(error.userMessage, privacy: .public)")
        } catch {
            problem = error.localizedDescription
        }
    }
}

#if DEBUG
extension NotionService {
    /// Snapshot renderer only: shows sample tasks without any token or network.
    func loadPreview(mapping: NotionMapping, tasks: [NotionTask], workspace: String) {
        self.mapping = mapping
        openTasks = tasks
        identity = workspace
        lastUpdated = .now
        status = .connected
    }
}
#endif
