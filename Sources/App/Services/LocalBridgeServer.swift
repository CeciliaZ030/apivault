import Foundation
import Network

final class LocalBridgeServer: @unchecked Sendable {
    private enum ParsedRequest {
        case jsonLine(BridgeEnvelope)
        case httpBridge(BridgeEnvelope)
        case httpOptions
    }

    private let queue = DispatchQueue(label: "APIKeyManager.LocalBridgeServer")
    private let handler: @Sendable (BridgeEnvelope) async -> BridgeResponseEnvelope
    private var listener: NWListener?
    private(set) var lastErrorMessage: String?

    init(handler: @escaping @Sendable (BridgeEnvelope) async -> BridgeResponseEnvelope) {
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }

        let port = NWEndpoint.Port(rawValue: AppConstants.bridgePort)!
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: port)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.lastErrorMessage = error.localizedDescription
            case .ready:
                self?.lastErrorMessage = nil
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection, buffer: Data())
    }

    private func receiveRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                self.sendJSONLine(
                    response: BridgeResponseEnvelope(
                        id: UUID().uuidString,
                        ok: false,
                        code: .internalError,
                        message: error.localizedDescription,
                        data: nil
                    ),
                    over: connection
                )
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = parseRequest(from: nextBuffer) {
                process(request, over: connection)
                return
            }

            if isComplete {
                sendJSONLine(
                    response: BridgeResponseEnvelope(
                        id: UUID().uuidString,
                        ok: false,
                        code: .internalError,
                        message: "Incomplete bridge request.",
                        data: nil
                    ),
                    over: connection
                )
                return
            }

            receiveRequest(from: connection, buffer: nextBuffer)
        }
    }

    private func parseRequest(from buffer: Data) -> ParsedRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if buffer.starts(with: Data("OPTIONS ".utf8)) {
            guard buffer.range(of: Data("\r\n\r\n".utf8)) != nil else { return nil }
            return .httpOptions
        }

        if buffer.starts(with: Data("POST ".utf8)) {
            guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }

            let headerData = Data(buffer[..<headerRange.lowerBound])
            let bodyStart = headerRange.upperBound
            let headerString = String(decoding: headerData, as: UTF8.self)
            let headerLines = headerString.components(separatedBy: "\r\n")

            guard let requestLine = headerLines.first, requestLine.contains("POST /bridge") else {
                return nil
            }

            let contentLength = headerLines.compactMap { line -> Int? in
                let components = line.split(separator: ":", maxSplits: 1)
                guard
                    components.count == 2,
                    components[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length"
                else {
                    return nil
                }
                return Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }.first ?? 0

            let availableBodyBytes = buffer.distance(from: bodyStart, to: buffer.endIndex)
            guard availableBodyBytes >= contentLength else { return nil }

            let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
            let body = Data(buffer[bodyStart..<bodyEnd])

            do {
                let envelope = try decoder.decode(BridgeEnvelope.self, from: body)
                return .httpBridge(envelope)
            } catch {
                return nil
            }
        }

        if let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newlineIndex])
            do {
                let envelope = try decoder.decode(BridgeEnvelope.self, from: line)
                return .jsonLine(envelope)
            } catch {
                return nil
            }
        }

        return nil
    }

    private func process(_ request: ParsedRequest, over connection: NWConnection) {
        switch request {
        case .httpOptions:
            sendHTTPStatus(code: 204, title: "No Content", over: connection)

        case .jsonLine(let envelope):
            Task {
                let response = await handler(envelope)
                sendJSONLine(response: response, over: connection)
            }

        case .httpBridge(let envelope):
            Task {
                let response = await handler(envelope)
                sendHTTPJSON(response: response, over: connection)
            }
        }
    }

    private func sendHTTPStatus(code: Int, title: String, over connection: NWConnection) {
        let header = [
            "HTTP/1.1 \(code) \(title)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Content-Length: 0",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        connection.send(content: Data(header.utf8), contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendHTTPJSON(response: BridgeResponseEnvelope, over connection: NWConnection) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let body = try encoder.encode(response)
            let header = [
                "HTTP/1.1 200 OK",
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: POST, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type",
                "Content-Type: application/json",
                "Content-Length: \(body.count)",
                "Connection: close",
                "",
                ""
            ].joined(separator: "\r\n")

            var payload = Data(header.utf8)
            payload.append(body)
            connection.send(content: payload, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendHTTPStatus(code: 500, title: "Internal Server Error", over: connection)
        }
    }

    private func sendJSONLine(response: BridgeResponseEnvelope, over connection: NWConnection) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            var payload = try encoder.encode(response)
            payload.append(0x0A)
            connection.send(content: payload, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }
}
