import Foundation
import Testing
@testable import SignalDesk

struct XClientTests {
    @Test func mapsTwitterAPIIOResponseToSignal() throws {
        let json = """
        {
          "tweets": [{
            "id": "1234567890",
            "text": "I believe robotics agents are the next AI platform.",
            "createdAt": "Mon Jul 27 10:20:30 +0000 2026",
            "retweetCount": 500,
            "replyCount": 120,
            "likeCount": 3000,
            "quoteCount": 200
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
            username: "example",
            source: source
        )

        #expect(events.count == 1)
        #expect(events[0].category == .viewpoint)
        #expect(events[0].url == "https://x.com/example/status/1234567890")
        #expect(events[0].matchedTopics.count == 3)
        #expect(events[0].summary.contains("喜欢 3,000"))
        #expect(events[0].importance >= 75)
    }

    @Test func buildsIncrementalSearchWithOverlap() throws {
        let lastCheckedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let url = XClient.searchURL(username: "example", lastCheckedAt: lastCheckedAt)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(
            components.queryItems?.first(where: { $0.name == "query" })?.value
        )

        #expect(url.host == "api.twitterapi.io")
        #expect(query.contains("from:example"))
        #expect(query.contains("-filter:replies"))
        #expect(query.contains("-filter:retweets"))
        #expect(query.contains("since_time:1799999700"))
        #expect(components.queryItems?.first(where: { $0.name == "queryType" })?.value == "Latest")
    }

    @Test func mapsBrightDataPostsAndExcludesRepliesFromOtherAccounts() throws {
        let json = """
        [
          {
            "id": "100",
            "user_posted": "example",
            "description": "AI chips and robotics are converging.",
            "date_posted": "2026-08-04T08:30:00Z",
            "url": "https://x.com/example/status/100",
            "replies": 12,
            "reposts": 34,
            "likes": 567,
            "quotes": 8,
            "parent_post_details": { "post_id": "100" }
          },
          {
            "id": "102",
            "user_posted": "example",
            "description": "This is a reply.",
            "date_posted": "2026-08-04T08:10:00Z",
            "parent_post_details": { "post_id": "99" }
          }
        ]
        """
        var source = TrackedSource.x(
            name: "Example Founder",
            role: "AI founder",
            username: "example",
            topics: ["AI", "robotics"]
        )
        source.lastCheckedAt = Date()

        let result = try XClient(provider: .brightData).brightDataEvents(
            from: Data(json.utf8),
            sources: [source]
        )
        let events = try #require(result[source.id])

        #expect(events.count == 1)
        #expect(events[0].url == "https://x.com/example/status/100")
        #expect(events[0].title == "AI chips and robotics are converging.")
        #expect(events[0].summary.contains("喜欢 567"))
        #expect(events[0].matchedTopics.count == 2)
    }

    @Test func buildsBrightDataProfileDiscoveryURL() throws {
        let components = try #require(
            URLComponents(url: XClient.brightDataURL, resolvingAgainstBaseURL: false)
        )

        #expect(XClient.brightDataURL.host == "api.brightdata.com")
        #expect(XClient.brightDataURL.path == "/datasets/v3/scrape")
        #expect(components.queryItems?.first(where: { $0.name == "dataset_id" })?.value == "gd_lwxkxvnf1cynvib9co")
        #expect(components.queryItems?.first(where: { $0.name == "type" })?.value == "discover_new")
        #expect(components.queryItems?.first(where: { $0.name == "discover_by" })?.value == "profiles_array")
        #expect(components.queryItems?.first(where: { $0.name == "limit_per_input" })?.value == "20")
    }

    @Test func buildsBrightDataProfilesArrayRequest() throws {
        let body = try XClient.brightDataRequestBody(usernames: ["karpathy", "RayDalio"])
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let inputs = try #require(json["input"] as? [[String: Any]])

        #expect(inputs.count == 1)
        #expect(inputs[0]["urls"] as? [String] == [
            "https://x.com/karpathy",
            "https://x.com/RayDalio"
        ])
        #expect(inputs[0]["url"] == nil)
    }

    @Test func buildsBrightDataSnapshotURLs() {
        let progress = XClient.brightDataProgressURL(snapshotID: "sd_example")
        let snapshot = XClient.brightDataSnapshotURL(snapshotID: "sd_example")
        let components = URLComponents(url: snapshot, resolvingAgainstBaseURL: false)

        #expect(progress.absoluteString == "https://api.brightdata.com/datasets/v3/progress/sd_example")
        #expect(snapshot.path == "/datasets/v3/snapshot/sd_example")
        #expect(components?.queryItems?.first(where: { $0.name == "format" })?.value == "json")
    }

    @Test func decodesBrightDataSnapshotEnvelope() throws {
        let data = Data(#"{"snapshot_id":"sd_example","message":"still running"}"#.utf8)

        #expect(try XClient.brightDataSnapshotID(from: data) == "sd_example")
    }

    @Test func surfacesBrightDataCrawlerError() throws {
        let data = Data(#"[{"error":"Crawler error: selector timeout"}]"#.utf8)
        let source = TrackedSource.x(
            name: "Example",
            role: "AI",
            username: "example",
            topics: ["AI"]
        )

        #expect(throws: XError.self) {
            try XClient(provider: .brightData).brightDataEvents(
                from: data,
                sources: [source]
            )
        }
    }
}
