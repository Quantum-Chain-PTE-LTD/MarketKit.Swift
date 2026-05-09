import Foundation

enum JsonHttpClient {
    static func fetch<T: Decodable>(_ type: T.Type, url: URL, headers: [String: String] = [:]) async throws -> T {
        let data = try await fetchData(url: url, headers: headers)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func fetchData(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: JsonHttpError.invalidResponse)
                    return
                }

                guard 200 ..< 300 ~= httpResponse.statusCode else {
                    continuation.resume(throwing: JsonHttpError.unexpectedStatusCode(httpResponse.statusCode))
                    return
                }

                guard let data else {
                    continuation.resume(throwing: JsonHttpError.emptyResponse)
                    return
                }

                continuation.resume(returning: data)
            }

            task.resume()
        }
    }
}

enum JsonHttpError: Error {
    case invalidResponse
    case unexpectedStatusCode(Int)
    case emptyResponse
}
