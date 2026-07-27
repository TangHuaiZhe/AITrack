import Foundation
import Testing
@testable import SignalDesk

struct XClientTests {
    @Test func mapsOfficialTimelineShapeToSignal() throws {
        let json = """
        {
          "data": [{
            "id": "1234567890",
            "text": "I believe robotics agents are the next AI platform.",
            "created_at": "2026-07-27T10:20:30.000Z",
            "public_metrics": {
              "retweet_count": 500,
              "reply_count": 120,
              "like_count": 3000,
              "quote_count": 200
            }
          }]
        }
        """
        let source = TrackedSource.x(
            name: "Example Founder",
            role: "AI founder",
            username: "example",
            topics: ["AI", "robotics", "agents"]
        )

        let events = try XClient().events(
            from: Data(json.utf8),
            user: XUser(id: "42", username: "example"),
            source: source
        )

        #expect(events.count == 1)
        #expect(events[0].category == .viewpoint)
        #expect(events[0].url == "https://x.com/example/status/1234567890")
        #expect(events[0].matchedTopics.count == 3)
        #expect(events[0].summary.contains("喜欢 3,000"))
        #expect(events[0].importance >= 75)
    }
}
