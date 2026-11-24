import Foundation

/// One answer from the web kept in a JSON file: used while it's fresh, asked again after `maxAge`,
/// and used however old when the web can't be reached. "Nothing found" is cached too, as nil.
struct WebCacheFile<Value: Codable & Sendable>: Sendable {
    let url: URL
    let maxAge: TimeInterval

    private struct Stored: Codable {
        var fetched: Date
        var value: Value?
    }

    /// The cached value while fresh, else `fetch`'s (saved), else the old one when `fetch` throws.
    /// `force` asks again however fresh the file is (Refresh Details).
    func value(now: Date, force: Bool = false, fetch: @Sendable () async throws -> Value?) async -> Value? {
        let cached = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(Stored.self, from: $0) }
        if !force, let cached, now.timeIntervalSince(cached.fetched) < maxAge { return cached.value }
        do {
            let value = try await fetch()
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Self.encoder.encode(Stored(fetched: now, value: value)).write(to: url, options: .atomic)
            return value
        } catch {
            return cached?.value
        }
    }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
