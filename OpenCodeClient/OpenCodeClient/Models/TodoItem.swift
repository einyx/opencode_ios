//
//  TodoItem.swift
//  OpenCodeClient
//

import Foundation

nonisolated struct TodoItem: Codable, Identifiable, Hashable {
    let content: String
    let status: String
    let priority: String
    let id: String

    private enum CodingKeys: String, CodingKey {
        case content
        case status
        case priority
        case id
        case completed
        case isCompleted
    }

    init(content: String, status: String, priority: String, id: String) {
        self.content = content
        self.status = status
        self.priority = priority
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let decodedContent = (try? c.decode(String.self, forKey: .content))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedContent = decodedContent.isEmpty ? "Untitled todo" : decodedContent

        let decodedStatus: String = {
            if let status = (try? c.decode(String.self, forKey: .status))?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
                return status
            }
            if let completed = try? c.decode(Bool.self, forKey: .completed) {
                return completed ? "completed" : "pending"
            }
            if let completed = try? c.decode(Bool.self, forKey: .isCompleted) {
                return completed ? "completed" : "pending"
            }
            return "pending"
        }()

        let decodedPriority = (try? c.decode(String.self, forKey: .priority))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPriority = (decodedPriority?.isEmpty == false) ? decodedPriority! : "medium"

        let decodedID = (try? c.decode(String.self, forKey: .id))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = (decodedID?.isEmpty == false) ? decodedID! : UUID().uuidString

        self.content = normalizedContent
        self.status = decodedStatus
        self.priority = normalizedPriority
        self.id = normalizedID
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(content, forKey: .content)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encode(id, forKey: .id)
    }

    var isCompleted: Bool {
        status == "completed" || status == "cancelled"
    }
}
