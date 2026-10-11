import Foundation
import BuddyCore

/// A Notion data source (the table inside a database) the token can see.
public struct NotionDataSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One column of a data source, as far as task mapping cares.
public struct NotionProperty: Codable, Equatable, Sendable {
    public var name: String
    /// Notion property type: "title", "status", "select", "checkbox", "date", …
    public var type: String
    /// Option names for status/select properties.
    public var options: [String]
    /// For status properties: options in the "Complete" group.
    public var completeOptions: [String]

    public init(name: String, type: String, options: [String] = [], completeOptions: [String] = []) {
        self.name = name
        self.type = type
        self.options = options
        self.completeOptions = completeOptions
    }
}

public struct NotionSchema: Equatable, Sendable {
    public var properties: [NotionProperty]

    public init(properties: [NotionProperty]) {
        self.properties = properties.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func properties(ofType types: String...) -> [NotionProperty] {
        properties.filter { types.contains($0.type) }
    }

    public func property(named name: String?) -> NotionProperty? {
        properties.first { $0.name == name }
    }
}

/// How a user's database maps onto tasks. No two Notion task databases look the same,
/// so this is chosen (or confirmed) by the user during setup — never assumed.
public struct NotionMapping: Codable, Equatable, Sendable {
    public enum StatusKind: String, Codable, Sendable { case status, select, checkbox }

    public var dataSourceID: String
    public var dataSourceTitle: String
    public var titleProperty: String
    public var statusProperty: String?
    public var statusKind: StatusKind?
    /// Values that count as done when reading (status/select).
    public var doneValues: [String]
    /// Value written when marking a task done (status/select).
    public var doneValue: String?
    public var dueProperty: String?
    public var priorityProperty: String?
    /// The user allowed the buddy to update completion in Notion (still confirmed each time).
    public var writeBackEnabled: Bool

    public init(dataSourceID: String, dataSourceTitle: String, titleProperty: String,
                statusProperty: String? = nil, statusKind: StatusKind? = nil, doneValues: [String] = [],
                doneValue: String? = nil, dueProperty: String? = nil, priorityProperty: String? = nil,
                writeBackEnabled: Bool = false) {
        self.dataSourceID = dataSourceID
        self.dataSourceTitle = dataSourceTitle
        self.titleProperty = titleProperty
        self.statusProperty = statusProperty
        self.statusKind = statusKind
        self.doneValues = doneValues
        self.doneValue = doneValue
        self.dueProperty = dueProperty
        self.priorityProperty = priorityProperty
        self.writeBackEnabled = writeBackEnabled
    }

    /// Whether this mapping knows how to mark a page done.
    public var canWriteCompletion: Bool {
        guard statusProperty != nil, let statusKind else { return false }
        return statusKind == .checkbox || doneValue != nil
    }

    /// A best guess the user can adjust: the title column, a status-like column and its
    /// "done" options, a due date, and a priority select.
    public static func suggested(for source: NotionDataSource, schema: NotionSchema) -> NotionMapping? {
        guard let title = schema.properties(ofType: "title").first else { return nil }
        var mapping = NotionMapping(dataSourceID: source.id, dataSourceTitle: source.title, titleProperty: title.name)

        let named = { (property: NotionProperty, words: [String]) in
            words.contains { property.name.lowercased().contains($0) }
        }
        if let status = schema.properties(ofType: "status").first {
            mapping.use(status: status)
        } else if let box = schema.properties(ofType: "checkbox").first(where: { named($0, ["done", "complete", "finished"]) }) {
            mapping.use(status: box)
        } else if let select = schema.properties(ofType: "select").first(where: { named($0, ["status", "state", "stage"]) }) {
            mapping.use(status: select)
        }
        mapping.dueProperty = (schema.properties(ofType: "date").first { named($0, ["due", "deadline", "date", "when"]) }
            ?? schema.properties(ofType: "date").first)?.name
        mapping.priorityProperty = schema.properties(ofType: "select", "status")
            .first { named($0, ["priority", "importance"]) && $0.name != mapping.statusProperty }?.name
        return mapping
    }

