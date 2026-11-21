import Foundation
import Network

/// One event from a coding tool, e.g. state=done source=claude.
struct PipEvent: Sendable {
    let state: String
    let source: String
    let message: String?
}

/// A tiny HTTP server bound to 127.0.0.1 only.
/// Accepts: GET /event?state=working|needs-input|done|hide&source=claude&message=...
///          GET /health
final class EventServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "pip.event-server")
    private let onEvent: @Sendable (PipEvent) -> Void

    init(port: UInt16, onEvent: @escaping @Sendable (PipEvent) -> Void) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                 port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        self.onEvent = onEvent
    }

    func start(onFailure: @escaping @Sendable (Error) -> Void) {
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Drop connections that never send a request.
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            let ok = self?.process(data) ?? false
            let body = ok ? "ok" : "bad request"
            let status = ok ? "200 OK" : "400 Bad Request"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func process(_ data: Data?) -> Bool {
        guard let data, let request = String(data: data, encoding: .utf8),
              let firstLine = request.split(separator: "\r\n", maxSplits: 1).first else { return false }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://localhost" + parts[1]) else { return false }

        switch components.path {
        case "/health":
            return true
        case "/event":
            var query: [String: String] = [:]
            for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
            guard let state = query["state"], !state.isEmpty else { return false }
            let message = query["message"].flatMap { $0.isEmpty ? nil : String($0.prefix(300)) }
            onEvent(PipEvent(state: state, source: query["source"] ?? "", message: message))
            return true
        default:
            return false
        }
    }
}
