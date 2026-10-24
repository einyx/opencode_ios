import Foundation
import Testing
@testable import OpenCodeClient

/// V2 SSE frames translated into the app's V1 event shapes. Frame shapes
/// measured against upstream `v2.1.3`; see `docs/features/v2_support/plan.md`.
struct V2EventTranslationTests {
    private func translate(_ json: String) -> SSEEvent? {
        guard let frame = try? JSONDecoder().decode(V2EventTranslator.Frame.self, from: Data(json.utf8)) else {
            return nil
        }
        return V2EventTranslator.translate(frame)
    }

    private func properties(_ event: SSEEvent?) -> [String: Any] {
        (event?.payload.properties ?? [:]).mapValues(\.value)
    }

    @Test func serverConnectedBecomesTheServerConnectedEvent() throws {
        let event = try #require(translate(#"{"id":"e1","type":"server.connected","data":{}}"#))
        #expect(event.payload.type == "server.connected")
        #expect(event.payload.properties?.isEmpty == true)
    }

    @Test func sessionStatusKeepsItsPayload() throws {
        let json = #"{"id":"e2","type":"session.status","data":{"sessionID":"ses_1","status":{"type":"busy"}}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "session.status")
        let props = properties(event)
        #expect(props["sessionID"] as? String == "ses_1")
        #expect((props["status"] as? [String: Any])?["type"] as? String == "busy")
    }

    @Test func sessionIdleBecomesAnIdleStatus() throws {
        let json = #"{"id":"e3","type":"session.idle","data":{"sessionID":"ses_1"}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "session.status")
        let props = properties(event)
        #expect(props["sessionID"] as? String == "ses_1")
        #expect((props["status"] as? [String: Any])?["type"] as? String == "idle")
    }

    @Test func sessionRenamedAsksForAFreshRead() throws {
        let json = #"{"id":"e4","type":"session.renamed","data":{"sessionID":"ses_1"}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "session.updated")
        let props = properties(event)
        #expect(props["sessionID"] as? String == "ses_1")
        #expect(props["v2Refresh"] as? Bool == true)
    }

    @Test func sessionDeletedCarriesItsSessionID() throws {
        let json = #"{"id":"e5","type":"session.deleted","data":{"sessionID":"ses_1"}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "session.deleted")
        #expect(properties(event)["sessionID"] as? String == "ses_1")
    }

    @Test func textDeltaBecomesAPartDeltaWithAStablePartID() throws {
        let json = #"{"id":"e6","type":"session.text.delta","data":{"sessionID":"ses_1","assistantMessageID":"msg_1","ordinal":0,"delta":"hi"}}"#
        let first = try #require(translate(json))
        #expect(first.payload.type == "message.part.delta")
        let props = properties(first)
        #expect(props["partID"] as? String == "msg_1-text-0")
        #expect(props["field"] as? String == "text")
        #expect(props["delta"] as? String == "hi")

        // The same ordinal yields the same part id, so a reconnect converges.
        let again = try #require(translate(json))
        #expect(properties(again)["partID"] as? String == "msg_1-text-0")
    }

    @Test func textEndedCarriesTheWholeText() throws {
        let json = #"{"id":"e8","type":"session.text.ended","data":{"sessionID":"ses_1","assistantMessageID":"msg_1","ordinal":0,"text":"hi there"}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "message.part.updated")
        let part = properties(event)["part"] as? [String: Any]
        #expect(part?["id"] as? String == "msg_1-text-0")
        #expect(part?["type"] as? String == "text")
        #expect(part?["text"] as? String == "hi there")
    }

    @Test func reasoningDeltaIsIgnored() {
        let json = #"{"id":"e9","type":"session.reasoning.delta","data":{"sessionID":"ses_1","assistantMessageID":"msg_1","ordinal":0,"delta":"..."}}"#
        #expect(translate(json) == nil)
    }

    @Test func messageContentUpdateAsksForAFreshTranscript() throws {
        let json = #"{"id":"e10","type":"session.message.content.updated","data":{"sessionID":"ses_1"}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "message.updated")
    }

    @Test func permissionAskedMapsActionAndResources() throws {
        let json = #"{"id":"e11","type":"permission.asked","data":{"id":"per_1","sessionID":"ses_1","action":"read","resources":["*.env"],"source":{"type":"tool","messageID":"msg_1","id":"call_1"}}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "permission.asked")
        let props = properties(event)
        #expect(props["permission"] as? String == "read")
        #expect(props["patterns"] as? [String] == ["*.env"])
        let tool = props["tool"] as? [String: Any]
        #expect(tool?["callID"] as? String == "call_1")
    }

    @Test func formCreatedBecomesAQuestion() throws {
        let json = #"{"id":"e12","type":"form.created","data":{"form":{"id":"frm_1","sessionID":"ses_1","title":"Pick","fields":[{"key":"color","type":"string","options":[{"value":"red","label":"Red"}]}]}}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "question.asked")
        let props = properties(event)
        #expect(props["id"] as? String == "frm_1")
        let questions = props["questions"] as? [[String: Any]]
        #expect(questions?.first?["header"] as? String == "color")
        let options = questions?.first?["options"] as? [[String: Any]]
        #expect(options?.first?["label"] as? String == "Red")
    }

    @Test func formRepliedRemovesTheCard() throws {
        let json = #"{"id":"e13","type":"form.replied","data":{"id":"frm_1","sessionID":"ses_1"}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "question.rejected")
        #expect(properties(event)["id"] as? String == "frm_1")
    }

    @Test func executionFailedBecomesASessionError() throws {
        let json = #"{"id":"e14","type":"session.execution.failed","data":{"sessionID":"ses_1","error":{"type":"ProviderError","message":"boom"}}}"#
        let event = try #require(translate(json))
        #expect(event.payload.type == "session.error")
        let props = properties(event)
        let error = props["error"] as? [String: Any]
        #expect(error?["name"] as? String == "ProviderError")
        #expect((error?["data"] as? [String: Any])?["message"] as? String == "boom")
    }
}
