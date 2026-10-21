# Evalon Codex — Distribution via Admin-Managed Hooks (Research)

> **Research only — nothing implemented.** This applies the L1–L4 concept to **OpenAI Codex**: the
> CLI, the desktop app and the IDE extension.
>
> **Scope:** only **documented, admin-managed** controls.
>
> **Requirements and the cross-platform matrix:** `readme-requirements.md`.
>
> Legend: ✅ verified in docs or `openai/codex` source (commit `af91f6e`) · ⚠ inference or untested.

## Why not a plugin

On Claude Code the plugin carries the hooks, and managed settings enable it. **On Codex that doesn't
work.** Plugin hooks are **user-level** ✅:
- they need the **user's trust review** before they run
- users can **turn them off** in `/hooks` or in `config.toml`
- they are **skipped** when the admin sets `allow_managed_hooks_only = true`

So a plugin can't meet **L2**: its hooks don't take effect automatically. The only hooks that do are
**managed hooks** from requirements. They are *trusted by policy*, users can't disable them, and
`[features].hooks = true` keeps them on ✅.

**Managed hooks carry only the command, not the files.** In OpenAI's words, "Codex doesn't distribute
the scripts". A plugin could deliver the files, but it adds admin steps (import the marketplace per
workspace, set it to *Installed*). It also has two drawbacks:
- a **versioned install path** that the hooks would have to resolve
- **no support in the IDE extension**

A managed `SessionStart` hook can install the handler itself, so the **plugin brings no advantage**. We don't use it.

## Conclusions
- **L1–L2:** Evalon's hooks go into the customer's **managed requirements**. The handler gets onto the machine in one of two ways:
  - **C1 · No MDM (recommended default):** a managed `SessionStart` hook installs the handler once, from a **hash-pinned installer**. After that, the handler updates itself.
  - **C2 · MDM:** the customer's MDM installs the handler at a fixed, root-owned path and delivers the requirements, including a sign-in lock.
- **L3:** each hook entry has `command` and `command_windows`, so one entry covers every OS.
- **L4:** the handler is a self-contained binary, so no Node is needed.
- **Limits OpenAI documents** (tell customers):
  - hooks are *"a useful guardrail, not a complete enforcement boundary"*
  - hosted tools such as WebSearch aren't hooked
  - cloud-orchestrated runs only support `mcp_tool` hooks
  - hooks are fail-open on error
  - a local machine admin can change system files

## Layer-by-layer

| Layer | Codex mechanism | Fit |
|---|---|---|
| **L1 Distribution** | **Hook definitions:** managed `requirements.toml` (Admin Console / MDM / system file). **Handler:** C1 installer via `SessionStart`, or C2 MDM package | ✅ |
| **L2 Trigger** | Managed `[hooks]`: trusted by policy, can't be disabled by users | ✅ incl. blocking |
| **L3 OS handling** | `command` + `command_windows` per entry | ✅ |
| **L4 Runtime** | Self-contained handler binary (Bun-compiled), one per OS/arch | ✅ |

### L1 — Managed requirements ✅

| Channel | Location / key | Notes |
|---|---|---|
| Cloud | ChatGPT Admin Console → Agent Security → *Edit as TOML* | Per workspace; for users signed in to it |
| macOS MDM | domain `com.openai.codex`, key `requirements_toml_base64` | Ranks above cloud for local runs |
| System file | `/etc/codex/requirements.toml`; `%ProgramData%\OpenAI\Codex\requirements.toml` | Admin-owned; ranks below cloud |

**Sign-in lock:**
- **Keys:** `allowed_login_methods = ["chatgpt"]` and `allowed_chatgpt_workspaces = ["<id>"]`.
- **Where it works:** they apply **only via MDM or the system file**. Cloud requirements ignore them.
- **Why it matters:** without the lock, a user signed in with a personal account or an API key doesn't get the cloud requirements.

### L2 — Managed hooks ✅
- **Events:** `SessionStart` / `SessionEnd`, `UserPromptSubmit`, `PreToolUse` / `PostToolUse`, `PermissionRequest`, `Pre` / `PostCompact`, `SubagentStart` / `SubagentStop`, `Stop`.
- **Blocking:** `PreToolUse` returns `permissionDecision: "deny"` or exits **2**.
  - Covered: shell, `apply_patch`, MCP and local tools.
  - Not covered: hosted tools.
