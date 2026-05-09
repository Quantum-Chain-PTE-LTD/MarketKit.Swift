import Foundation
import GRDB
import HsToolKit

extension Kit {
    private static let dataDirectoryName = "market-kit"
    private static let databaseFileName = "market-kit"

    public static func instance(hsApiBaseUrl: String, cryptoCompareApiKey: String? = nil, hsProviderApiKey: String? = nil, minLogLevel: Logger.Level = .error, qcApiBaseUrl: String? = nil, qcApiKey: String? = nil, qcAssetListUrl: String? = nil) throws -> Kit {
        let logger = Logger(minLogLevel: minLogLevel)
        let reachabilityManager = ReachabilityManager()
        let networkManager = NetworkManager(logger: logger)

        let dataDirectoryURL = try dataDirectoryUrl()
        let databaseURL = dataDirectoryURL.appendingPathComponent("\(databaseFileName).sqlite")
        let cacheDirectoryURL = dataDirectoryURL.appendingPathComponent("cache", isDirectory: true)
        let dbPool = try DatabasePool(path: databaseURL.path)
        let coinStorage = try CoinStorage(dbPool: dbPool)

        let syncerStateStorage = try SyncerStateStorage(dbPool: dbPool)

        let cryptoCompareProvider = CryptoCompareProvider(networkManager: networkManager, apiKey: cryptoCompareApiKey)
        let hsProvider = HsProvider(baseUrl: hsApiBaseUrl, networkManager: networkManager, apiKey: hsProviderApiKey)
        let hsNftProvider = HsNftProvider(baseUrl: hsApiBaseUrl, networkManager: networkManager, apiKey: hsProviderApiKey)

        let coinPriceProvider: CoinPriceProvider
        let supplementalMetadataProvider: SupplementalCoinMetadataProvider?

        if let qcApiBaseUrl = qcApiBaseUrl.nonBlank, let qcApiKey = qcApiKey.nonBlank {
            coinPriceProvider = RoutedCoinPriceProvider(
                hsProvider: hsProvider,
                qcProvider: QcCoinPriceProvider(
                    baseUrl: qcApiBaseUrl,
                    apiVersion: QcProviderDefaults.apiVersion,
                    apiKey: qcApiKey,
                    networkManager: networkManager
                ),
                priceSourceMappingProvider: CachedPriceSourceMappingProvider(
                    cacheDirectoryURL: cacheDirectoryURL,
                    mappingUrl: QcProviderDefaults.priceSourceMappingUrl,
                    fallbackTtlSeconds: QcProviderDefaults.mappingCacheTtlSeconds
                )
            )

            supplementalMetadataProvider = CachedQcCoinMetadataProvider(
                cacheDirectoryURL: cacheDirectoryURL,
                assetListUrl: qcAssetListUrl.nonBlank ?? QcProviderDefaults.assetListUrl,
                fallbackTtlSeconds: QcProviderDefaults.assetListCacheTtlSeconds
            )
        } else {
            coinPriceProvider = hsProvider
            supplementalMetadataProvider = nil
        }

        let coinManager = CoinManager(storage: coinStorage, hsProvider: hsProvider)
        let nftManager = NftManager(coinManager: coinManager, provider: hsNftProvider)
        let marketOverviewManager = MarketOverviewManager(nftManager: nftManager, hsProvider: hsProvider)

        let coinSyncer = CoinSyncer(storage: coinStorage, hsProvider: hsProvider, syncerStateStorage: syncerStateStorage, supplementalMetadataProvider: supplementalMetadataProvider)
        let hsDataSyncer = HsDataSyncer(coinSyncer: coinSyncer, hsProvider: hsProvider)

        let coinPriceStorage = try CoinPriceStorage(dbPool: dbPool)
        let coinPriceManager = CoinPriceManager(storage: coinPriceStorage)
        let coinPriceSchedulerFactory = CoinPriceSchedulerFactory(manager: coinPriceManager, provider: coinPriceProvider, reachabilityManager: reachabilityManager, logger: logger)
        let coinPriceSyncManager = CoinPriceSyncManager(schedulerFactory: coinPriceSchedulerFactory)
        coinPriceManager.delegate = coinPriceSyncManager

        let coinHistoricalPriceStorage = try CoinHistoricalPriceStorage(dbPool: dbPool)
        let coinHistoricalPriceManager = CoinHistoricalPriceManager(storage: coinHistoricalPriceStorage, hsProvider: hsProvider)

        let postManager = PostManager(provider: cryptoCompareProvider)

        let globalMarketInfoStorage = try GlobalMarketInfoStorage(dbPool: dbPool)
        let globalMarketInfoManager = GlobalMarketInfoManager(provider: hsProvider, storage: globalMarketInfoStorage)

        return Kit(
            coinManager: coinManager,
            nftManager: nftManager,
            marketOverviewManager: marketOverviewManager,
            hsDataSyncer: hsDataSyncer,
            coinSyncer: coinSyncer,
            coinPriceManager: coinPriceManager,
            coinPriceSyncManager: coinPriceSyncManager,
            coinHistoricalPriceManager: coinHistoricalPriceManager,
            postManager: postManager,
            globalMarketInfoManager: globalMarketInfoManager,
            hsProvider: hsProvider
        )
    }

    private static func dataDirectoryUrl() throws -> URL {
        let fileManager = FileManager.default

        let url = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(dataDirectoryName, isDirectory: true)

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        return url
    }
}

private extension Optional where Wrapped == String {
    var nonBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