    /// Points the mapping at a status/select/checkbox property and guesses its done values.
    public mutating func use(status property: NotionProperty?) {
        guard let property, let kind = StatusKind(rawValue: property.type) else {
            statusProperty = nil; statusKind = nil; doneValues = []; doneValue = nil
            return
        }
        statusProperty = property.name
        statusKind = kind
        switch kind {
        case .checkbox:
            doneValues = []
            doneValue = nil
        case .status, .select:
            let doneWords = ["done", "complete", "completed", "finished", "shipped", "closed"]
            let guessed = property.options.filter { doneWords.contains($0.lowercased()) }
            doneValues = property.completeOptions.isEmpty ? guessed : property.completeOptions
            doneValue = doneValues.first ?? property.options.last
        }
    }
}

/// A task as read from Notion.
public struct NotionTask: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var url: URL?
    public var isDone: Bool
    public var due: Date?
    public var priority: TaskPriority
    public var statusName: String?

    public init(id: String, title: String, url: URL? = nil, isDone: Bool, due: Date? = nil,
                priority: TaskPriority = .none, statusName: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.isDone = isDone
        self.due = due
        self.priority = priority
        self.statusName = statusName
    }

    public var ref: ExternalTaskRef { ExternalTaskRef(source: .notion, id: id, url: url) }

    /// The local task to add when the user picks this one for today.
    public func makeTask(now: Date = .now) -> BuddyTask {
        BuddyTask(title: title, priority: priority, deadline: due, createdAt: now, external: ref)
    }
}

/// Notion REST API, version 2025-09-03 (databases contain "data sources").
public enum NotionAPI {
    public static let version = "2025-09-03"
    static let base = URL(string: "https://api.notion.com/v1/")!

    // MARK: Requests

    /// Who the token belongs to — used to verify a pasted token.
    public static func meRequest(token: String) -> URLRequest {
        request("users/me", token: token)
    }

    public static func searchDataSourcesRequest(token: String, cursor: String? = nil) -> URLRequest {
        var body: [String: Any] = ["filter": ["property": "object", "value": "data_source"], "page_size": 50]
        if let cursor { body["start_cursor"] = cursor }
        return request("search", method: "POST", token: token, json: body)
    }

    public static func dataSourceRequest(id: String, token: String) -> URLRequest {
        request("data_sources/\(id)", token: token)
    }

    /// Open tasks only, soonest due first.
    public static func queryOpenTasksRequest(mapping: NotionMapping, token: String, cursor: String? = nil) -> URLRequest {
        var body: [String: Any] = ["page_size": 100]
        if let cursor { body["start_cursor"] = cursor }
        if let property = mapping.statusProperty, let kind = mapping.statusKind {
            switch kind {
            case .checkbox:
                body["filter"] = ["property": property, "checkbox": ["equals": false]]
            case .status, .select:
                let clauses = mapping.doneValues.map { ["property": property, kind.rawValue: ["does_not_equal": $0]] }
                if clauses.count == 1 { body["filter"] = clauses[0] } else if !clauses.isEmpty { body["filter"] = ["and": clauses] }
            }
        }
        if let due = mapping.dueProperty {
            body["sorts"] = [["property": due, "direction": "ascending"]]
        } else {
            body["sorts"] = [["timestamp": "created_time", "direction": "descending"]]
        }
        return request("data_sources/\(mapping.dataSourceID)/query", method: "POST", token: token, json: body)
    }

    public static func pageRequest(id: String, token: String) -> URLRequest {
        request("pages/\(id)", token: token)
    }

    /// Marks a page done using the mapped status property, or nil if the mapping can't.
    public static func markDoneRequest(pageID: String, mapping: NotionMapping, token: String) -> URLRequest? {
        guard mapping.canWriteCompletion, let property = mapping.statusProperty, let kind = mapping.statusKind else { return nil }
        let value: Any = switch kind {
        case .checkbox: true
        case .status, .select: ["name": mapping.doneValue ?? ""]
        }
        return request("pages/\(pageID)", method: "PATCH", token: token,
                       json: ["properties": [property: [kind.rawValue: value]]])
    }

    // MARK: Decoding

    /// "Coco's workspace" for an integration token, or the person's name for a personal token.
    public static func decodeIdentity(_ data: Data) -> String? {
        guard let root = object(data) else { return nil }
        if let bot = root["bot"] as? [String: Any], let workspace = bot["workspace_name"] as? String { return workspace }
        return root["name"] as? String
    }

    public static func decodeDataSources(_ data: Data) throws -> (sources: [NotionDataSource], nextCursor: String?) {
        guard let root = object(data) else { throw IntegrationError.invalidResponse("Search result wasn't JSON.") }
        let sources = (root["results"] as? [[String: Any]] ?? []).compactMap { item -> NotionDataSource? in
            guard item["object"] as? String == "data_source", let id = item["id"] as? String,
                  item["in_trash"] as? Bool != true, item["archived"] as? Bool != true else { return nil }
            let title = plainText(item["title"])
            return NotionDataSource(id: id, title: title.isEmpty ? "Untitled" : title)
        }
        return (sources, root["next_cursor"] as? String)
    }

