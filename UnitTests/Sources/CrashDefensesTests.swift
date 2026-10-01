//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

/// Tests for `Other/Stability/CrashDefenses`. Pure logic, no mocks needed.
@MainActor
struct CrashDefensesTests {
    // MARK: - SafeAccess
    
    @Test
    func clampedRange() {
        let items = ["a", "b", "c"]
        
        #expect(Array(items[items.clamped(0..<2)]) == ["a", "b"])
        // Out-of-bounds ranges collapse instead of trapping.
        #expect(Array(items[items.clamped(0..<99)]).count == 3)
        #expect(items[items.clamped(99..<100)].isEmpty)
        #expect(items[items.clamped(2..<1)].isEmpty)
    }
    
    @Test
    func clampedIndex() {
        let items = ["a", "b", "c"]
        
        #expect(items.clampedIndex(1) == 1)
        #expect(items.clampedIndex(-5) == 0)
        #expect(items.clampedIndex(99) == 2)
        #expect([String]().clampedIndex(0) == nil)
    }
    
    @Test
    func safeRemovals() {
        var items = ["a", "b"]
        
        #expect(items.removeFirstSafely() == "a")
        #expect(items.removeLastSafely() == "b")
        #expect(items.removeFirstSafely() == nil)
        #expect(items.removeLastSafely() == nil)
        #expect(items.isEmpty)
    }
    
    // MARK: - MessageRenderingGuards
    
    @Test
    func nonBlank() {
        #expect(MessageRenderingGuards.nonBlank("hello") == "hello")
        #expect(MessageRenderingGuards.nonBlank(nil) == nil)
        #expect(MessageRenderingGuards.nonBlank("") == nil)
        #expect(MessageRenderingGuards.nonBlank("   \n  ") == nil)
    }
    
    @Test
    func urlFromString() {
        #expect(MessageRenderingGuards.url(from: "https://example.com")?.absoluteString == "https://example.com")
        #expect(MessageRenderingGuards.url(from: nil) == nil)
        #expect(MessageRenderingGuards.url(from: "") == nil)
        #expect(MessageRenderingGuards.url(from: "   ") == nil)
    }
    
    @Test
    func renderableSize() {
        #expect(MessageRenderingGuards.isRenderable(CGSize(width: 100, height: 100)))
        #expect(!MessageRenderingGuards.isRenderable(nil))
        #expect(!MessageRenderingGuards.isRenderable(.zero))
        #expect(!MessageRenderingGuards.isRenderable(CGSize(width: -1, height: 10)))
        #expect(!MessageRenderingGuards.isRenderable(CGSize(width: .infinity, height: 10)))
        #expect(!MessageRenderingGuards.isRenderable(CGSize(width: .nan, height: 10)))
    }
    
    @Test
    func clampedAspectRatio() {
        #expect(MessageRenderingGuards.clampedAspectRatio(1.5) == 1.5)
        #expect(MessageRenderingGuards.clampedAspectRatio(0.001) == 0.1)
        #expect(MessageRenderingGuards.clampedAspectRatio(1000) == 10)
        #expect(MessageRenderingGuards.clampedAspectRatio(nil) == nil)
        #expect(MessageRenderingGuards.clampedAspectRatio(0) == nil)
        #expect(MessageRenderingGuards.clampedAspectRatio(-2) == nil)
        #expect(MessageRenderingGuards.clampedAspectRatio(.nan) == nil)
    }
    
    @Test
    func validBlurhash() {
        #expect(MessageRenderingGuards.validBlurhash("LEHV6nWB2yk8pyo0adR*.7kCMdnj") != nil)
        #expect(MessageRenderingGuards.validBlurhash("") == nil)
        #expect(MessageRenderingGuards.validBlurhash(nil) == nil)
    }
    
    // MARK: - EventDecodingGuards
    
    @Test
    func decodeJSON() {
        struct Payload: Decodable, Equatable {
            let name: String
        }
        
        #expect(EventDecodingGuards.decode(Payload.self, from: #"{"name":"holm"}"#) == Payload(name: "holm"))
        #expect(EventDecodingGuards.decode(Payload.self, from: "{oops") == nil)
        #expect(EventDecodingGuards.decode(Payload.self, from: #"{"name":42}"#) == nil)
    }
    
    @Test
    func decodeSafelyWithDefault() throws {
        struct Payload: Decodable {
            let name: String
            let count: Int
            
            enum CodingKeys: String, CodingKey {
                case name, count
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = container.decodeSafely(String.self, forKey: .name, default: "unknown")
                count = container.decodeSafely(Int.self, forKey: .count, default: 0)
            }
        }
        
        let malformed = try #require(EventDecodingGuards.decode(Payload.self, from: #"{"name":42,"count":"many"}"#))
        #expect(malformed.name == "unknown")
        #expect(malformed.count == 0)
        
        let missing = try #require(EventDecodingGuards.decode(Payload.self, from: "{}"))
        #expect(missing.name == "unknown")
        #expect(missing.count == 0)
    }
    
    // MARK: - MainThreadGuard
    
    @Test
    func reportsMainThread() {
        // This test struct is @MainActor, so this is deterministic.
        #expect(MainThreadGuard.isMainThread)
    }
    
    @Test
    func doesNotFireOffMainThread() async {
        await Task.detached {
            // Would assert (in DEBUG) if this ran on the main thread.
            MainThreadGuard.assertNotOnMainThread()
        }.value
    }
    
    // MARK: - CrashBreadcrumbs
    
    @Test
    func recordsAndReadsBackPreviousSession() {
        let url = Self.temporaryFileURL()
        let breadcrumbs = CrashBreadcrumbs(fileURL: url)
        
        #expect(breadcrumbs.previousSessionBreadcrumbs().isEmpty)
        
        breadcrumbs.record(screen: "chats")
        breadcrumbs.record(action: "timeline.paginate.back")
        breadcrumbs.flush()
        
        let readBack = CrashBreadcrumbs(fileURL: url).previousSessionBreadcrumbs()
        #expect(readBack.count == 2)
        #expect(readBack[0].hasSuffix("screen:chats"))
        #expect(readBack[1].hasSuffix("action:timeline.paginate.back"))
    }
    
    @Test
    func clearsAfterReading() {
        let url = Self.temporaryFileURL()
        let breadcrumbs = CrashBreadcrumbs(fileURL: url)
        breadcrumbs.record("one")
        breadcrumbs.flush()
        
        #expect(CrashBreadcrumbs(fileURL: url).previousSessionBreadcrumbs().count == 1)
        #expect(CrashBreadcrumbs(fileURL: url).previousSessionBreadcrumbs().isEmpty)
    }
    
    @Test
    func capsEntries() {
        let url = Self.temporaryFileURL()
        let breadcrumbs = CrashBreadcrumbs(fileURL: url)
        for index in 0..<300 {
            breadcrumbs.record("event-\(index)")
        }
        breadcrumbs.flush()
        
        let readBack = CrashBreadcrumbs(fileURL: url).previousSessionBreadcrumbs()
        #expect(readBack.count == 128)
        #expect(readBack.last?.hasSuffix("event-299") == true)
    }
    
    // MARK: - Private
    
    private static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}
