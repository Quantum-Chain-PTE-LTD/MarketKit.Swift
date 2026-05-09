import Foundation

enum QcProviderDefaults {
    static let apiVersion = 1
    static let mappingCacheTtlSeconds: TimeInterval = 86_400
    static let assetListCacheTtlSeconds: TimeInterval = 86_400
    static let assetListUrl = "https://4fldi7jb6b.execute-api.ap-southeast-1.amazonaws.com/v1/market-kit/assets"
    static let priceSourceMappingUrl = "https://quantum-static-prod-s3-apse1.s3.ap-southeast-1.amazonaws.com/qwallet/market-kit/price-source-mapping.json"
}
