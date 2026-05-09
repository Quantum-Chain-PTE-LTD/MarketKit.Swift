import Foundation

struct CoinMetadata {
    let coins: [Coin]
    let blockchainRecords: [BlockchainRecord]
    let tokenRecords: [TokenRecord]

    init(coins: [Coin] = [], blockchainRecords: [BlockchainRecord] = [], tokenRecords: [TokenRecord] = []) {
        self.coins = coins
        self.blockchainRecords = blockchainRecords
        self.tokenRecords = tokenRecords
    }
}

protocol SupplementalCoinMetadataProvider {
    func metadata() async throws -> CoinMetadata
}
