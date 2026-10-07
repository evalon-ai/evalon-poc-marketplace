# Evalon Claude Code Plugin – Distribution POC

## Goal

Get Evalon's hook-based agent onto every developer machine running Claude Code, with these constraints:

- **Native distribution** – use Anthropic's own plugin marketplace mechanism, not a custom installer.
- **OS-agnostic** – macOS, Windows and Linux, on x86_64 and ARM64.
- **No Node.js dependency** – the machine is not required to have `node` installed.

## Approach: 4 layers

| Layer | Concern | Mechanism | Status |
|---|---|---|---|
| **L1** | Distribution | Marketplace + plugin hosted on GitHub, configured org-wide through managed settings | ✅ Verified, including on a non-Evalon org |
| **L2** | Trigger | Hooks embedded in the plugin take effect automatically | ✅ Works and documented |
| **L3** | OS detection | A `sh` script in the plugin detects the OS | ✅ Verified on macOS and Windows |
| **L4** | Running the launcher | Use the system `node` if it exists; otherwise download a portable Node and use that | ⚠️ Portable Node verified on macOS; binaries built for all 6 OS/arch targets |

### L1 – Distribution

The plugin lives in a GitHub-hosted marketplace (this repo). An org-wide `managed-settings.json` declares the marketplace and enables the plugin, so Claude Code installs it with no action from the user:

```json
{
  "extraKnownMarketplaces": {
    "evalon-poc-marketplace": {
      "source": { "source": "github", "repo": "evalon-ai/evalon-poc-marketplace" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "evalon-poc-plugin@evalon-poc-marketplace": true
  }
}
```

Managed settings locations:
- macOS: `/Library/Application Support/ClaudeCode/managed-settings.json`
- Linux: `/etc/claude-code/managed-settings.json`
- Windows: `C:\Program Files\ClaudeCode\managed-settings.json`

The managed settings can also be delivered through the Claude admin console or MDM. The same content is in `poc-local-settings.json` for local testing.

Validated on the Evalon org and on a separate, non-Evalon org.

### L2 – Trigger

The plugin's `hooks/hooks.json` registers its hooks. They are active as soon as the plugin is enabled, with no user configuration. Claude Code must be **restarted** before newly installed or changed hooks take effect.

The POC wires `PreToolUse`, `PostToolUse` (matcher `*`), `SessionStart` and `UserPromptSubmit` to `scripts/echo-hook.sh`. That script echoes each invocation back to the user as a `systemMessage`, which makes it easy to see the hooks firing.

### L3 – OS detection

Hook commands run through `bash`, and Claude Code on Windows runs them in Git Bash. That means a single `sh` script covers all platforms. The script detects the OS from `uname -s`:

| `uname -s` | OS |
|---|---|
| `Darwin*` | macOS |
| `Linux*` | Linux |
| `MINGW*` / `MSYS*` / `CYGWIN*` | Windows |

The architecture comes from `uname -m` (`x86_64`/`amd64` vs `arm64`/`aarch64`).

Verified on macOS and Windows.

### L4 – Launcher runtime

We can't assume `node` exists on the machine. The POC compiled a minimal JS/TS module loader to a native executable with `bun build --compile`. That executable embeds the runtime, works as a portable stand-in for `node`, and can load and run the launcher `.mjs`.

- Verified running on macOS.
- Cross-compiled for all six targets: {macOS, Windows, Linux} × {x86_64, ARM64}.

## Proposed solution

1. **Build portable Node** executables for the 6 OS/arch combinations with `bun build --compile --target=…`:
   - `bun-darwin-x64`, `bun-darwin-arm64`
   - `bun-linux-x64`, `bun-linux-arm64`
   - `bun-windows-x64`, `bun-windows-arm64`
2. **Host them in an S3 bucket**, versioned, each with a SHA-256 checksum.
3. **Ship the plugin** with:
   - `hooks/hooks.json`, which points every hook at the shell script.
   - The existing launcher `.mjs`.
   - A shell script (`run.sh`) that:
     1. Detects the OS and architecture (L3).
     2. If `node` is on `PATH`, runs the launcher with it.
     3. Otherwise downloads the matching portable executable from S3 into a local cache once, verifies its checksum, and runs the launcher with it.
     4. Passes the hook's stdin through, and forwards the launcher's stdout and exit code back to Claude Code.
4. **Update the launcher** so it behaves the same under system Node and under the portable runtime. That means relying only on APIs both provide, with no assumptions about `process.execPath` or `node_modules`.

```
hook event ──► run.sh ──► detect OS/arch
                            │
               node on PATH?├── yes ──► node launcher.mjs
                            │
                            └── no ───► cached portable runtime?
                                          ├── no ──► download from S3 + verify checksum
                                          └──────► portable-runtime launcher.mjs
```

## Open items

- **Download size.** Bun-compiled binaries embed the full runtime, so expect tens of MB per platform (around 55–110 MB uncompressed, smaller when compressed). This only happens on the first run, but it can delay the first hook.
- **First-run latency vs hook timeouts.** Either download in the background on `SessionStart`, or fail open (exit 0) until the runtime is ready.
- **Cache location and versioning.** Pick a per-user directory such as `${CLAUDE_PLUGIN_DATA}` or `~/.evalon/runtime/<version>/`, and clean up old versions.
- **Integrity and trust.** Verify the checksum; consider code signing for macOS (Gatekeeper/notarization) and Windows (SmartScreen).
- **Network constraints.** Corporate proxies, egress restrictions and offline machines all affect the S3 download; add a fallback or fail-open behavior.
- **Download tool.** `curl` is present on macOS, Linux and Git Bash. Confirm it is available everywhere and decide whether a `wget` fallback is needed.
- **Validation gaps.**
  - L3 has not been tested on Linux.
  - L4 portable runtime has not been tested on Windows or Linux, or on x86 macOS.
