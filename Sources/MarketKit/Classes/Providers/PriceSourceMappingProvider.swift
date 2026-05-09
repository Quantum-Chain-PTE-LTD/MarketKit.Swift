import Foundation

struct PriceSourceMapping: Codable {
    let version: Int?
    let ttlSeconds: TimeInterval?
    let coins: [String]
}

protocol PriceSourceMappingProvider {
    func mappedCoinUids() async throws -> Set<String>
}

class CachedPriceSourceMappingProvider: PriceSourceMappingProvider {
    private let cacheURL: URL
    private let mappingURL: URL?
    private let fallbackTtlSeconds: TimeInterval

    init(cacheDirectoryURL: URL, mappingUrl: String, fallbackTtlSeconds: TimeInterval = QcProviderDefaults.mappingCacheTtlSeconds) {
        cacheURL = cacheDirectoryURL.appendingPathComponent("qc-price-source-mapping-cache.json")
        mappingURL = URL(string: mappingUrl)!
        self.fallbackTtlSeconds = fallbackTtlSeconds
    }

    func mappedCoinUids() async throws -> Set<String> {
        let now = Date().timeIntervalSince1970
        let cached = readCache()

        do {
            guard let mappingURL else {
                return cached?.mapping.normalizedCoinUids ?? []
            }

            let mapping = try await JsonHttpClient.fetch(PriceSourceMapping.self, url: mappingURL)
            writeCache(CachedPriceSourceMapping(fetchedAt: now, mapping: mapping))
            return mapping.normalizedCoinUids
        } catch {
            if let cached, !cached.isExpired(now: now, fallbackTtlSeconds: fallbackTtlSeconds) {
                return cached.mapping.normalizedCoinUids
            }

            return cached?.mapping.normalizedCoinUids ?? []
        }
    }

    private func readCache() -> CachedPriceSourceMapping? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            return try JSONDecoder().decode(CachedPriceSourceMapping.self, from: data)
        } catch {
            return nil
        }
    }

    private func writeCache(_ cachedMapping: CachedPriceSourceMapping) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cachedMapping)
            try data.write(to: cacheURL, options: .atomic)
        } catch {}
    }
}

private struct CachedPriceSourceMapping: Codable {
    let fetchedAt: TimeInterval
    let mapping: PriceSourceMapping

    func isExpired(now: TimeInterval, fallbackTtlSeconds: TimeInterval) -> Bool {
        let ttl = mapping.ttlSeconds.flatMap { $0 > 0 ? $0 : nil } ?? fallbackTtlSeconds
        return now - fetchedAt >= ttl
    }
}

private extension PriceSourceMapping {
    var normalizedCoinUids: Set<String> {
        Set(coins.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }
}
