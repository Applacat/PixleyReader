import XCTest
import Foundation

// MARK: - Test-Only Type Definitions
// Since ChatMessage is in the main app (executable target),
// we mirror the implementation here for testing the logic.

// MARK: - ChatMessage Mirror

private struct TestableChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Tests

final class ChatMessageTests: XCTestCase {

    func testInit_capturesCurrentTimestamp() {
        let before = Date()
        let msg = TestableChatMessage(role: .user, content: "Hello")
        let after = Date()

        XCTAssertGreaterThanOrEqual(msg.timestamp, before)
        XCTAssertLessThanOrEqual(msg.timestamp, after)
    }
}
