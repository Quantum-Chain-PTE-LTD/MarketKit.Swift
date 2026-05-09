import Foundation

protocol CoinPriceProvider {
    func coinPrices(coinUids: [String], currencyCode: String) async throws -> [CoinPrice]
}

extension HsProvider: CoinPriceProvider {}

class RoutedCoinPriceProvider: CoinPriceProvider {
    private let hsProvider: CoinPriceProvider
    private let qcProvider: CoinPriceProvider?
    private let priceSourceMappingProvider: PriceSourceMappingProvider?

    init(hsProvider: CoinPriceProvider, qcProvider: CoinPriceProvider?, priceSourceMappingProvider: PriceSourceMappingProvider?) {
        self.hsProvider = hsProvider
        self.qcProvider = qcProvider
        self.priceSourceMappingProvider = priceSourceMappingProvider
    }

    func coinPrices(coinUids: [String], currencyCode: String) async throws -> [CoinPrice] {
        let requestedCoinUids = coinUids.uniqueOrdered()
        guard !requestedCoinUids.isEmpty else {
            return []
        }

        guard let qcProvider, let priceSourceMappingProvider else {
            return try await hsProvider.coinPrices(coinUids: requestedCoinUids, currencyCode: currencyCode)
        }

        let mappedCoinUids = (try? await priceSourceMappingProvider.mappedCoinUids()) ?? []
        let qcCoinUids = requestedCoinUids.filter { mappedCoinUids.contains($0.lowercased()) }
        let hsCoinUids = requestedCoinUids.filter { !mappedCoinUids.contains($0.lowercased()) }

        guard !qcCoinUids.isEmpty else {
            return try await hsProvider.coinPrices(coinUids: requestedCoinUids, currencyCode: currencyCode)
        }

        async let hsPrices = providerCoinPrices(hsProvider, coinUids: hsCoinUids, currencyCode: currencyCode)
        async let qcPrices = qcCoinPricesWithFallback(qcProvider: qcProvider, coinUids: qcCoinUids, currencyCode: currencyCode)

        return merge(hsPrices: try await hsPrices, qcPrices: try await qcPrices)
    }

    private func providerCoinPrices(_ provider: CoinPriceProvider, coinUids: [String], currencyCode: String) async throws -> [CoinPrice] {
        guard !coinUids.isEmpty else {
            return []
        }

        return try await provider.coinPrices(coinUids: coinUids, currencyCode: currencyCode)
    }

    private func qcCoinPricesWithFallback(qcProvider: CoinPriceProvider, coinUids: [String], currencyCode: String) async throws -> [CoinPrice] {
        do {
            return try await qcProvider.coinPrices(coinUids: coinUids, currencyCode: currencyCode)
        } catch {
            return try await hsProvider.coinPrices(coinUids: coinUids, currencyCode: currencyCode)
        }
    }

    private func merge(hsPrices: [CoinPrice], qcPrices: [CoinPrice]) -> [CoinPrice] {
        var order = [String]()
        var merged = [String: CoinPrice]()

        for coinPrice in hsPrices + qcPrices {
            if merged[coinPrice.coinUid] == nil {
                order.append(coinPrice.coinUid)
            }
            merged[coinPrice.coinUid] = coinPrice
        }

        return order.compactMap { merged[$0] }
    }
}

private extension Sequence where Element: Hashable {
    func uniqueOrdered() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
