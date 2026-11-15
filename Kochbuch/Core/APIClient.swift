import Foundation
import UIKit

enum APIError: LocalizedError {
  case notConfigured, invalidURL, unauthorized(String?), server(Int, String?), decoding(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured: return "Kein Server eingerichtet."
    case .invalidURL: return "Die Serveradresse ist ungültig."
    case let .unauthorized(msg): return msg ?? "Anmeldung abgelaufen – bitte erneut anmelden."
    case let .server(code, msg): return (msg?.isEmpty == false) ? msg : "Serverfehler (\(code))."
    case let .decoding(detail): return "Antwort des Servers nicht lesbar (\(detail))."
    }
  }
}

private struct ErrorBody: Decodable { let error: String? }

/// Zugriff auf die Kochbuch-API (/api/v1) mit Bearer-Token.
@MainActor
final class APIClient {
  static let shared = APIClient()

  private enum Keys {
    static let server = "kochbuch.server"
    static let token = "kochbuch.token"
  }

  private(set) var baseURL: String = UserDefaults.standard.string(forKey: Keys.server) ?? ""
  private(set) var token: String? = Keychain.get(Keys.token)

  /// Wird aufgerufen, wenn das Token ungültig ist (401)
  var onUnauthorized: (@MainActor () -> Void)?

  var isLoggedIn: Bool { !baseURL.isEmpty && token != nil }

  let session: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 30
    cfg.timeoutIntervalForResource = 300
    cfg.waitsForConnectivity = false
    return URLSession(configuration: cfg)
  }()

  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  nonisolated static func normalize(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if !s.isEmpty, !s.lowercased().hasPrefix("http") { s = "http://" + s }
    while s.hasSuffix("/") { s.removeLast() }
    return s
  }

  /// Absolute URL für Bilder ("/uploads/…" vom Server)
  func mediaURL(_ path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    if path.hasPrefix("http") { return URL(string: path) }
    return URL(string: baseURL + path)
  }

  // MARK: Anmeldung

  func setServer(_ server: String) { baseURL = Self.normalize(server) }

  func store(server: String, token: String) {
    baseURL = Self.normalize(server)
    self.token = token
    UserDefaults.standard.set(baseURL, forKey: Keys.server)
    Keychain.set(token, for: Keys.token)
  }

  func clearToken() {
    token = nil
    Keychain.set(nil, for: Keys.token)
  }

  // MARK: Requests

  private func makeRequest(_ method: String, _ path: String, query: [String: String?] = [:]) throws -> URLRequest {
    guard !baseURL.isEmpty else { throw APIError.notConfigured }
    guard var comps = URLComponents(string: baseURL + "/api/v1/" + path) else { throw APIError.invalidURL }
    let items = query.compactMap { key, value -> URLQueryItem? in
      guard let value, !value.isEmpty else { return nil }
      return URLQueryItem(name: key, value: value)
    }
    if !items.isEmpty { comps.queryItems = items }
    guard let url = comps.url else { throw APIError.invalidURL }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    return req
  }

  private func perform(_ req: URLRequest) async throws -> Data {
    let data: Data
    let resp: URLResponse
    do {
      (data, resp) = try await session.data(for: req)
    } catch let error as URLError {
      switch error.code {
      case .timedOut: throw APIError.server(0, "Zeitüberschreitung – ist der Server erreichbar?")
      case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost:
        throw APIError.server(0, "Server nicht erreichbar. Bist du im Heimnetz (oder per VPN verbunden)?")
      default: throw error
      }
    }
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    if (200 ..< 300).contains(code) { return data }
    let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
    if code == 401 {
      if token != nil, req.url?.path.hasSuffix("auth/login") == false {
        clearToken()
        onUnauthorized?()
      }
      throw APIError.unauthorized(message)
    }
    throw APIError.server(code, message ?? String(data: data, encoding: .utf8).map { String($0.prefix(200)) })
  }

  private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do {
      return try decoder.decode(T.self, from: data)
    } catch let DecodingError.keyNotFound(key, ctx) {
      throw APIError.decoding("fehlt: \(key.stringValue) in \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
    } catch let DecodingError.typeMismatch(_, ctx) {
      throw APIError.decoding("Typ: \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
    } catch let DecodingError.valueNotFound(_, ctx) {
      throw APIError.decoding("leer: \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
    } catch {
      throw APIError.decoding(error.localizedDescription)
    }
  }

  func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
    let req = try makeRequest("GET", path, query: query)
    return try decode(T.self, try await perform(req))
  }

  func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil, as type: T.Type = T.self) async throws -> T {
    var req = try makeRequest(method, path)
    if let body {
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try encoder.encode(AnyEncodable(body))
    }
    return try decode(T.self, try await perform(req))
  }

  /// Für Endpunkte, deren Antwort nicht gebraucht wird
  func call(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
    let _: OkResponse = try await send(method, path, body: body)
  }

  func raw(_ path: String) async throws -> Data {
    try await perform(try makeRequest("GET", path))
  }

  // MARK: Uploads

  struct UploadFile {
    var data: Data
    var filename: String
    var mimeType: String
  }

  func upload<T: Decodable>(_ path: String, fields: [String: String] = [:], files: [(field: String, file: UploadFile)], as type: T.Type = T.self) async throws -> T {
    var req = try makeRequest("POST", path)
    req.timeoutInterval = 300
    let boundary = "Boundary-\(UUID().uuidString)"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    var body = Data()
    func append(_ s: String) { body.append(s.data(using: .utf8)!) }
    for (key, value) in fields {
      append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
    }
    for entry in files {
      let safeName = entry.file.filename.replacingOccurrences(of: "\"", with: "")
      append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(entry.field)\"; filename=\"\(safeName)\"\r\nContent-Type: \(entry.file.mimeType)\r\n\r\n")
      body.append(entry.file.data)
      append("\r\n")
    }
    append("--\(boundary)--\r\n")
    let data = try await session.upload(for: req, from: body)
    let code = (data.1 as? HTTPURLResponse)?.statusCode ?? 0
    if !(200 ..< 300).contains(code) {
      let message = (try? decoder.decode(ErrorBody.self, from: data.0))?.error
      if code == 401 { clearToken(); onUnauthorized?(); throw APIError.unauthorized(message) }
      throw APIError.server(code, message)
    }
    return try decode(T.self, data.0)
  }

  /// Foto als JPEG hochladen (HEIC etc. versteht der Server nicht) – liefert "/uploads/…"
  func uploadImage(_ image: UIImage) async throws -> String {
    let resized = image.downscaled(maxSide: 2000)
    guard let data = resized.jpegData(compressionQuality: 0.82) else { throw APIError.server(0, "Bild konnte nicht umgewandelt werden.") }
    let result: UploadResponse = try await upload("uploads", files: [("file", UploadFile(data: data, filename: "foto.jpg", mimeType: "image/jpeg"))])
    return result.url
  }
}

struct OkResponse: Decodable { let ok: Bool? }
struct UploadResponse: Decodable { let url: String }

/// Typ-gelöschter Encodable-Wrapper für `any Encodable`
struct AnyEncodable: Encodable {
  let value: any Encodable
  init(_ value: any Encodable) { self.value = value }
  func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

extension UIImage {
  func downscaled(maxSide: CGFloat) -> UIImage {
    let longest = max(size.width, size.height)
    guard longest > maxSide else { return self }
    let scale = maxSide / longest
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
