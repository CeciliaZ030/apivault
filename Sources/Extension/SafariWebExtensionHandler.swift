import AppKit
import Foundation
import SafariServices

private final class ExtensionResponseSink: @unchecked Sendable {
    private let callback: (BridgeResponseEnvelope) -> Void

    init(callback: @escaping (BridgeResponseEnvelope) -> Void) {
        self.callback = callback
    }

    func deliver(_ response: BridgeResponseEnvelope) {
        DispatchQueue.main.async {
            self.callback(response)
        }
    }
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let request = context.inputItems.first as? NSExtensionItem else {
            complete(
                response: BridgeResponseEnvelope(
                    id: UUID().uuidString,
                    ok: false,
                    code: .internalError,
                    message: "Missing extension input item.",
                    data: nil
                ),
                context: context
            )
            return
        }

        guard let payload = messagePayload(from: request) else {
            complete(
                response: BridgeResponseEnvelope(
                    id: UUID().uuidString,
                    ok: false,
                    code: .internalError,
                    message: "Missing browser message payload.",
                    data: nil
                ),
                context: context
            )
            return
        }

        let sink = ExtensionResponseSink { [weak self] response in
            self?.complete(response: response, context: context)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try JSONSerialization.data(withJSONObject: payload)
            let bridgeRequest = try decoder.decode(BridgeEnvelope.self, from: data)

            if bridgeRequest.type == .openApp {
                openContainingApp { result in
                    let response: BridgeResponseEnvelope
                    switch result {
                    case .success:
                        response = BridgeResponseEnvelope(
                            id: bridgeRequest.id,
                            ok: true,
                            code: nil,
                            message: "Opening API Key Manager.",
                            data: nil
                        )
                    case .failure(let error):
                        response = BridgeResponseEnvelope(
                            id: bridgeRequest.id,
                            ok: false,
                            code: .internalError,
                            message: error.localizedDescription,
                            data: nil
                        )
                    }
                    sink.deliver(response)
                }
                return
            }

            LoopbackBridgeClient.send(bridgeRequest) { result in
                let response: BridgeResponseEnvelope
                switch result {
                case .success(let envelope):
                    response = envelope
                case .failure(let error):
                    response = BridgeResponseEnvelope(
                        id: bridgeRequest.id,
                        ok: false,
                        code: .internalError,
                        message: "Launch API Key Manager and try again. \(error.localizedDescription)",
                        data: nil
                    )
                }
                sink.deliver(response)
            }
        } catch {
            complete(
                response: BridgeResponseEnvelope(
                    id: UUID().uuidString,
                    ok: false,
                    code: .internalError,
                    message: "Invalid browser request payload.",
                    data: nil
                ),
                context: context
            )
        }
    }

    private func openContainingApp(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func complete(response: BridgeResponseEnvelope, context: NSExtensionContext) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard
            let data = try? encoder.encode(response),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            context.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let responseItem = NSExtensionItem()
        if #available(macOS 11.0, *) {
            responseItem.userInfo = [SFExtensionMessageKey: object]
        } else {
            responseItem.userInfo = ["message": object]
        }
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    private func messagePayload(from item: NSExtensionItem) -> Any? {
        if #available(macOS 11.0, *) {
            return item.userInfo?[SFExtensionMessageKey]
        }
        return item.userInfo?["message"]
    }
}
