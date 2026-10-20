# ClaudeBar

<img width="640" height="536" alt="Screenshot 2026-10-20 at 11 56 25 PM" src="https://github.com/user-attachments/assets/1b4dc432-226c-46ba-b764-5ca001b565b6" />


A tiny macOS menu-bar app that shows your Claude usage limits: the **5-hour** and **weekly** windows, the same numbers Claude Code's `/usage` command shows.

The menu bar shows two small gauges with percentages. Click it to see larger dials with reset times, a last-updated time, and Refresh / Quit items. Gauges turn green below 50%, orange below 80%, and red at 80% and above.

## Requirements

- macOS
- Xcode command line tools (`xcode-select --install`)
- [Claude Code](https://claude.com/claude-code), logged in with a Claude account

## Build and run

```sh
make run        # build and launch
make install    # copy ClaudeBar.app to /Applications
make clean      # remove the built app
```

Or without make: `./build.sh && open ClaudeBar.app`.

The app runs only in the menu bar and has no Dock icon. To quit, choose **Quit** (⌘Q) from its menu. To start it at login, add `ClaudeBar.app` under System Settings → General → Login Items.

## How it works

- **Auth:** reuses Claude Code's OAuth token. It reads `~/.claude/.credentials.json` if that file exists, otherwise the `Claude Code-credentials` item in the macOS Keychain (macOS may ask you to allow access the first time).
- **Data:** calls `https://api.anthropic.com/api/oauth/usage` and reads `five_hour` and `seven_day` utilization and reset times.
- **Refresh:** every 5 minutes, or on demand with **Refresh** (⌘R).

The token stays on your machine and is sent only to `api.anthropic.com`.

## Troubleshooting

| Menu shows | Meaning |
|---|---|
| `No Claude Code login found` | No credentials found. Run `claude` and log in. |
| `Token expired – run claude once` | The OAuth token expired. Running `claude` refreshes it. |
| `HTTP <code>` | The usage endpoint returned an error, or there was no network (`HTTP 0`). |

This uses an undocumented endpoint, so it may stop working if that endpoint changes.
