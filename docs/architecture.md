# Architecture

## Core Components

- `Host app`
  - native macOS app
  - owns secure storage and dashboard UI
  - runs a localhost bridge server while the app is open
- `Safari Web Extension`
  - detects supported sites
  - supports manual save from the popup on any page
  - sends save requests through Safari native messaging to the extension handler
- `Extension handler`
  - receives `browser.runtime.sendNativeMessage(...)` messages
  - forwards bridge requests to the running app over `127.0.0.1`
- `Vault`
  - secret values stored in macOS Keychain
  - metadata stored locally in SwiftData

## Architecture Diagram

```mermaid
flowchart LR
    user["User in Safari"]
    popup["Safari Web Extension Popup"]
    handler["Safari Extension Handler"]
    fallback["Localhost HTTP Fallback<br/>127.0.0.1:38173/bridge"]
    app["Apivault Host App"]
    dashboard["Dashboard UI"]
    bridge["Local Bridge Server"]
    swiftdata["SwiftData Metadata Store"]
    keychain["macOS Keychain"]

    user --> popup
    popup -->|preferred| handler
    popup -->|temporary extension fallback| fallback
    handler --> bridge
    fallback --> bridge
    bridge --> app
    app --> dashboard
    app --> swiftdata
    app --> keychain
```

## Data Flow

1. User visits a developer portal page and clicks the Safari extension.
2. Extension shows a manual save flow first.
3. User pastes or confirms the API key and related metadata in the extension UI.
4. Extension sends the capture request through the Safari extension handler.
5. Extension handler forwards the request to the running app over localhost.
6. Host app validates, encrypts, and stores the record.
7. Host app replies with success or validation failure.
8. Dashboard displays the saved key metadata and allows secure copy.

## Sequence Diagram

```mermaid
sequenceDiagram
    participant U as "User"
    participant P as "Safari Popup"
    participant H as "Extension Handler"
    participant B as "Host App Bridge"
    participant A as "Host App"
    participant S as "SwiftData"
    participant K as "Keychain"

    U->>P: Open popup on developer portal page
    P->>P: Capture active tab URL and page title
    U->>P: Paste API key and metadata

    alt "Native messaging path"
        P->>H: sendNativeMessage(saveDraft)
        H->>B: Forward request over localhost
    else "Temporary extension fallback"
        P->>B: POST /bridge saveDraft
    end

    B->>A: Deliver BridgeEnvelope
    A->>A: Validate payload and fingerprint key
    A->>S: Check duplicate metadata record
    A->>K: Save plaintext secret
    A->>S: Insert metadata record
    A-->>B: Return success or validation error

    alt "Save succeeded"
        B-->>P: ok=true, savedItemID
        P-->>U: Show success state
        A-->>U: Dashboard updates with new record
    else "Save failed"
        B-->>P: ok=false, validation_error/internal_error
        P-->>U: Show error message
    end
```

## Capture Strategy

- `phase 1`: manual save from the extension popup on any page
- `phase 2`: automatic recognition of supported developer portal pages
- `phase 3`: provider-specific extraction helpers for known API key screens

## Security Rules

- Do not treat this as a password manager.
- Do not scrape Google sign-in credentials.
- Minimize secret handling inside the extension.
- Require app unlock before revealing or copying sensitive values.

## Near-Term Milestones

1. Manual save from popup on any page.
2. Desktop CRUD for saved metadata and secure copy.
3. Session unlock for reveal and copy.
4. Assistive provider recognition for OpenAI, Anthropic, and Stripe.
5. Better failure handling and test fixtures.
