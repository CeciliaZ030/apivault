import Foundation
import Network

enum LoopbackBridgeClientError: LocalizedError {
    case timeout
    case missingResponse

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "API Key Manager did not respond in time. Launch the app and try again."
        case .missingResponse:
            return "API Key Manager returned an empty response."
        }
    }
}

private final class LoopbackClientState: @unchecked Sendable {
    var didFinish = false
    var responseBuffer = Data()
}

enum LoopbackBridgeClient {
    static func send(
        _ request: BridgeEnvelope,
        completion: @escaping @Sendable (Result<BridgeResponseEnvelope, Error>) -> Void
    ) {
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(rawValue: AppConstants.bridgePort)!
        let connection = NWConnection(host: host, port: port, using: .tcp)
        let queue = DispatchQueue(label: "APIKeyManager.ExtensionBridgeClient")
        let state = LoopbackClientState()

        @Sendable func finish(_ result: Result<BridgeResponseEnvelope, Error>) {
            guard !state.didFinish else { return }
            state.didFinish = true
            connection.cancel()
            completion(result)
        }

        @Sendable func receiveNextChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    finish(.failure(error))
                    return
                }

                if let data {
                    state.responseBuffer.append(data)
                }

                if let newlineIndex = state.responseBuffer.firstIndex(of: 0x0A) {
                    let line = Data(state.responseBuffer[..<newlineIndex])
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601

                    do {
                        let response = try decoder.decode(BridgeResponseEnvelope.self, from: line)
                        finish(.success(response))
                    } catch {
                        finish(.failure(error))
                    }
                    return
                }

                if isComplete {
                    finish(.failure(LoopbackBridgeClientError.missingResponse))
                    return
                }

                receiveNextChunk()
            }
        }

        connection.stateUpdateHandler = { stateUpdate in
            switch stateUpdate {
            case .ready:
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601

                do {
                    var payload = try encoder.encode(request)
                    payload.append(0x0A)
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                        } else {
                            receiveNextChunk()
                        }
                    })
                } catch {
                    finish(.failure(error))
                }

            case .failed(let error):
                finish(.failure(error))

            case .waiting(let error):
                finish(.failure(error))

            default:
                break
            }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 5) {
            finish(.failure(LoopbackBridgeClientError.timeout))
        }
    }
}

