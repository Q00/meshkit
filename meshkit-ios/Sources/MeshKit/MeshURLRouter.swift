import Foundation

public enum MeshURLRouter {
    public static func invokeURL(scheme: String, request: MeshRequest) throws -> URL {
        guard var components = URLComponents(string: scheme),
              let urlScheme = components.scheme,
              let firstScalar = urlScheme.unicodeScalars.first,
              CharacterSet.letters.contains(firstScalar),
              !urlScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              urlScheme.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.").inverted) == nil
        else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "mesh_request", value: try request.encodedForURLScheme())]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
