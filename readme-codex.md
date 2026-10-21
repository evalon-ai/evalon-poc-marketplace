# Evalon Codex — Enterprise Distribution via Admin-Managed Controls (Research)

> **Research only — nothing implemented.** This applies the L1–L4 concept to **OpenAI Codex**: the
> CLI, the desktop app and the IDE extension.
>
> **Scope:** only **documented, admin-managed** controls that an organisation's IT/security team
> deploys to its own fleet, plus what other vendors publicly do.
>
> **Status:** findings as of Oct 2026. Legend:
> - ✅ verified in official docs or the `openai/codex` source (commit `af91f6e`)
> - ⚠ vendor claim, inference, or untested
>
> Sources are listed at the end.

## Goal
Evalon's hook-based agent runs on every Codex developer machine in a customer org. It must be:
- **centrally deployed and enforced by the org's admins**
- able to **intercept and block**
- **OS-agnostic:** macOS, Windows and Linux, on x64 and arm64
- free of any dependency on Node

## Conclusions

- **Admin-managed hooks are the documented enforcement channel.**
  - Admins put hooks in `[hooks]` in `requirements.toml`. It can be delivered three ways:
    - the ChatGPT Admin Console (Agent Security)
    - macOS MDM
    - a system file
  - OpenAI documents these hooks as *trusted by policy*: they skip the per-user review, and they **can't be disabled from the `/hooks` browser**.
  - Pinning `[features].hooks = true` keeps them running even if a user turns hooks off locally. ✅
- **Requirements carry the hook *definitions*, not the handler.** "Codex doesn't distribute the scripts." The handler binary or script reaches the machine by one of **two L1 options**:
  - **L1-A · MDM.** A package installs the handler at a fixed, root-owned path.
  - **L1-B · Workspace plugin.** The admin sets the Evalon plugin to *Installed*, and Codex installs it and keeps it updated.
- **The plugin is a code-delivery vehicle, not the enforcement point.** Plugin hooks are user-level:
  - they go through user trust review
  - users can toggle them
  - they are skipped when `allow_managed_hooks_only = true`

  So the managed hooks call the plugin's handler; the plugin's own `hooks.json` stays empty.
- **Limits OpenAI documents itself:**
  - Hooks are *"a useful guardrail, not a complete enforcement boundary"*.
  - Hosted tools such as WebSearch aren't hooked.
  - Cloud-orchestrated runs only support `mcp_tool` hooks.
  - Hooks are fail-open on error.
  - A local machine admin can change system files.

  Disclose these to customers, as other vendors do.

## Layer-by-layer

| Layer | Codex mechanism | Fit |
|---|---|---|
| **L1 Distribution** | **Hook definitions:** managed `requirements.toml` (Admin Console / MDM / system file). **Handler:** L1-A MDM package, or L1-B workspace plugin | ✅ two options |
| **L2 Trigger** | **Managed `[hooks]`**: trusted by policy; their commands invoke the L1 handler | ✅ incl. blocking |
| **L3 OS handling** | Native: each handler has `command` + `command_windows` | ✅ one entry for all OSes |
| **L4 Runtime** | System `node`, else the Bun portable runtime (checksum, cached) | ✅ reuse of the POC |

### L1 — Distribution

Every option needs **two things on the machine**:
- **(1) the hook definitions:** `requirements.toml` `[hooks]`
- **(2) the handler** those definitions execute

#### (1) Hook definitions — managed requirements ✅

| Channel | Location / key | Notes |
|---|---|---|
| Cloud | ChatGPT Admin Console → Agent Security → *Edit as TOML* | Per workspace; applies to users signed in to it |
| macOS MDM | domain `com.openai.codex`, key `requirements_toml_base64` | Ranks above cloud for local runs |
| System file | `/etc/codex/requirements.toml` (Unix/macOS); `%ProgramData%\OpenAI\Codex\requirements.toml` (Windows) | Root/admin-owned; ranks below cloud |

The same TOML (shown in **L2**) goes into any channel.

**Example: delivering it by macOS MDM.** This is a `.mobileconfig` payload, uploaded to Jamf, Intune or Kandji:

