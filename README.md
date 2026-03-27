# API Key Manager

Local macOS dashboard plus Safari Web Extension for capturing, storing, and managing API keys from developer portals.

## What Exists

- Native macOS dashboard built with `SwiftUI`.
- Safari Web Extension popup for manual key capture on any page.
- Local bridge from the extension to the running app over `127.0.0.1`.
- Secret storage in macOS `Keychain`.
- Metadata storage in `SwiftData`.
- Session unlock for reveal and copy actions.
- Provider recognition helpers for `OpenAI`, `Anthropic`, and `Stripe`.

## Project Layout

- XcodeGen spec: [project.yml](/Users/cecilia/vibe-tools/api-key-manager/project.yml)
- Shared models: [Sources/Shared](/Users/cecilia/vibe-tools/api-key-manager/Sources/Shared)
- Desktop app: [Sources/App](/Users/cecilia/vibe-tools/api-key-manager/Sources/App)
- Safari extension handler: [Sources/Extension](/Users/cecilia/vibe-tools/api-key-manager/Sources/Extension)
- Web extension resources: [Extension](/Users/cecilia/vibe-tools/api-key-manager/Extension)
- Architecture notes: [docs/architecture.md](/Users/cecilia/vibe-tools/api-key-manager/docs/architecture.md)
- Manual validation: [docs/manual-testing.md](/Users/cecilia/vibe-tools/api-key-manager/docs/manual-testing.md)

## Build

```bash
git clone https://github.com/CeciliaZ030/apivault.git
cd apivault
./install
```

`./install` will:
- generate the Xcode project if needed
- build the macOS app
- copy `APIKeyManager.app` into `/Applications`
- launch the installed app

## Manual Safari Step

Safari still requires one manual step after install:

1. Open Safari.
2. Go to `Safari > Settings > Extensions`.
3. Enable `APIKeyManager Extension`.
4. If it does not appear immediately, quit and reopen Safari once.

## Manual Developer Build

If you want to work on the app in Xcode instead:

```bash
cd apivault
xcodegen generate
open APIKeyManager.xcodeproj
```

## Current Flow

1. Run the desktop app so the local bridge is listening.
2. Open any page in Safari and click the extension.
3. Paste a key, choose a provider/environment, and save.
4. Review the saved item in the dashboard.
5. Unlock the vault before reveal or copy.
