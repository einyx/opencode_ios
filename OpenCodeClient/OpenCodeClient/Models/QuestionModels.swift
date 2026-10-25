//
//  QuestionModels.swift
//  OpenCodeClient
//

import Foundation

nonisolated struct QuestionOption: Codable, Identifiable {
    var id: String { label }
    let label: String
    let description: String
}

nonisolated struct QuestionInfo: Codable, Identifiable {
    var id: String { header }
    let question: String
    let header: String
    let options: [QuestionOption]
    let multiple: Bool?
    let custom: Bool?

    var allowMultiple: Bool { multiple ?? false }
    var allowCustom: Bool { custom ?? true }
}

nonisolated struct QuestionRequest: Codable, Identifiable {
    let id: String
    let sessionID: String
    let questions: [QuestionInfo]
    let tool: ToolRef?

    struct ToolRef: Codable {
        let messageID: String
        let callID: String
    }
}