```xml
<dict>
  <key>PayloadType</key>            <string>com.openai.codex</string>
  <key>PayloadIdentifier</key>      <string>ai.evalon.codex.requirements</string>
  <key>PayloadUUID</key>            <string>…</string>
  <key>PayloadVersion</key>         <integer>1</integer>
  <!-- base64 of the requirements.toml shown in L2 -->
  <key>requirements_toml_base64</key>
  <string>W2ZlYXR1cmVzXQpob29rcyA9IHRydWUK…</string>
</dict>
```

```sh
# Evalon CI produces the value:
base64 < requirements.toml | tr -d '\n'
```

On Windows and Linux, the MDM or config tool writes the same TOML to the system-file path instead. Cloud delivery means pasting the TOML in the Admin Console.

**Sign-in lock** (`allowed_login_methods = ["chatgpt"]`, `allowed_chatgpt_workspaces = ["<id>"]`):
- **Where it works:** it is honoured **only via MDM or the system file**; cloud requirements ignore it.
- **What it does:** it makes users sign in to the org workspace, so the org's cloud requirements apply.

#### (2) Handler — two options

| | **L1-A · MDM package** | **L1-B · Workspace plugin** |
|---|---|---|
| How | `.pkg` / `.msi` / `.deb` installs handler + runtime to a fixed path, e.g. `/opt/evalon/` | Admin imports Evalon's GitHub marketplace into the ChatGPT workspace and sets `evalon-guard` → **Installed** |
| Updates | MDM re-push or Evalon self-updater | **Automatic**: daily marketplace sync (or *Sync now*) |
| Handler path | Fixed, root-owned, not user-writable | User-owned plugin cache; versioned path (see L2) |
| Surfaces | CLI, desktop app, IDE extension | CLI and desktop app. **Plugins aren't available in the IDE extension** ✅ (IDE-only machines need a fallback) |
| Sign-in | Any | Needs a ChatGPT sign-in to the workspace |
| Customer setup | MDM package + profile | One-time admin UI steps **per workspace** |
| Market use | Pillar, BeyondTrust, Endor, Arcjet, NeuralTrust, Mintive | No vendor found doing this yet |

**Is the workspace plugin stronger?** No. Enforcement strength comes from the **managed hooks**, and they are identical in both options.
- **L1-B is more convenient:** no binary MDM package, and updates are automatic.
- **L1-A is stronger on integrity and coverage:** the handler sits at a root-owned path rather than a user-writable cache, and it works in the IDE extension and with any sign-in.

**Can the workspace plugin be defined globally?** Not as far as documented.
- **Per-workspace setup.** Plugin import and the *Installed* policy are set **per workspace, per role, in the Admin UI**. Every customer's admin repeats the import, and so does each workspace if a customer has several.
- **No API.** No admin API for plugin policy is documented.
- **Public directory ⚠.** Publishing Evalon to OpenAI's public plugin directory (`/plugins/deploy/submission`) would make it **discoverable** in every workspace, so admins skip the import. Admins would still choose *Installed* per workspace.
- **Config-declared marketplaces ⚠.** A marketplace declared in `config.toml`, which MDM or cloud config could push, makes plugins **available**, but I found **no auto-install** for it in the source. *Installed by default* comes only from the workspace policy.

**L1-B on its own still needs requirements:** the cloud Agent Security requirements (no MDM) carry the hook definitions. The MDM-only sign-in lock is optional but closes the personal-account and API-key gap.

### L2 — Trigger: managed hooks ✅

**Example — L1-A (MDM) only.** This is the requirements TOML from L1; repeat the block per event.

> ⚠ The fixed path `/opt/evalon/bin/evalon-hook` exists **only when the L1-A MDM package installed
> it**. The workspace plugin (L1-B) never writes there. It installs to
> `${CODEX_HOME:-~/.codex}/plugins/cache/workspace-directory/evalon-guard/<version>/`, which is
> user-owned and versioned. **With L1-B, replace `command` / `command_windows` with the resolver
> variant** in *Determining the handler path* below.