    public static func decodeSchema(_ data: Data) throws -> NotionSchema {
        guard let root = object(data), let properties = root["properties"] as? [String: [String: Any]] else {
            throw IntegrationError.invalidResponse("Database schema wasn't readable.")
        }
        return NotionSchema(properties: properties.map { name, config in
            let type = config["type"] as? String ?? "unknown"
            let settings = config[type] as? [String: Any] ?? [:]
            let options = settings["options"] as? [[String: Any]] ?? []
            let names = options.compactMap { $0["name"] as? String }
            var complete: [String] = []
            if type == "status", let groups = settings["groups"] as? [[String: Any]],
               let done = groups.first(where: { ($0["name"] as? String)?.lowercased() == "complete" }),
               let ids = done["option_ids"] as? [String] {
                complete = options.filter { ids.contains($0["id"] as? String ?? "") }.compactMap { $0["name"] as? String }
            }
            return NotionProperty(name: name, type: type, options: names, completeOptions: complete)
        })
    }

    public static func decodeTasks(_ data: Data, mapping: NotionMapping) throws -> (tasks: [NotionTask], nextCursor: String?) {
        guard let root = object(data) else { throw IntegrationError.invalidResponse("Task list wasn't JSON.") }
        let tasks = (root["results"] as? [[String: Any]] ?? []).compactMap { task(from: $0, mapping: mapping) }
        return (tasks, root["next_cursor"] as? String)
    }

    public static func decodeTask(_ data: Data, mapping: NotionMapping) throws -> NotionTask? {
        guard let page = object(data) else { throw IntegrationError.invalidResponse("Page wasn't JSON.") }
        return task(from: page, mapping: mapping)
    }

    static func task(from page: [String: Any], mapping: NotionMapping) -> NotionTask? {
        guard page["object"] as? String == "page", let id = page["id"] as? String,
              page["in_trash"] as? Bool != true, page["archived"] as? Bool != true,
              let properties = page["properties"] as? [String: [String: Any]] else { return nil }
        let title = plainText(properties[mapping.titleProperty]?["title"])
        guard !title.isEmpty else { return nil }

        var isDone = false
        var statusName: String?
        if let name = mapping.statusProperty, let property = properties[name], let kind = mapping.statusKind {
            switch kind {
            case .checkbox:
                isDone = property["checkbox"] as? Bool ?? false
            case .status, .select:
                statusName = (property[kind.rawValue] as? [String: Any])?["name"] as? String
                isDone = statusName.map(mapping.doneValues.contains) ?? false
            }
        }
        let due = mapping.dueProperty
            .flatMap { (properties[$0]?["date"] as? [String: Any])?["start"] as? String }
            .flatMap(date(from:))
        let priority = mapping.priorityProperty.flatMap { name -> String? in
            let property = properties[name]
            return ((property?["select"] ?? property?["status"]) as? [String: Any])?["name"] as? String
        }.map(priority(from:)) ?? TaskPriority.none

        return NotionTask(id: id, title: title, url: (page["url"] as? String).flatMap(URL.init(string:)),
                          isDone: isDone, due: due, priority: priority, statusName: statusName)
    }

    /// Reads common priority labels: "High", "P1", "Urgent", "Low", …
    public static func priority(from label: String) -> TaskPriority {
        // Whole words only, so "Someday" isn't read as "med".
        let words = Set(label.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "🔥" }.map(String.init))
        if !words.isDisjoint(with: ["high", "urgent", "critical", "p0", "p1", "asap", "🔥"]) { return .high }
        if !words.isDisjoint(with: ["medium", "med", "normal", "p2"]) { return .medium }
        if !words.isDisjoint(with: ["low", "p3", "p4", "someday", "later"]) { return .low }
        return .none
    }

    // MARK: Helpers

    static func request(_ path: String, method: String = "GET", token: String, json: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(version, forHTTPHeaderField: "Notion-Version")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        return request
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func plainText(_ value: Any?) -> String {
        ((value as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "2026-10-12" (all day, local midnight) or a full ISO-8601 date-time.
    static func date(from text: String) -> Date? {
        if text.count == 10 {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
