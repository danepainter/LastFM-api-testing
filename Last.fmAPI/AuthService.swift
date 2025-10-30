import Foundation

struct SessionPayload: Decodable {
    struct Session: Decodable {
        let key: String
        let name: String
        let subscriber: Int?
    }
    let session: Session
}

struct AuthService {
    private let base = "https://ws.audioscrobbler.com/2.0/"

    func makeAuthURL() -> URL {
        var comps = URLComponents(string: "https://www.last.fm/api/auth")!
        comps.queryItems = [
            .init(name: "api_key", value: Secrets.apiKey),
            .init(name: "cb", value: Secrets.callbackURL)
        ]
        return comps.url!
    }

    func fetchSessionKey(token: String) async throws -> String {
        let params: [String: String] = [
            "api_key": Secrets.apiKey,
            "method": "auth.getSession",
            "token": token
        ]
        let sortedConcat = params.keys.sorted().map { "\($0)\(params[$0]!)" }.joined()
        let apiSig = md5Hex(sortedConcat + Secrets.sharedSecret)

        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "method", value: "auth.getSession"),
            .init(name: "api_key", value: Secrets.apiKey),
            .init(name: "token", value: token),
            .init(name: "api_sig", value: apiSig),
            .init(name: "format", value: "json")
        ]
        let url = comps.url!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
        return payload.session.key
    }
}