```toml
[features]
hooks = true     # keep managed hooks on even if a user disables hooks locally
plugins = true   # L1-B only

[hooks]
managed_dir = "/opt/evalon"                    # L1-A install dir; a label only — Codex doesn't install anything here
windows_managed_dir = 'C:\ProgramData\Evalon'

[[hooks.PreToolUse]]
[[hooks.PreToolUse.hooks]]
type = "command"
command = "/opt/evalon/bin/evalon-hook PreToolUse"                      # L1-A only (MDM-installed path)
command_windows = '"C:\ProgramData\Evalon\bin\evalon-hook.exe" PreToolUse' # L1-A only
timeout = 30
statusMessage = "Evalon policy check"
# Also: PostToolUse, UserPromptSubmit, SessionStart, PermissionRequest, Stop
```

- **Blocking (`PreToolUse`):** the handler returns `permissionDecision: "deny"` or exits **2**. Errors, timeouts and other exit codes are fail-open, so the handler decides its own error policy.
- **Covered tools:** shell / unified exec, `apply_patch`, MCP and local function tools.
- **Not covered:** hosted tools such as WebSearch.
- **Shell:** Codex runs the command string with `$SHELL -lc` on macOS/Linux and `%COMSPEC% /C` (`cmd.exe`) on Windows ✅ (`hooks/src/engine/command_runner.rs`).

#### Determining the handler path

- **With L1-A** the path is trivial: MDM put the handler at a fixed absolute path, which the TOML hard-codes (above).
- **With L1-B it is not trivial:**
  1. **No plugin variables in managed hooks.** Only *plugin* hooks receive `PLUGIN_ROOT` / `PLUGIN_DATA`. A **managed** hook gets no variable pointing at the plugin.
  2. **The install path is versioned:** `${CODEX_HOME:-~/.codex}/plugins/cache/<marketplace>/<plugin>/<version>/` ✅ (`core-plugins/src/store.rs`).
     - `<version>` changes on every update.
     - For workspace plugins, `<marketplace>` is `workspace-directory` ✅ (constant in `core-plugins/src/remote.rs`) ⚠ (confirm on a real install).
  3. **`CODEX_HOME` can relocate it.** A user (or CI) can relocate `~/.codex`, so don't hard-code `$HOME/.codex`.
  4. **The plugin may not be there yet.** It may not have arrived (first sync, or an IDE-only machine).

  **Approach:** the managed command is a **small inline resolver**:
  - it finds the newest version directory under `CODEX_HOME`
  - it runs the handler from there
  - if nothing is found, it falls back to a bootstrap (download plus checksum, as in the L4 POC) or applies the chosen error policy

```toml
# L1-B variant of the handler entry (POSIX sh; Windows runs PowerShell through cmd.exe)
command = '''d=$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/workspace-directory/evalon-guard/*/ 2>/dev/null | sort -V | tail -n1); [ -n "$d" ] && exec sh "${d}scripts/run.sh" PreToolUse; exec sh -c "curl -fsSL https://dl.evalon.ai/codex/bootstrap.sh | sh -s PreToolUse"'''
command_windows = '''powershell -NoProfile -ExecutionPolicy Bypass -Command "$h=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'}; $d=Get-ChildItem (Join-Path $h 'plugins\cache\workspace-directory\evalon-guard') -Directory -EA 0 | Sort-Object Name | Select-Object -Last 1; if($d){& (Join-Path $d.FullName 'scripts\run.ps1') PreToolUse; exit $LASTEXITCODE} else {exit 0}"'''
```

⚠ Validate:
- the exact cache layout and version-directory naming on a real workspace install
- quoting under `cmd.exe /C`
- whether stdin is passed through to the nested script (it should be, since `exec` inherits stdin)

A cleaner long-term alternative is a tiny **stable shim** at a fixed path. But that shim has to be delivered too: by MDM (back to L1-A), or by the bootstrap on first run.

### L3 — OS handling ✅
- **One entry for all OSes:** each handler has `command` and an optional `command_windows` (`commandWindows` in JSON) (`config/src/hook_config.rs`). There's no need for dual entries or a self-guard.
- **Windows:** the default shell is `cmd.exe`, so call PowerShell explicitly.

