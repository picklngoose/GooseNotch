import Foundation

// MARK: - Wire types (all Sendable so they can cross the streaming boundary)

struct ToolCall: Sendable {
    let name: String
    /// JSON object of the arguments, kept as raw bytes so it can be echoed back to the model unchanged.
    let argumentsData: Data

    /// Arguments flattened to strings (numbers and booleans included) for simple tool handlers.
    var arguments: [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, value) in object {
            if let s = value as? String {
                out[key] = s
            } else if let n = value as? NSNumber {
                out[key] = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
            } else {
                out[key] = "\(value)"
            }
        }
        return out
    }
}

struct ChatTurn: Sendable {
    var role: String            // system | user | assistant | tool
    var content: String
    var toolName: String? = nil
    var toolCalls: [ToolCall] = []
}

enum ChatEvent: Sendable {
    case content(String)
    case toolCalls([ToolCall])
}

enum OllamaError: LocalizedError {
    case unreachable(String)
    case http(Int, String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let host):
            return "Can't reach Ollama at \(host). Is it running?"
        case .http(let code, let message):
            if code == 401 || code == 403 { return "Ollama rejected the request (\(code)). Check your sign-in or API key." }
            return message.isEmpty ? "Ollama returned HTTP \(code)." : message
        case .server(let message):
            return message
        }
    }
}

// MARK: - Client

/// Minimal Ollama client: model list + streaming chat with tool calls.
///
/// Talks to the local Ollama server by default (`http://localhost:11434`). Cloud models work through
/// the local server once you've run `ollama signin`. To talk to Ollama's cloud API directly instead:
///   defaults write com.example.NotchIsland ollamaHost "https://ollama.com"
///   defaults write com.example.NotchIsland ollamaAPIKey "<your key>"
final class OllamaClient: Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        session = URLSession(configuration: config)
    }

    var host: String {
        let raw = UserDefaults.standard.string(forKey: "ollamaHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = raw.isEmpty ? "http://localhost:11434" : raw
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    private func makeRequest(_ path: String, body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: host + path) else { throw OllamaError.unreachable(host) }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key = UserDefaults.standard.string(forKey: "ollamaAPIKey"), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func isConnectionError(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .notConnectedToInternet, .timedOut, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private static func errorMessage(from text: String) -> String {
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            return message
        }
        return text
    }

    // MARK: Models

    func listModels() async throws -> [String] {
        do {
            let (data, response) = try await session.data(for: try makeRequest("/api/tags"))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw OllamaError.http(http.statusCode, Self.errorMessage(from: String(decoding: data, as: UTF8.self)))
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = (object?["models"] as? [[String: Any]]) ?? []
            return models.compactMap { ($0["name"] as? String) ?? ($0["model"] as? String) }.sorted()
        } catch let error as URLError where Self.isConnectionError(error) {
            throw OllamaError.unreachable(host)
        }
    }

    // MARK: Chat

    func chatStream(model: String, turns: [ChatTurn], tools: [[String: Any]]) -> AsyncThrowingStream<ChatEvent, Error> {
        var body: [String: Any] = [
            "model": model,
            "messages": turns.map(Self.serialize),
            "stream": true
        ]
        if !tools.isEmpty { body["tools"] = tools }

        let bodyData: Data
        let request: URLRequest
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
            request = try makeRequest("/api/chat", body: bodyData)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var text = ""
                        for try await line in bytes.lines { text += line }
                        throw OllamaError.http(http.statusCode, Self.errorMessage(from: text))
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let error = object["error"] as? String { throw OllamaError.server(error) }

                        if let message = object["message"] as? [String: Any] {
                            if let content = message["content"] as? String, !content.isEmpty {
                                continuation.yield(.content(content))
                            }
                            if let rawCalls = message["tool_calls"] as? [[String: Any]] {
                                let calls = rawCalls.compactMap(Self.parseToolCall)
                                if !calls.isEmpty { continuation.yield(.toolCalls(calls)) }
                            }
                        }
                        if object["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch let error as URLError where Self.isConnectionError(error) {
                    continuation.finish(throwing: OllamaError.unreachable(self.host))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func parseToolCall(_ raw: [String: Any]) -> ToolCall? {
        guard let function = raw["function"] as? [String: Any],
              let name = function["name"] as? String
        else { return nil }

        var data = Data("{}".utf8)
        if let dict = function["arguments"] as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: dict) {
            data = encoded
        } else if let string = function["arguments"] as? String, let encoded = string.data(using: .utf8) {
            data = encoded
        }
        return ToolCall(name: name, argumentsData: data)
    }

    private static func serialize(_ turn: ChatTurn) -> [String: Any] {
        var dict: [String: Any] = ["role": turn.role, "content": turn.content]
        if !turn.toolCalls.isEmpty {
            dict["tool_calls"] = turn.toolCalls.map { call -> [String: Any] in
                let args = (try? JSONSerialization.jsonObject(with: call.argumentsData)) ?? [String: Any]()
                return ["function": ["name": call.name, "arguments": args] as [String: Any]]
            }
        }
        if let toolName = turn.toolName { dict["tool_name"] = toolName }
        return dict
    }
}
