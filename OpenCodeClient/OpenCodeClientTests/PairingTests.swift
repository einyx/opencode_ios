import Foundation
import Testing
@testable import OpenCodeClient

/// `opencode pair` onboarding. The pairing code is redeemed against
/// `GET /auth/connect/:code` with `Accept: application/json`, which returns a
/// session token usable as the Basic-auth password (username `opencode`).
/// Shapes measured against upstream `v2.1.3`.
struct PairingTests {
    @Test func printedPairingLinkIsParsed() throws {
        let link = try #require(PairingLink.parse("http://192.168.190.237:4096/auth/connect/R1ZynR76yZ3G7uoPHlGOiA"))
        #expect(link.code == "R1ZynR76yZ3G7uoPHlGOiA")
        #expect(link.urls == ["http://192.168.190.237:4096"])
    }

    @Test func scannedQRPayloadIsParsed() throws {
        let link = try #require(
            PairingLink.parse(#"{"code":"R1ZynR76yZ3G7uoPHlGOiA","urls":["http://192.168.190.237:4096","http://10.0.0.5:4096"]}"#)
        )
        #expect(link.code == "R1ZynR76yZ3G7uoPHlGOiA")
        #expect(link.urls == ["http://192.168.190.237:4096", "http://10.0.0.5:4096"])
    }

    @Test func linkWithoutConnectPathIsNotAPairingLink() {
        #expect(PairingLink.parse("http://192.168.190.237:4096/session/ses_1") == nil)
        #expect(PairingLink.parse("http://192.168.190.237:4096/auth/connect/") == nil)
        #expect(PairingLink.parse("http://192.168.190.237:4096/auth/connect/abc/extra") == nil)
        #expect(PairingLink.parse("https://example.invalid") == nil)
    }

    @Test func incompleteCodeIsNotAPairingLink() {
        // The server issues 22 character base64url codes. A shorter prefix is
        // what the field holds while a link is still being typed, and
        // redeeming it would spend the single-use code on a typo.
        #expect(PairingLink.parse("http://192.168.190.237:4096/auth/connect/R1ZynR7") == nil)
        #expect(PairingLink.parse(#"{"code":"R1ZynR7","urls":["http://192.168.190.237:4096"]}"#) == nil)
        // A complete code is still accepted.
        #expect(PairingLink.parse("http://192.168.190.237:4096/auth/connect/R1ZynR76yZ3G7uoPHlGOiA") != nil)
    }

    @Test func pairingLinkWithUnsupportedSchemeIsRejected() {
        #expect(PairingLink.parse("opencode-ios://auth/connect/abc") == nil)
    }

    @Test func pairingCodeWithIllegalCharactersIsRejected() {
        #expect(PairingLink.parse("http://192.168.190.237:4096/auth/connect/abc%20def") == nil)
        #expect(PairingLink.parse("http://192.168.190.237:4096/auth/connect/../../etc") == nil)
    }

    @Test func qrPayloadWithNoUsableURLIsRejected() {
        #expect(PairingLink.parse(#"{"code":"abc","urls":[]}"#) == nil)
        #expect(PairingLink.parse(#"{"code":"abc"}"#) == nil)
    }

    @Test func qrPayloadWithNonStringURLIsRejected() {
        #expect(PairingLink.parse(#"{"code":"abc","urls":[7]}"#) == nil)
    }

    @Test func bareServerAddressIsNotAPairingLink() {
        // A host address typed into the pairing field must not be mistaken for
        // a link: the path must be exactly `/auth/connect/<code>`.
        #expect(PairingLink.parse("http://192.168.190.237:4096") == nil)
        #expect(PairingLink.parse("192.168.190.237:4096") == nil)
    }
}