### L4 — Runtime
L4 reuses the POC:
1. Use the system `node` if it's present.
2. Otherwise use the Bun-compiled portable runtime, fetched once and checked against its checksum.
3. Cache it in a stable location, outside the versioned plugin directory:
   - the plugin data directory `${CODEX_HOME:-~/.codex}/plugins/data/evalon-guard-<marketplace>/` ✅ (path from `store.rs`)
   - or `~/.evalon/runtime/<version>/`

## Recipes

### GitHub repo (L1-B marketplace)

Codex reads the marketplace from `.agents/plugins/marketplace.json` and the plugin manifest from `.codex-plugin/plugin.json` ✅ (`core-plugins/src/marketplace_add.rs`, `store.rs`). It also accepts `.claude-plugin/plugin.json` as an alternate manifest ✅ (`manifest.rs`).

```
evalon-codex-marketplace/
├── .agents/
│   └── plugins/
│       └── marketplace.json          # lists evalon-guard
└── plugins/
    └── evalon-guard/
        ├── .codex-plugin/
        │   └── plugin.json           # name, version, description (no hooks)
        ├── scripts/
        │   ├── run.sh                # L3/L4: detect OS/arch, node or portable runtime, exec launcher
        │   └── run.ps1               # Windows equivalent
        ├── launcher/
        │   └── launcher.mjs          # Evalon hook logic (stdin JSON → decision)
        └── runtime/
            └── checksums.txt         # SHA-256 of per-OS Bun runtimes hosted on S3
```

```json
// .agents/plugins/marketplace.json
{
  "name": "evalon",
  "plugins": [
    { "name": "evalon-guard", "source": { "source": "local", "path": "./plugins/evalon-guard" } }
  ]
}
```
```json
// plugins/evalon-guard/.codex-plugin/plugin.json
{ "name": "evalon-guard", "version": "0.1.0", "description": "Evalon policy hooks handler" }
```

The **requirements template** (L2 TOML) and the **MDM payload generator** live in a separate `deploy/` folder of Evalon's main repo, not in the marketplace. The marketplace syncs into customer workspaces, and sync imports every plugin it finds.

### C1 · Workspace plugin + managed hooks (L1-B)
1. Push the repo above to GitHub.
2. Customer admin: **Admin → Plugins → Add → Import marketplace** (repo URL) → `evalon-guard` → **Installed** for the relevant roles.
3. Customer admin: **Agent Security → requirements** → paste the L2 TOML with the **L1-B resolver** commands.
4. Optional MDM text payload: the sign-in lock.

### C2 · MDM only (L1-A, market norm)
1. Evalon ships per-OS packages that install `/opt/evalon/bin/evalon-hook` (and the Windows equivalent).
2. The customer's MDM deploys the package plus the requirements (`requirements_toml_base64` or the system file) with **fixed-path** commands and the sign-in lock.

### C3 · Cloud requirements only, no MDM
Same as C1 without step 4.

⚠ **Gap:** users signed in with a personal account or an API key don't receive cloud requirements. Disclose this.

## What other vendors do (summary)

| Vendor | Codex mechanism | Tamper statement |
|---|---|---|
| Pillar Security | MDM writes managed hooks (macOS/Linux) | "cannot disable" via managed hooks; fail-open admitted |
| BeyondTrust Pathfinder | Installer/MDM writes `requirements.toml` `[hooks]` + `features.hooks=true` | Root-owned files; health "degraded" when unreachable |
| Endor Labs | `/etc/codex/requirements.toml` via Jamf/Intune/Kandji/JumpCloud | "Enforcement hooks fail open" |
| Arcjet | Managed requirements (file/MDM/cloud) + wrapper | Wrapper fails closed; admits local-admin removal, personal-account gap |
| NeuralTrust TrustGuard | MDM: scripts + `requirements.toml` | `allow_managed_hooks_only`; some user-file keys still override |
| Mintive | Requirements via MDM | Fail-open relay; WebSearch outside coverage |
| Unbound | `/etc/codex/hooks.json` (system, managed) on macOS/Linux | Windows stays per-user |
| GitGuardian, Akto, Apollo Watcher | User-level `~/.codex/hooks.json` | User-removable; opt-in tier |
| Palo Alto Prisma AIRS | Admin-console prompt routing (server-side) | Prompts only, no tool calls (vendor claim ⚠) |