- **Fail-open:** errors, timeouts and other exit codes let the action continue (R9).
- **Shell:** Codex runs the command with `$SHELL -lc` on macOS/Linux and `cmd.exe /C` on Windows ✅ (`hooks/src/engine/command_runner.rs`).

### L3 — OS handling ✅
Use `command` for macOS/Linux and `command_windows` for Windows. The Windows shell is `cmd.exe`, so call PowerShell explicitly when needed.

### L4 — Runtime
L4 reuses the POC:
- **Handler:** one self-contained binary per target (Bun `--compile`), installed to `~/.evalon/bin/` (C1) or a fixed system path (C2).
- **Targets:** `darwin-arm64`, `darwin-x64`, `linux-x64`, `linux-arm64`, `windows-x64`, `windows-arm64`.

## Recipes

### C1 · No MDM — managed hooks + hash-pinned installer (recommended default)

**How it works:**
1. **First `SessionStart`:** if the handler isn't installed yet, the hook downloads `install.sh` / `install.ps1` and runs it **only if its SHA-256 matches** the hash pinned in the TOML.
2. **The installer:**
   - detects the OS and architecture
   - downloads the handler
   - verifies it with Evalon's signing key, which is embedded in the installer
   - installs it to `~/.evalon/bin/`
3. **Later sessions:** the handler **updates itself**, using our existing update mechanism and its signature checks.
4. **Event hooks:** all other hooks call the fixed path. If the handler is missing, the command fails and Codex fails open.

**Requirements TOML** (the admin pastes this in **Agent Security → Edit as TOML**):

```toml
[features]
hooks = true

[[hooks.SessionStart]]
[[hooks.SessionStart.hooks]]
type = "command"
timeout = 15
command = '''[ -x "$HOME/.evalon/bin/evalon-hook" ] || { curl -fsSL https://<evalon-cdn>/codex/install.sh -o /tmp/evalon-install.sh && echo "<INSTALLER_SHA256>  /tmp/evalon-install.sh" | shasum -a 256 -c - >/dev/null && sh /tmp/evalon-install.sh; } >/dev/null 2>&1; exit 0'''
command_windows = '''powershell -NoProfile -ExecutionPolicy Bypass -Command "if(!(Test-Path $env:USERPROFILE\.evalon\bin\evalon-hook.exe)){$f=\"$env:TEMP\evalon-install.ps1\"; iwr -UseBasicParsing https://<evalon-cdn>/codex/install.ps1 -OutFile $f; if((Get-FileHash $f).Hash -eq '<INSTALLER_SHA256>'){& $f}}; exit 0"'''

[[hooks.PreToolUse]]
[[hooks.PreToolUse.hooks]]
type = "command"
timeout = 30
statusMessage = "Evalon policy check"
command = '"$HOME/.evalon/bin/evalon-hook" PreToolUse --org <tenant-id>'
command_windows = '"%USERPROFILE%\.evalon\bin\evalon-hook.exe" PreToolUse --org <tenant-id>'

# Same as PreToolUse for: PostToolUse, UserPromptSubmit, PermissionRequest, Stop
```

**What the admin reviews:**
- the installer URL
- one hash, which we publish on GitHub releases
- the tenant ID (R6), which comes with the same paste

A new handler release needs **no TOML change**. The admin only re-pastes when the installer itself changes, which is rare.

**Evalon repo:**
```
evalon-codex/
├── installer/
│   ├── install.sh            # OS/arch detect → download → verify signature → ~/.evalon/bin
│   └── install.ps1
├── handler/                  # Bun-compiled evalon-hook, built for 6 targets in CI
└── deploy/
    └── requirements.toml     # template above; CI fills in INSTALLER_SHA256
```
CDN layout: `codex/install.sh`, `codex/install.ps1`, `codex/<version>/evalon-hook-<target>[.exe]` (+ signatures).

**Customer admin steps (one-time, per workspace):** paste the TOML in **Agent Security**. That's all.

