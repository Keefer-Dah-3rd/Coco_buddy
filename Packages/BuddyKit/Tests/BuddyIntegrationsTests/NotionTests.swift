import Foundation
import Testing
import BuddyCore
@testable import BuddyIntegrations

@Suite struct NotionTests {
    let schemaJSON = #"""
    {"object": "data_source", "id": "ds1", "title": [{"plain_text": "Tasks"}],
     "properties": {
       "Name": {"id": "title", "name": "Name", "type": "title", "title": {}},
       "Status": {"id": "s", "name": "Status", "type": "status", "status": {
          "options": [{"id": "1", "name": "Not started"}, {"id": "2", "name": "In progress"}, {"id": "3", "name": "Done"}, {"id": "4", "name": "Archived"}],
          "groups": [{"name": "To-do", "option_ids": ["1"]}, {"name": "In progress", "option_ids": ["2"]}, {"name": "Complete", "option_ids": ["3", "4"]}]}},
       "Due date": {"id": "d", "name": "Due date", "type": "date", "date": {}},
       "Priority": {"id": "p", "name": "Priority", "type": "select", "select": {"options": [{"name": "High"}, {"name": "Low"}]}},
       "Notes": {"id": "n", "name": "Notes", "type": "rich_text", "rich_text": {}}
     }}
    """#

    var source: NotionDataSource { NotionDataSource(id: "ds1", title: "Tasks") }

    @Test func suggestsAMappingFromTheSchema() throws {
        let schema = try NotionAPI.decodeSchema(Data(schemaJSON.utf8))
        let mapping = try #require(NotionMapping.suggested(for: source, schema: schema))
        #expect(mapping.titleProperty == "Name")
        #expect(mapping.statusProperty == "Status" && mapping.statusKind == .status)
        #expect(mapping.doneValues == ["Done", "Archived"] && mapping.doneValue == "Done")
        #expect(mapping.dueProperty == "Due date")
        #expect(mapping.priorityProperty == "Priority")
        #expect(mapping.canWriteCompletion && !mapping.writeBackEnabled)
    }

    @Test func schemaWithoutTitleCantBeMapped() throws {
        let schema = NotionSchema(properties: [NotionProperty(name: "Due", type: "date")])
        #expect(NotionMapping.suggested(for: source, schema: schema) == nil)
    }

    @Test func checkboxDatabasesWorkToo() {
        let schema = NotionSchema(properties: [NotionProperty(name: "Task", type: "title"),
                                               NotionProperty(name: "Done?", type: "checkbox")])
        let mapping = NotionMapping.suggested(for: source, schema: schema)!
        #expect(mapping.statusKind == .checkbox && mapping.canWriteCompletion)
        let request = NotionAPI.markDoneRequest(pageID: "p1", mapping: mapping, token: "t")!
        #expect(String(data: request.httpBody!, encoding: .utf8) == #"{"properties":{"Done?":{"checkbox":true}}}"#)
    }

    @Test func decodesTasksWithTheMapping() throws {
        let schema = try NotionAPI.decodeSchema(Data(schemaJSON.utf8))
        let mapping = NotionMapping.suggested(for: source, schema: schema)!
        let pages = #"""
        {"object": "list", "has_more": true, "next_cursor": "c2", "results": [
          {"object": "page", "id": "p1", "url": "https://www.notion.so/p1", "properties": {
            "Name": {"type": "title", "title": [{"plain_text": "Write "}, {"plain_text": "case study"}]},
            "Status": {"type": "status", "status": {"name": "In progress"}},
            "Due date": {"type": "date", "date": {"start": "2026-10-12", "end": null}},
            "Priority": {"type": "select", "select": {"name": "High"}}}},
          {"object": "page", "id": "p2", "properties": {
            "Name": {"type": "title", "title": [{"plain_text": "Ship it"}]},
            "Status": {"type": "status", "status": {"name": "Done"}},
            "Due date": {"type": "date", "date": null},
            "Priority": {"type": "select", "select": null}}},
          {"object": "page", "id": "p3", "in_trash": true, "properties": {"Name": {"type": "title", "title": [{"plain_text": "Gone"}]}}},
          {"object": "page", "id": "p4", "properties": {"Name": {"type": "title", "title": []}}}
        ]}
        """#
        let (tasks, cursor) = try NotionAPI.decodeTasks(Data(pages.utf8), mapping: mapping)
        #expect(cursor == "c2")
        #expect(tasks.map(\.id) == ["p1", "p2"])
        #expect(tasks[0].title == "Write case study" && !tasks[0].isDone && tasks[0].priority == .high)
        #expect(Calendar.current.component(.day, from: tasks[0].due!) == 12)
        #expect(tasks[1].isDone && tasks[1].due == nil && tasks[1].priority == .none)
        #expect(tasks[0].makeTask().external == ExternalTaskRef(source: .notion, id: "p1", url: URL(string: "https://www.notion.so/p1")))
    }

    @Test func queryAsksForOpenTasksOnly() throws {
        let schema = try NotionAPI.decodeSchema(Data(schemaJSON.utf8))
        let mapping = NotionMapping.suggested(for: source, schema: schema)!
        let request = NotionAPI.queryOpenTasksRequest(mapping: mapping, token: "secret")
        #expect(request.httpMethod == "POST")
        #expect(request.url!.absoluteString == "https://api.notion.com/v1/data_sources/ds1/query")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2025-09-03")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let clauses = try #require((body["filter"] as? [String: Any])?["and"] as? [[String: Any]])
        #expect(clauses.count == 2)
    }

    @Test func markDoneUsesTheMappedStatusValue() throws {
        let schema = try NotionAPI.decodeSchema(Data(schemaJSON.utf8))
        let mapping = NotionMapping.suggested(for: source, schema: schema)!
        let request = try #require(NotionAPI.markDoneRequest(pageID: "p1", mapping: mapping, token: "t"))
        #expect(request.httpMethod == "PATCH")
        #expect(request.url!.absoluteString == "https://api.notion.com/v1/pages/p1")
        #expect(String(data: request.httpBody!, encoding: .utf8) == #"{"properties":{"Status":{"status":{"name":"Done"}}}}"#)
    }

    @Test func searchListsDataSourcesAndIdentityIsReadable() throws {
        let search = #"""
        {"results": [{"object": "data_source", "id": "ds1", "title": [{"plain_text": "Tasks"}]},
                     {"object": "data_source", "id": "ds2", "title": [], "in_trash": true},
                     {"object": "page", "id": "x"}], "next_cursor": null}
        """#
        let (sources, cursor) = try NotionAPI.decodeDataSources(Data(search.utf8))
        #expect(sources == [NotionDataSource(id: "ds1", title: "Tasks")] && cursor == nil)
        #expect(NotionAPI.decodeIdentity(Data(#"{"type": "bot", "bot": {"workspace_name": "Keefer's Notion"}}"#.utf8)) == "Keefer's Notion")
    }

    @Test func readsCommonPriorityLabels() {
        #expect(NotionAPI.priority(from: "P1 – Urgent") == .high)
        #expect(NotionAPI.priority(from: "Medium") == .medium)
        #expect(NotionAPI.priority(from: "Someday") == .low)
        #expect(NotionAPI.priority(from: "Blue") == TaskPriority.none)
    }
}