**Patterns:**
- **Managed hooks plus an MDM-installed handler (L1-A) are the norm.**
- **Every "cannot be disabled" claim rests on the platform's managed layer.**
- **Vendors answer local-admin tampering with detection:** MDM re-push, a doctor or health check, and treating silence from a machine as a signal.

## Limits to disclose (all documented)
- **Not a security boundary.** OpenAI: "a useful guardrail, not a complete enforcement boundary".
- **Hosted tools aren't hooked.** WebSearch is the main example. Consider `web_search_mode` in requirements.
- **Cloud-orchestrated runs:** only `mcp_tool` hooks run.
- **Fail-open** on hook errors and timeouts.
- **Local machine admins** can modify system files and MDM-delivered state.
- **Telemetry:** OTel export can't be enforced via requirements.
- **IDE extension:** no plugins, so L1-B needs the bootstrap fallback there.

## Validation gaps
- **L1-B install:** an *Installed* workspace plugin lands on CLI and desktop clients. Measure the latency after **Sync now**. Confirm the cache path, the `workspace-directory` name and the version-directory naming.
- **L1-B resolver:** run it on macOS, Linux and Windows (`cmd.exe` quoting, stdin pass-through).
- **Surfaces:** managed hooks fire in the IDE extension and the desktop app, the same as in the CLI.
- **Combining layers:** how cloud and MDM requirements combine when both define `[hooks]`.
- **Version floor:** Codex hooks GA is ~v0.128+. Older clients ignore `[hooks]`.
- **Public directory:** whether a listing removes the per-workspace import step.

## Action items
**Build**
- [ ] Marketplace repo (tree above); `run.sh` / `run.ps1`; launcher; S3 runtimes + checksums.
- [ ] Requirements template (L1-A and L1-B variants); `.mobileconfig` / system-file generator.
- [ ] Bootstrap script for the plugin-missing case.

**Decide**
- [ ] Per customer: is MDM available? Yes → C2, or C1 plus the sign-in lock. No → C3, with the gap disclosed.
- [ ] Error policy when the handler is unavailable.
- [ ] Whether to submit to OpenAI's public plugin directory.

## Sources
- **Managed configuration (requirements, MDM keys, precedence, hooks, login keys, marketplaces):** https://learn.chatgpt.com/docs/enterprise/managed-configuration
- **Hooks:** https://learn.chatgpt.com/docs/hooks · https://developers.openai.com/codex/hooks
- **Plugins:** https://learn.chatgpt.com/docs/plugins
  - Admin plugin management: https://learn.chatgpt.com/docs/enterprise/plugin-management
  - Help article: https://help.openai.com/en/articles/20001256-plugins-in-chatgpt-and-codex
  - Directory submission: https://developers.openai.com/plugins/deploy/submission
- **`openai/codex` source (commit `af91f6e`):**
  - Hook discovery and trust: `codex-rs/hooks/src/engine/discovery.rs`
  - Hook shell: `hooks/src/engine/command_runner.rs`
  - `PreToolUse`: `hooks/src/events/pre_tool_use.rs`
  - Requirements: `config/src/config_requirements.rs`
  - Hook schema (`command_windows`): `config/src/hook_config.rs`
  - Plugin paths: `core-plugins/src/store.rs`
  - Remote marketplace names: `core-plugins/src/remote.rs`
  - Marketplace layout: `core-plugins/src/marketplace_add.rs`
  - Install-policy UI: `tui/src/chatwidget/plugin_catalog.rs`
  - PR #18893
- **Vendors:**
  - Pillar: pillar.security (2026 comparison)
  - BeyondTrust: docs.beyondtrust.com (coding-hooks)
  - Endor Labs: docs.endorlabs.com/agent-governance/codex
  - Arcjet: arcjet.com/learn/secure-openai-codex
  - NeuralTrust: docs.neuraltrust.ai/integrations/codex
  - Mintive: mintive.com docs
  - Unbound: github.com/websentry-ai/setup PR #390
  - GitGuardian: docs.gitguardian.com/endpoint-protection/ai-hooks
  - Akto: ai-security-docs.akto.io
  - Apollo Watcher: watcher-docs.apolloresearch.ai
  - Palo Alto: paloaltonetworks.com blog 2026-08-07
