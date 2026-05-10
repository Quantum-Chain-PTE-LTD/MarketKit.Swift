import Foundation

class CachedQcCoinMetadataProvider: SupplementalCoinMetadataProvider {
    private let cacheURL: URL
    private let assetListURL: URL?
    private let fallbackTtlSeconds: TimeInterval

    init(
        cacheDirectoryURL: URL, assetListUrl: String,
        fallbackTtlSeconds: TimeInterval = QcProviderDefaults.assetListCacheTtlSeconds
    ) {
        cacheURL = cacheDirectoryURL.appendingPathComponent("qc-asset-list-cache.json")
        assetListURL = URL(string: assetListUrl)!
        self.fallbackTtlSeconds = fallbackTtlSeconds
    }

    func metadata() async throws -> CoinMetadata {
        let now = Date().timeIntervalSince1970
        let cached = readCache()

        do {
            guard let assetListURL else {
                return cachedMetadata(cached: cached, now: now)
            }

            let assetList = try await JsonHttpClient.fetch(QcAssetList.self, url: assetListURL)
            writeCache(CachedQcAssetList(fetchedAt: now, assetList: assetList))
            return assetList.coinMetadata
        } catch {
            return cachedMetadata(cached: cached, now: now)
        }
    }

    private func cachedMetadata(cached: CachedQcAssetList?, now: TimeInterval) -> CoinMetadata {
        if let cached, !cached.isExpired(now: now, fallbackTtlSeconds: fallbackTtlSeconds) {
            return cached.assetList.coinMetadata
        }

        return cached?.assetList.coinMetadata ?? CoinMetadata()
    }

    private func readCache() -> CachedQcAssetList? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            return try JSONDecoder().decode(CachedQcAssetList.self, from: data)
        } catch {
            return nil
        }
    }

    private func writeCache(_ cachedAssetList: CachedQcAssetList) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cachedAssetList)
            try data.write(to: cacheURL, options: .atomic)
        } catch {}
    }
}
private struct CachedQcAssetList: Codable {
    let fetchedAt: TimeInterval
    let assetList: QcAssetList

    func isExpired(now: TimeInterval, fallbackTtlSeconds: TimeInterval) -> Bool {
        let ttl = assetList.ttlSeconds.flatMap { $0 > 0 ? $0 : nil } ?? fallbackTtlSeconds
        return now - fetchedAt >= ttl
    }
}
private struct QcAssetList: Codable {
    let version: Int?
    let ttlSeconds: TimeInterval?
    let coins: [QcAssetCoin]?
    let blockchains: [QcAssetBlockchain]?
    let tokens: [QcAssetToken]?

    var coinMetadata: CoinMetadata {
        CoinMetadata(
            coins: (coins ?? []).compactMap { $0.coin },
            blockchainRecords: (blockchains ?? []).compactMap { $0.blockchainRecord },
            tokenRecords: (tokens ?? []).compactMap { $0.tokenRecord }
        )
    }
}
private struct QcAssetCoin: Codable {
    let uid: String?
    let id: String?
    let name: String?
    let code: String?
    let marketCapRank: Int?
    let coinGeckoId: String?
    let image: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        uid = try container.decodeString(forKeys: "uid", "coin_uid", "coinUid")
        id = try container.decodeString(forKeys: "id")
        name = try container.decodeString(forKeys: "name")
        code = try container.decodeString(forKeys: "code")
        marketCapRank = try container.decodeIfPresent(
            Int.self, forKeys: "market_cap_rank", "marketCapRank")
        coinGeckoId = try container.decodeString(forKeys: "coingecko_id", "coinGeckoId")
        image = try container.decodeString(forKeys: "image", "icon")
    }

    var coin: Coin? {
        guard let uid = (uid ?? id).cleaned, let name = name.cleaned, let code = code.cleaned else {
            return nil
        }

        return Coin(
            uid: uid,
            name: name,
            code: code.uppercased(),
            marketCapRank: marketCapRank,
            coinGeckoId: coinGeckoId.cleaned,
            image: image.cleaned
        )
    }
}
private struct QcAssetBlockchain: Codable {
    let uid: String?
    let name: String?
    let url: String?

    var blockchainRecord: BlockchainRecord? {
        guard let uid = uid.cleaned, let name = name.cleaned else {
            return nil
        }

        return BlockchainRecord(uid: uid, name: name, explorerUrl: url.cleaned)
    }
}
private struct QcAssetToken: Codable {
    let coinUid: String?
    let blockchainUid: String?
    let type: String?
    let decimals: Int?
    let address: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        coinUid = try container.decodeString(forKeys: "coin_uid", "coinUid")
        blockchainUid = try container.decodeString(forKeys: "blockchain_uid", "blockchainUid")
        type = try container.decodeString(forKeys: "type")
        decimals = try container.decodeIfPresent(Int.self, forKeys: "decimals")
        address = try container.decodeString(forKeys: "address", "reference")
    }

    var tokenRecord: TokenRecord? {
        guard let coinUid = coinUid.cleaned, let blockchainUid = blockchainUid.cleaned,
            let type = type.cleaned?.lowercased()
        else {
            return nil
        }

        let reference: String?
        if type == "native" {
            reference = nil
        } else {
            guard let address = address.cleaned else {
                return nil
            }
            reference = address
        }

        return TokenRecord(
            coinUid: coinUid, blockchainUid: blockchainUid, type: type, decimals: decimals,
            reference: reference)
    }
}
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
extension KeyedDecodingContainer where K == AnyCodingKey {
    fileprivate func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: String...) throws
        -> T?
    {
        try decodeIfPresent(type, forKeys: keys)
    }

    fileprivate func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [String]) throws
        -> T?
    {
        for key in keys {
            guard let codingKey = AnyCodingKey(stringValue: key), contains(codingKey) else {
                continue
            }

            if let value = try decodeIfPresent(type, forKey: codingKey) {
                return value
            }
        }

        return nil
    }

    fileprivate func decodeString(forKeys keys: String...) throws -> String? {
        try decodeIfPresent(String.self, forKeys: keys)
    }
}
extension Optional where Wrapped == String {
    fileprivate var cleaned: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else {
            return nil
        }

        return value
    }
}
