### What's new in 1.2.0

- Fixed persistent "Token expired" when a stale `~/.claude/.credentials.json` shadowed the fresh Keychain login.
- Added an app icon.

ClaudeBar now supports both Claude and Codex usage in the macOS menu bar.

- Switch between Claude and Codex; your choice is remembered.
- View usage windows and reset times using existing CLI logins.
- Official Claude and OpenAI logos identify the selected provider.
- Automatic refresh every five minutes, with manual refresh available.

### Downloads

Requires **macOS 13 Ventura or later**.

| Archive | Mac |
| --- | --- |
| `macos-arm64.zip` | Apple Silicon (M-series) |
| `macos-x86_64.zip` | Intel |
| `macos-universal.zip` | Either architecture |

Extract the ZIP, move `ClaudeBar.app` into Applications, and open it. Claude Code or Codex CLI must be installed and signed in for the corresponding provider.

These builds are ad-hoc signed, without Apple notarization. macOS may block the first launch; after attempting to open the app, use **System Settings → Privacy & Security → Open Anyway** if you trust this download.

`SHA256SUMS.txt` contains checksums for all three archives. Linux is not included in this release.
