import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ReleaseChannelFetching {
    func fetchAppcastXML(from url: URL) throws -> String
}

public struct URLSessionReleaseChannelFetcher: ReleaseChannelFetching {
    private final class Box: @unchecked Sendable {
        var data: Data?
        var error: Error?
    }

    public init() {}

    public func fetchAppcastXML(from url: URL) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let box = Box()

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.error = error
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                box.error = URLError(.badServerResponse)
                return
            }
            box.data = data
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)

        if let error = box.error {
            throw error
        }
        guard let resultData = box.data, let text = String(data: resultData, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }
}
