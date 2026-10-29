import Foundation

/// One HTTPS GET. Behind a protocol so tests and apps can supply their own transport.
public protocol HTTPFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

/// `URLSession`, reporting a non-HTTP response as status -1.
public struct URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}

/// Asks the public registries: `pypi.org/pypi/<name>/json`, `registry.npmjs.org/<name>` and
/// `crates.io/api/v1/crates/<name>`. Only the package name leaves the device.
public struct PublicRegistry: PackageRegistry {
    public let fetcher: any HTTPFetching
    public let userAgent: String
    public let timeout: TimeInterval

    public init(
        fetcher: any HTTPFetching = URLSessionFetcher(),
        userAgent: String = "PackageClaimKit/1.0 (+https://github.com/rajatslakhina/package-claim-kit)",
        timeout: TimeInterval = 8
    ) {
        self.fetcher = fetcher
        self.userAgent = userAgent
        self.timeout = timeout
    }

    /// The request for a name, or nil when the name could not be a package there.
    public func request(for name: String, in ecosystem: Ecosystem) -> URLRequest? {
        let key = ecosystem.normalize(name)
        let address = switch ecosystem {
        case .pypi: "https://pypi.org/pypi/\(key)/json"
        case .npm: "https://registry.npmjs.org/" + key.replacingOccurrences(of: "/", with: "%2F")
        case .crates: "https://crates.io/api/v1/crates/\(key)"
        }
        guard ecosystem.accepts(name), let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func lookup(_ name: String, in ecosystem: Ecosystem) async -> RegistryAnswer {
        let registry = ecosystem.registryName
        guard let request = request(for: name, in: ecosystem) else {
            return .unavailable("`\(name)` is not a valid \(registry) name")
        }
        do {
            let (data, status) = try await fetcher.fetch(request)
            switch status {
            case 200:
                return RegistryParser.parse(data, in: ecosystem).map(RegistryAnswer.found)
                    ?? .unavailable("\(registry) sent an answer this kit cannot read")
            case 404, 410:
                return .missing
            default:
                return .unavailable("\(registry) answered HTTP \(status)")
            }
        } catch {
            return .unavailable("\(registry) could not be reached (\(error.localizedDescription))")
        }
    }
}
