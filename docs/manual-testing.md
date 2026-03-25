# Manual Testing

## Build And Enable

1. Run `xcodegen generate` in `/Users/cecilia/vibe-tools/api-key-manager`.
2. Open `APIKeyManager.xcodeproj` in Xcode.
3. Run the `APIKeyManagerApp` scheme.
4. For the fastest local loop, use `Safari > Settings > Developer > Add Temporary Extension...`.
5. Select [Extension](/Users/cecilia/vibe-tools/api-key-manager/Extension).
6. Keep the desktop app running so the popup can use the localhost fallback bridge.

## Temporary Extension Dev Loop

- The popup will try Safari native messaging first.
- If Safari loaded the folder as a temporary extension, the popup falls back to `http://127.0.0.1:38173/bridge`.
- If you edit [popup.js](/Users/cecilia/vibe-tools/api-key-manager/Extension/popup.js) or other extension resources, reload the temporary extension in Safari before retesting.

## Phase 2 Checks

- Add two fake keys from the desktop app: `sk-test-alpha` and `sk-test-beta`.
- Relaunch the app and confirm both records persist.
- Search by provider or note.
- Delete one record and confirm it stays deleted after relaunch.
- Try invalid entries: blank key, whitespace-only key, duplicate key for the same provider.

## Phase 3 Checks

- Open any page in Safari and click the extension.
- Confirm the popup opens on the `Log Key` tab.
- Confirm `Current Link` is filled from the active Safari tab and is read-only.
- Enter a manual `Page Title`, `Platform Link`, environment, and one fake key row.
- Add a second key row with `+` and confirm both save in one submit.
- Switch back to the dashboard and confirm the new platform and key rows appear immediately.
- Retry the same key save and confirm duplicate validation appears in the popup.

## Usage Logging Checks

- Open the extension and switch to the `Log Usage` tab.
- Confirm `Source Platform` is populated from saved key platforms.
- Pick a source environment, add a usage row, and submit it.
- Add a second usage row for a different server or site and submit again.
- Confirm the desktop app still builds and opens after usage logs are stored.

## Phase 4 Checks

- Fresh launch should start with the vault locked.
- Unlock once, reveal a key, and copy it into a plain text editor.
- Lock the vault again and confirm reveal/copy are blocked.
- Save a new key from Safari while the vault is locked and confirm the save still succeeds.

## Phase 5 Checks

- Quit the app and try saving from Safari. The popup should tell you to launch the dashboard.
- Relaunch the app and retry the save.
- Edit metadata for an existing record and relaunch to confirm persistence.
- Export metadata and confirm the JSON excludes plaintext secrets.