**Limits:**
- **Sign-in gap:** personal-account or API-key sign-ins don't get cloud requirements.
- **User-writable handler:** the handler lives in a user-writable folder.
- **First session:** it may run unprotected until the install finishes (fail-open).
- **Network:** the machine must reach our CDN.

### C2 · MDM
1. **Package:** Evalon ships one package per OS (`.pkg` / `.msi` / `.deb`) that installs the handler to a fixed, admin-owned path (e.g. `/opt/evalon/bin/evalon-hook`).
2. **Requirements:** the customer's MDM delivers them through `requirements_toml_base64` or the system file:
   - the same event hooks, pointing at the fixed path (no `SessionStart` installer needed)
   - the **sign-in lock**
3. **Updates:** via MDM, or the handler's own updater.

```xml
<!-- macOS .mobileconfig payload -->
<key>PayloadType</key>              <string>com.openai.codex</string>
<key>requirements_toml_base64</key> <string><!-- base64 of requirements.toml --></string>
```

**Closes C1's gaps:** the sign-in lock applies, the handler is admin-owned, and there is no download on first run. This is what most vendors do (Pillar, BeyondTrust, Endor, Arcjet, NeuralTrust, Mintive).

## What other vendors do

| Vendor | Codex mechanism | Tamper statement |
|---|---|---|
| Pillar Security | MDM writes managed hooks (macOS/Linux) | "cannot disable" via managed hooks; fail-open admitted |
| BeyondTrust Pathfinder | Installer/MDM writes `requirements.toml` `[hooks]` + `features.hooks=true` | Root-owned files |
| Endor Labs | `/etc/codex/requirements.toml` via Jamf/Intune/Kandji/JumpCloud | "Enforcement hooks fail open" |
| Arcjet | Managed requirements (file/MDM/cloud) + wrapper | Admits local-admin removal and the personal-account gap |
| NeuralTrust TrustGuard | MDM: scripts + `requirements.toml` | `allow_managed_hooks_only` |
| Mintive | Requirements via MDM | WebSearch outside coverage |
| GitGuardian, Akto, Apollo Watcher | User-level `~/.codex/hooks.json` | User-removable; opt-in |

**Pattern:** managed hooks plus an MDM-installed handler. No vendor relies on a Codex plugin for enforcement.

## Validation gaps
- **Surfaces:** managed hooks fire in the IDE extension and the desktop app, the same as in the CLI.
- **Install timing:** `SessionStart` runs before the first `PreToolUse`. Measure how long the first install takes.
- **Windows:** `command_windows` quoting under `cmd.exe /C`; `%USERPROFILE%` expansion.
- **Combining layers:** how cloud and MDM requirements combine when both define `[hooks]`.
- **Version floor:** Codex hooks GA is ~v0.128+; older clients ignore `[hooks]`.

## Sources
- **Managed configuration:** https://learn.chatgpt.com/docs/enterprise/managed-configuration
- **Hooks:** https://learn.chatgpt.com/docs/hooks · https://developers.openai.com/codex/hooks
- **Plugins:** https://learn.chatgpt.com/docs/plugins · https://learn.chatgpt.com/docs/enterprise/plugin-management
- **`openai/codex` source (`af91f6e`):**
  - Hook trust and discovery: `codex-rs/hooks/src/engine/discovery.rs`
  - Hook shell: `hooks/src/engine/command_runner.rs`
  - `PreToolUse`: `hooks/src/events/pre_tool_use.rs`
  - Requirements: `config/src/config_requirements.rs`
  - Hook schema: `config/src/hook_config.rs`
- **Vendors:**
  - Pillar: pillar.security
  - BeyondTrust: docs.beyondtrust.com (coding-hooks)
  - Endor Labs: docs.endorlabs.com/agent-governance/codex
  - Arcjet: arcjet.com/learn/secure-openai-codex
  - NeuralTrust: docs.neuraltrust.ai/integrations/codex
  - Mintive: mintive.com docs
  - GitGuardian: docs.gitguardian.com/endpoint-protection/ai-hooks
  - Akto: ai-security-docs.akto.io
  - Apollo Watcher: watcher-docs.apolloresearch.ai
