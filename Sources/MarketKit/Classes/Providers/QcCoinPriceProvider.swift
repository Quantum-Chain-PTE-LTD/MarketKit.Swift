import Alamofire
import Foundation
import HsToolKit

class QcCoinPriceProvider: CoinPriceProvider {
    private let baseUrl: String
    private let networkManager: NetworkManager
    private let apiKey: String

    init(baseUrl: String, apiVersion _: Int, apiKey: String, networkManager: NetworkManager) {
        self.baseUrl = baseUrl.trimmingTrailingSlashes()
        self.networkManager = networkManager
        self.apiKey = apiKey
    }

    private var headers: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "Authorization", value: apiKey)
        return headers
    }

    func coinPrices(coinUids: [String], currencyCode: String) async throws -> [CoinPrice] {
        let uniqueCoinUids = coinUids.uniqueOrdered()
        guard !uniqueCoinUids.isEmpty else {
            return []
        }

        let parameters: Parameters = [
            "uids": uniqueCoinUids.joined(separator: ","),
            "currency": currencyCode,
            "fields": "uid,price,price_change_24h,price_change_1d,last_updated",
        ]

        let responses: [CoinPriceResponse] = try await networkManager.fetch(url: "\(baseUrl)/coins", method: .get, parameters: parameters, headers: headers)
        return responses.map { $0.coinPrice(currencyCode: currencyCode) }
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

private extension Sequence where Element: Hashable {
    func uniqueOrdered() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
