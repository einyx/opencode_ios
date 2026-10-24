import Foundation

/// Translates OpenCode V2 SSE frames into the app's V1 event shapes.
///
/// V2 publishes `{"id":…,"type":…,"data":…}` frames with its own event names.
/// The app's SSE handlers already know the V1 names and property shapes, so
/// the translation happens here: the handler code stays unchanged and the
/// MessageStore keeps seeing the parts it expects.
///
/// Event names measured against upstream `v2.1.3`; see
/// `docs/features/v2_support/plan.md`.
nonisolated enum V2EventTranslator {
    /// A V2 frame.
    struct Frame: Decodable {
        let id: String?
        let type: String
        let data: [String: AnyCodable]?

        /// The frame data as plain values.
        var values: [String: Any] {
            (data ?? [:]).mapValues(\.value)
        }
    }

    /// Translate one V2 frame. Returns `nil` for a frame the app ignores.
    static func translate(_ frame: Frame) -> SSEEvent? {
        let data = frame.values
        switch frame.type {
        case "server.connected":
            return event(type: "server.connected", properties: [:])

        case "session.status":
            // `data` already carries `sessionID` and `status`.
            return event(type: "session.status", properties: data)

        case "session.idle":
            return event(
                type: "session.status",
                properties: [
                    "sessionID": data["sessionID"] as Any,
                    "status": ["type": "idle"],
                ]
            )

        case "session.created", "session.renamed", "session.metadata.updated":
            // V2 does not send the session body: the app reads it back.
            return event(
                type: "session.updated",
                properties: [
                    "sessionID": data["sessionID"] as Any,
                    "v2Refresh": true,
                ]
            )

        case "session.deleted":
            return event(type: "session.deleted", properties: data)

        case "session.text.started":
            guard let part = textPart(data, text: nil) else { return nil }
            return event(
                type: "message.part.updated",
                properties: [
                    "sessionID": data["sessionID"] as Any,
                    "messageID": data["assistantMessageID"] as Any,
                    "part": part,
                ]
            )

        case "session.text.delta":
            guard let partID = textPartID(data) else { return nil }
            return event(
                type: "message.part.delta",
                properties: [
                    "sessionID": data["sessionID"] as Any,
                    "messageID": data["assistantMessageID"] as Any,
                    "partID": partID,
                    "field": "text",
                    "delta": data["delta"] as Any,
                ]
            )

        case "session.text.ended":
            guard let part = textPart(data, text: data["text"] as? String) else { return nil }
            return event(
                type: "message.part.updated",
                properties: [
                    "sessionID": data["sessionID"] as Any,
                    "messageID": data["assistantMessageID"] as Any,
                    "part": part,
                ]
            )

        case "session.reasoning.ended", "session.message.content.updated":
            // No part of its own: the app reloads the transcript.
            return event(type: "message.updated", properties: [:])

        case "permission.asked":
            return event(type: "permission.asked", properties: permissionProperties(data))

        case "permission.replied":
            return event(type: "permission.replied", properties: data)

        case "form.created":
            guard let form = data["form"] as? [String: Any] else { return nil }
            return event(type: "question.asked", properties: formProperties(form))

        case "form.replied", "form.cancelled":
            return event(
                type: "question.rejected",
                properties: ["id": data["id"] as Any]
            )

        case "session.execution.failed":
            let error = data["error"] as? [String: Any] ?? [:]
            return event(
                type: "session.error",
                properties: [
                    "sessionID": data["sessionID"] as Any,
                    "error": [
                        "name": error["type"] as Any,
                        "data": ["message": error["message"] as Any],
                    ],
                ]
            )

        default:
            // `session.reasoning.delta` and every other event the app does
            // not render.
            return nil
        }
    }

    // MARK: - Helpers

    private static func event(type: String, properties: [String: Any]) -> SSEEvent {
        let wrapped = properties.mapValues { AnyCodable($0) }
        return SSEEvent(directory: nil, payload: SSEPayload(type: type, properties: wrapped))
    }

    /// The part id for a text part: the assistant message id plus the ordinal.
    /// The same ordinal always yields the same id, including after a
    /// reconnect.
    private static func textPartID(_ data: [String: Any]) -> String? {
        guard let messageID = data["assistantMessageID"] as? String else { return nil }
        guard let ordinal = data["ordinal"] as? Int else { return nil }
        return "\(messageID)-text-\(ordinal)"
    }

    private static func textPart(_ data: [String: Any], text: String?) -> [String: Any]? {
        guard let partID = textPartID(data),
              let messageID = data["assistantMessageID"] as? String else {
            return nil
        }
        var part: [String: Any] = [
            "type": "text",
            "id": partID,
            "messageID": messageID,
        ]
        if let sessionID = data["sessionID"] as? String {
            part["sessionID"] = sessionID
        }
        if let text {
            part["text"] = text
        }
        return part
    }

    /// V2 names the permission `action` and its targets `resources`; the app
    /// expects `permission` and `patterns`.
    private static func permissionProperties(_ data: [String: Any]) -> [String: Any] {
        var properties: [String: Any] = data
        if let action = data["action"] as? String {
            properties["permission"] = action
        }
        if let resources = data["resources"] as? [String] {
            properties["patterns"] = resources
        }
        if let source = data["source"] as? [String: Any] {
            var tool: [String: Any] = [:]
            if let messageID = source["messageID"] as? String { tool["messageID"] = messageID }
            if let callID = source["id"] as? String { tool["callID"] = callID }
            properties["tool"] = tool
        }
        return properties
    }

    /// A V2 form becomes the app's question request shape.
    private static func formProperties(_ form: [String: Any]) -> [String: Any] {
        var properties: [String: Any] = form
        guard let fields = form["fields"] as? [[String: Any]] else { return properties }
        let questions = fields.compactMap { field -> [String: Any]? in
            guard let key = field["key"] as? String else { return nil }
            let options = (field["options"] as? [[String: Any]] ?? []).map { option in
                [
                    "label": option["label"] as Any,
                    "description": option["description"] as Any,
                ]
            }
            var question: [String: Any] = [
                "question": (field["title"] as? String) ?? key,
                "header": key,
                "options": options,
            ]
            if field["type"] as? String == "multiselect" {
                question["multiple"] = true
            }
            return question
        }
        properties["questions"] = questions
        return properties
    }
}
