# Evalon — Seamless Per-Org Identifier Provisioning (Research)

> **Research only.** How to hand the Evalon **hook handler** a **per-org, non-secret, hash-grade**
> identifier so reported events can be attributed to the source org — across **Claude Code, Cursor,
> Codex**. Constraints: **no per-machine manual config**; the value is **programmatically consumable
> by the hook** (env / arg / stdin / file); it is **set and distributed by the platform** or **read
> from the agent's runtime/local state**; it is **non-secret** (customer willing to share). Findings
> Oct 2026. ✅ = verified in official docs · ⚠ = community / undocumented / inference. Sources at end.

## Scope & requirements
- **Identifier:** unique per **org**, or per **org × platform** — Evalon maps `(platform, id) → customer org`. **Non-secret**, **hash-grade** (opaque / high-entropy, not sequential). **No rotation** requirement.
- **Delivery:** consumable by the hook programmatically, with **no manual per-machine/per-runner setup**.
- **Dropped (per decision):** baking a per-customer artifact (**M1**) is out.

## Conclusions

### Claude Code
- **(Recommended)** Set an `env` var `EVALON_ORG_ID` in managed settings; the hook reads it. **Validated locally.**
- Alternative: a plugin option → `$CLAUDE_PLUGIN_OPTION_ORG_ID` (M6) — more plugin-native.
- *Watch:* only the on-device file was tested, not console delivery; Team/Enterprise only; Bedrock/Vertex users skip the fetch.

### Cursor
- **(Recommended)** Have the **hook read the plugin parameter directly** — cleanest if it works (no MCP, no email). *Untested → confirm with a quick test.*
- Fallback: send the **Cursor login email**; map its domain → org in our backend. *Reliably delivered; needs enforced SSO; breaks on multi-domain orgs, contractors, and gmail.*
- Last resort: **MCP-server bridge** (server reads the parameter, writes a file, hook reads it). *Fragile — MCP server launch/timing isn't guaranteed (may start late or never).*

### Codex
- **(Recommended)** **M4** — an admin-set, org-wide `SessionStart` hook writes an **Evalon-assigned token** to a file the hook reads. *Clean 1:1 per customer; needs enterprise managed config.*
- Alternative: the hook reads the **ChatGPT workspace id** from `~/.codex/auth.json` and tags events; the admin reports it from the dashboard; we match (and union) in the backend. *ChatGPT login only; not the API `org-…`.*
- *Watch:* **no single-per-org id exists** that a hook can read locally *and* an admin can report — the local id is **per-workspace** (several per company → union in our backend), `org-…` needs a secret and isn't 1:1 either, and the company-level "Tenant" id isn't locally exposed. So **M4's assigned token is the clean 1:1 key**; the workspace id is a secondary signal to union.

## TL;DR
| | Claude Code | Cursor | Codex |
|---|---|---|---|
| **M2 · managed value → hook** (platform-distributed) | ✅ managed `env` var (console) — **env→hook validated locally** | ⚠ **undocumented & UNTESTED for hooks** — `variables` is official but exemplified only for `mcp.json`; hook schema shows no `env`/`args`/`${VAR}`, and no example confirms a hook reading one (none proves it fails either). **Test before relying**; proven paths = `user_email` / M4 | ❌ **for plugin delivery** — no platform-distributed value reaches a plugin hook (no `variables`, env-policy, or args); ✅ only via **non-plugin managed `hooks.json`** command args |
| **M3 · native org id in hook context** (stdin/env) | ❌ none in stdin/env | ❌ none (only `user_email`) | ❌ none in stdin/env |
| **M3-id · native hash-grade org id exists?** | ✅ org **UUID** (1:1) | ❌ team id = **sequential int** | ⚠ `org-…` / workspace **UUID** exist but **not 1:1 per org** (several workspaces; `org-…` unreachable without a secret) |
| **M3-local · extract org id from machine state** | ✅ `~/.claude.json` → `oauthAccount.organizationUuid` (⚠ undocumented) | ❌ only a secret JWT; no non-secret hash id | ⚠ ChatGPT mode: `~/.codex/auth.json` account-id (undocumented) |
| **M4 · managed Startup hook → `~/.evalon/org_id`; plugin reads file** | ✅ server-managed `SessionStart` hook (or just M2 env) | ✅ **Enterprise** team `sessionStart` / **MDM** (❌ Teams·Pro w/o MDM) | ✅ managed `SessionStart` hook — **how a Codex plugin gets the id** |
| **M5-email · authenticated email in hook** (per-user) | ❌ none | ✅ `user_email` (trustworthy under enforced SSO) | ❌ none |
| **M6-plugin-parameter · admin-set plugin option → hook** | ✅ `userConfig` → `CLAUDE_PLUGIN_OPTION_<KEY>` (admin sets via managed `pluginConfigs`) | ✅⚠ via **MCP-server bridge**: plugin `${VAR}` → plugin's MCP server `env` (✅) → writes `~/.evalon/org_id` → hook reads it; ⚠ MCP **start-timing racy** (first-run gap self-heals). *(Direct `${VAR}`→hook stays untested.)* | ❌ no plugin variables/options field |

*Email is **per-user**, not per-org. Beyond Cursor's hook payload it's also readable **non-secret from local state** — Claude `~/.claude.json` → `oauthAccount.emailAddress`; Codex `id_token` `email` claim — but **no clean non-interactive CLI** prints it on Claude/Codex.*

**Bottom line:** **no platform injects a native org id into the hook (M3 fails everywhere)**, and **M2 works on Claude only**. Per-platform:
- **Claude = M2 managed `env` var** ✅ (value = the native org UUID).
- **Cursor =** test **plugin-param→hook** (clean if it works); else **`user_email` + enforced SSO** (map domain→org); **MCP bridge** is a fragile last resort.
- **Codex (plugin) = M4** (admin hook writes an Evalon-assigned token) — clean 1:1; or read the **ChatGPT workspace id** from `auth.json` + admin reports it (⚠ not 1:1 per org → union). M2 ❌ for plugin delivery.

An **MDM-dropped `org_id` file** read by the hook is the common non-native fallback for an opaque admin-assigned id. All local-extraction / undocumented fields → version-guard.

## Mechanisms
- **M2 — platform-distributed managed value.** Admin sets a value once in the platform's console / managed config; the **platform distributes** it to clients; the hook reads it (env / arg). No per-machine setup.
- **M3 — native org id from the hook's runtime context.** The hook reads an org id the platform already injects (stdin JSON / env). **Fails on all three** — no org id is injected.
- **M3-local — local extraction.** The consented hook reads the native org id from the platform's **local app state** — no API call, no managed config. Undocumented / brittle.
- **M3-id — does a native hash-grade org id even exist?** The precondition for M3 / M3-local (a platform may have one the hook can't reach).
- **M5-email — authenticated email in the hook.** Per-**user**, not per-org; Evalon maps email → org. (Cursor only.)
- **M4 — managed Startup hook writes the id to a shared file.** An **admin-set, org-wide `SessionStart` hook** (its command embeds the id) writes it to `~/.evalon/org_id`; Evalon's plugin hooks **read the file**. Decouples admin *delivery* from plugin *consumption* — works even where the plugin can't receive a value directly.
- **M6-plugin-parameter — admin-set plugin option delivered to the hook.** The plugin declares a config option; an **admin sets its value org-wide**; the platform hands it to the plugin's **hook**. Claude ✅ (`CLAUDE_PLUGIN_OPTION_<KEY>` via managed `pluginConfigs`); Cursor ✅⚠ (plugin `${VAR}` → plugin's **MCP server** `env` → writes a file → hook reads it; ⚠ MCP start-timing racy); Codex ❌ (no plugin option field).

---

## Claude Code

### Hook runtime context ✅
- **stdin JSON:** `session_id`, `prompt_id`, `transcript_path`, `cwd`, `scratchpad_dir?`, `permission_mode`, `effort`, `hook_event_name`, `agent_id?`, `agent_type?`, + event-specific (`tool_name`, `tool_input`, …).
- **env injected:** `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_CODE_REMOTE`, `CLAUDE_EFFORT`, `CLAUDE_ENV_FILE`, `CLAUDE_PLUGIN_OPTION_<KEY>`.
- **No org / account / user id anywhere → M3 ❌.**

### M2 — managed `env` var ✅ (recommended)
- claude.ai admin console → **Organization settings → Claude Code → Managed settings** (`claude.ai/admin-settings/claude-code`). Owner sets JSON incl. an `env` block; **Anthropic servers deliver it** (clients fetch from `api.anthropic.com` at startup, **refresh hourly**, cache `~/.claude/remote-settings.json`). **No MDM, no per-machine file.**
- `env` "sets environment variables for every session and its **subprocesses**," explicitly **incl. hooks**; custom names allowed; the hook reads `$EVALON_ORG_ID`. **Highest precedence**; user can't override.

```json
// claude.ai → Organization settings → Claude Code → Managed settings            ✅ verified surface
{
  "env": { "EVALON_ORG_ID": "72b6da61-1c4e-4a9f-8b2d-0f3a7e9c5d10" },
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "evalon-report" } ] }
    ]
  }
}
```
The hook reads it from its environment — Bash `"$EVALON_ORG_ID"`, Node `process.env.EVALON_ORG_ID`.
- ✅ **Validated locally (Oct 2026):** a custom `env` var (`EVALON_TEST_ORGID`) set in an **endpoint-managed** `managed-settings.json` `env` block was injected into the Claude Code hook process and read at runtime (the POC `echo-hook.sh` surfaced it as `[org: …]`). This exercises the **`env` → hook** delivery; the **server-managed console** path (same `env` key, distributed by Anthropic) uses the same mechanism and was not separately exercised.
- ⚠ Constraints: **Team/Enterprise only**; session must authenticate with a Team/Enterprise OAuth login / eligible credential (**a Console API key resolves a *different* org**); third-party-provider exports (`CLAUDE_CODE_USE_BEDROCK/VERTEX/…`, custom `ANTHROPIC_BASE_URL`) **skip the settings fetch** → need a Claude apps gateway; interactive sessions show a **one-time security-approval dialog** (payload includes hooks); **not a tamper boundary** (fine for a non-secret id); Cowork sessions don't fetch.

### M6 — plugin option → hook (`CLAUDE_PLUGIN_OPTION_…`) ✅ (most plugin-native)
- A plugin declares an option in **`userConfig`** (`.claude-plugin/plugin.json`); Claude exports every option to **hook processes** as **`CLAUDE_PLUGIN_OPTION_<KEY>`** (e.g. `org_id` → `$CLAUDE_PLUGIN_OPTION_ORG_ID`). Option values live under **`pluginConfigs`** (scope **User or managed**), so an **admin sets the value org-wide in managed settings** (console or `managed-settings.json`), overriding the user — documented precedent: Anthropic's own `allowManagedModsOnly`. **No file, no MCP, no race.** Set the value to the native org UUID for a hash-grade id. (Same Team/Enterprise + one-time approval-dialog caveats as M2.)
- Lighter file-bridge variants if a non-hook consumer needs it: a **SessionStart hook** reads the option and writes a file (via `CLAUDE_ENV_FILE` / `${CLAUDE_PLUGIN_DATA}`); or a plugin **MCP server** resolves `${user_config.KEY}` in its `env` and writes a file on startup (runs per enabled session). Monitors and `bin/` are **not** config channels.

### M3-local — read the native org UUID ✅ works, ⚠ undocumented
- `~/.claude.json` → **`oauthAccount.organizationUuid`** = **UUID** (same value/format as `GET /v1/organizations/me` → `id`). Siblings: `organizationName`, `organizationRole`, `organizationType` (`claude_team`/…). Read: `jq -r '.oauthAccount.organizationUuid' ~/.claude.json` (respect `CLAUDE_CONFIG_DIR`; `~` = `%USERPROFILE%` on Windows).
- **Non-secret & separate from the credential:** `.claude.json` holds OAuth **session metadata**, not the token (token = `~/.claude/.credentials.json` or the OS keychain). Reading the UUID touches **no secret**.
- ⚠ **Undocumented** `oauthAccount` schema → brittle across versions; reflects the **last interactive login**, so it can be **stale / absent / mismatched under API-key / Console / Bedrock / Vertex / CI**; scanning other `~/.claude/` auth files may trip the customer's own **"Credential Exploration"** guardrails — read **only** that one field. (`remote-settings.json` carries **no** org id; top-level `userID`/`machineID` are 64-hex, not org-scoped.)
- **Authenticated email (per-user)** sits in the same object: `~/.claude.json` → `oauthAccount.emailAddress` (non-secret). There is **no confirmed non-interactive CLI** that prints it — `/status` is interactive and a scriptable `whoami` is an open feature request — so read the file (`jq -r '.oauthAccount.emailAddress' ~/.claude.json`).

### Recommendation — Claude
Prefer **M2 managed `env`**, value = the **native `organizationUuid`** (admin pastes it once) → supported delivery + authoritative hash-grade id. **Local extraction** is a zero-config fallback on OAuth-login dev machines; don't rely on it for CI / API-key runners.

---

## Cursor

### Hook runtime context ✅
- **stdin JSON (base):** `conversation_id`, `generation_id`, `model`, `model_id`, `model_params`, `hook_event_name`, `cursor_version`, `workspace_roots[]`, **`user_email` (string | null)**, `transcript_path`. `sessionStart` adds `session_id`, `is_background_agent`, `composer_mode`.
- **env injected:** `CURSOR_PROJECT_DIR`, `CURSOR_VERSION`, **`CURSOR_USER_EMAIL`** (if logged in), `CURSOR_TRANSCRIPT_PATH`, `CURSOR_CODE_REMOTE`, `CLAUDE_PROJECT_DIR`.
- **No team / org id → M3 ❌** for an org id. The only tenant-linkable value is **`user_email`**.

### `user_email` — authenticated? ✅ yes (under SSO)
- Documented as the **authenticated** user email (`string | null`; null when logged out) — the **signed-in Cursor account**, not git config. Under **enforced SSO** (Teams/Enterprise; SAML — Okta / Azure AD / Google / OneLogin; SCIM) it is the **IdP-verified** identity → trustworthy; **no documented override/spoof knob**. Non-SSO / personal accounts = authenticated account email (lower assurance).
- ⚠ It is a plain string from the Cursor process (**not cryptographically signed to your hook**). The **stdin** value is handed over by Cursor each invocation (more trustworthy than the shadowable `CURSOR_USER_EMAIL` env var in a child process).

### M2 — plugin `variables` ⚠ undocumented & untested for hooks (resolve by testing)
- `plugin.json` `variables` is **official** and admin-set centrally in the dashboard — but **whether a hook can consume it is undocumented and UNTESTED (not proven-broken).** Evidence it is *not* the intended hook path (but **not proof it fails**): the only documented consumer is `mcp.json` (`${VAR}` in a server's `command`/`args`/`env`/`cwd`); the hook entry schema exposes **no `env`/`args`/`${VAR}`** (only `command`/`type`/`timeout`/`loop_limit`/`failClosed`/`matcher`); "variables" never appears on the hooks pages; the demonstrated model is **stdin-only** (an open forum request asks for env-injection into hooks); and **1Password/cursor-plugin** uses stdin + its own lookup. **The open door:** docs say `${VAR}` expands in "`mcp.json` **and other plugin config**" — "other plugin config" *might* include `hooks.json`, unconfirmed. **Resolve by testing** (a plugin that declares a variable + a hook whose `command` uses `${VAR}`). Until then, use **`user_email`** or **M4**.

```json
// plugin.json — DECLARE the variable; the admin sets its VALUE in the dashboard   ✅ declaration
{ "name": "evalon-guard",
  "variables": { "type": "object",
    "properties": { "EVALON_ORG_ID": { "type": "string", "description": "Evalon org id" } } } }
```
```json
// ${VAR} interpolation is documented ONLY for mcp.json (✅) — NOT hooks.json (⚠ THE GAP)
{ "mcpServers": { "evalon": {
  "command": "evalon-report",
  "env": { "EVALON_ORG_ID": "${EVALON_ORG_ID}" } } } }
```

### M6 — plugin `${VAR}` → MCP server → file → hook (✅ with a ⚠)
The one plugin component that **can** read a plugin `variable` is the plugin's **MCP server** (hooks are variable-blind; commands/agents are markdown; there is no install script). The working bridge:
**admin sets the plugin variable → Cursor launches the plugin's MCP server with `env: { "EVALON_ORG_ID": "${EVALON_ORG_ID}" }` (✅ verified: the server receives the dashboard value) → the MCP server writes `$EVALON_ORG_ID` to `~/.evalon/org_id` on startup → the plugin's hooks read the file.**
⚠ **MCP start-timing is undocumented and racy.** Cursor doesn't document when the stdio server spawns (eager vs. lazy), and there are known bugs (servers not auto-starting / "0 tools until toggled" / SIGKILL-after-init). On a **cold first session** the file may not exist when early hooks fire — acceptable if the hook **degrades gracefully** (empty org, report-later) and the server **rewrites every startup** (steady-state self-heals). Harden: expose **one trivial tool** (0-tool servers are the ones most prone to not starting) and **validate empirically** that the server spawns before your earliest hook on a cold install.
**Lifecycle facts (verified):** Cursor does **not** document whether/when the server auto-starts, and there is **no `autostart`/eager flag** (stdio config is just `command`/`args`/`env`/`envFile`; enable is a UI toggle). **Do not start-then-exit** — a stdio server that exits right after `initialize` registers as *failed* ("No server info found" / "Client closed"), and some builds **SIGKILL it ~1.5 s after init**. **Pattern:** write the file as the **very first action on boot**, then **stay alive** (answer `initialize`, expose one no-op tool, idle).

### Native org id & local extraction ❌
- Cursor's only org/team id is the **small sequential integer** team id (`cursorAuth.allowedTeamId`, e.g. `"1,3,7"`; `AllowedTeamId` MDM key) — **non-secret but NOT hash-grade**, and not a session "active-org" signal.
- **Local state:** no plaintext hash-grade org UUID. The active org is encoded only inside the **JWT access token** (`cursorAuth/accessToken` in `state.vscdb`, Keychain-encrypted) — a **secret**, undocumented, brittle. The cached email merely **duplicates `user_email`**. → local extraction **adds nothing**.

### Recommendation — Cursor
**Delivering an Evalon-chosen value into a Cursor hook is hard** — plugin `variables`→hook is undocumented/untested, there is no custom managed env, and M3 / local-extraction fail. Viable paths: **(1) `user_email`** (stdin; IdP-verified under **enforced SSO**) → map email → org; **(2) M4** — an admin **team `sessionStart` hook** (Enterprise) or **MDM** writes the id to `~/.evalon/org_id` for the plugin to read; **(3)** an MDM-dropped file. **Do not parse local auth tokens.** And **test** plugin `variables`→hook before dismissing it (undocumented, not proven-broken).

---

## Codex

### Baseline — hooks exist ✅
- Full hooks framework (`SessionStart/End`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Pre/PostCompact`, `SubagentStart/Stop`, `Stop`, `Interrupt`) via `hooks.json` or `[hooks]` in `config.toml` (`~/.codex`, repo, plugin, managed layers). Handlers `command` | `mcp_tool`. Also a `notify` program + MCP servers.
- **stdin:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, `turn_id`, `permission_mode`, + event fields. **env:** only **plugin-bundled** hooks get `PLUGIN_ROOT` / `PLUGIN_DATA` / `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA`. **No org id → M3 ❌.**

### M2 — managed config · ❌ for plugin delivery · ✅ only for non-plugin managed `hooks.json`

**For Evalon's plugin delivery, M2 is effectively ❌** — the plugin (and its `hooks.json`) is identical for every org, and no platform-distributed value reaches a plugin's hook (verified below). The command-args mechanism below applies **only** to a non-plugin **managed `hooks.json`**; for the plugin, the primary is **local extraction** (next section).
- OpenAI/ChatGPT distributes **cloud-managed `config.toml` defaults** + admin **`requirements.toml`** (Agent Security bundle) or MDM / `managed_config.toml` to the **signed-in workspace** — no per-machine env setup.
- **Carry the org id in the managed hook's `command` args** ✅: `command = "python3 /enterprise/hooks/report.py --org <uuid>"`. The id rides in the **distributed config**; only the script binary is pre-placed (MDM `managed_dir` / `windows_managed_dir`). `allow_managed_hooks_only = true` + `[features].hooks = true` enforces fleet-wide.
- ⚠ Alt: `[shell_environment_policy] set = { EVALON_ORG_ID = "<uuid>" }` (env) — docs scope `set` to the agent’s *shell tool*, **not hook subprocesses** → **lean NO** for hooks (see plugin caveat below). There is **no** generic "custom `config.toml` key forwarded to hook stdin."

```json
// managed hooks.json (distributed via requirements.toml / cloud config) — org id in the ARGS   ✅
{ "hooks": { "PreToolUse": [
  { "type": "command",
    "command": "python3 /opt/evalon/report.py --org 72b6da61-1c4e-4a9f-8b2d-0f3a7e9c5d10" } ] } }
```
```toml
# alt (⚠ reaching hook handlers UNVERIFIED): env injection + enforce managed hooks
[shell_environment_policy]
set = { EVALON_ORG_ID = "72b6da61-1c4e-4a9f-8b2d-0f3a7e9c5d10" }

[features]
hooks = true
# allow_managed_hooks_only = true
```

**⚠ Plugin-bundled hooks change this (verified).** If Evalon ships the hooks **inside a Codex plugin**,
the hook `command` is fixed/bundled → **command-args don't apply**, and two tempting paths are **dead
ends**: Codex `plugin.json` has **no `variables`/options field** (verified absence — unlike
Cursor/Claude), and `[shell_environment_policy].set` is documented for the agent's **shell tool, not
hook subprocesses** (plugin hooks receive only `PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT`,
`CLAUDE_PLUGIN_DATA`) → don't rely on it. Reliable plugin-compatible options:
- **(best — no admin value) Local-derive + cache in `PLUGIN_DATA`:** a bundled `SessionStart` hook reads `~/.codex/auth.json` → `chatgpt_account_id`, caches it to `$PLUGIN_DATA/org_id`, and later events reuse it. ⚠ ChatGPT-auth only; `auth.json` undocumented → version-guard; API-key customers have no local plain org id.
- **(admin-assigned id) MDM-dropped file:** the admin/MDM places an `org_id` file at a fixed path (the same enterprise channel that already deploys managed hook *scripts*); the bundled hook reads that path. Opaque admin-chosen id, no per-machine *user* setup.
- **(⚠ unverified) Custom `config.toml` key:** the hook reads e.g. `[evalon].org_id` from `~/.codex/config.toml` set via cloud-managed config — but whether Codex preserves unknown keys through managed-config resolution is **unverified**; test first.

### Native org id & local extraction
- Native ids (both **hash-grade, non-secret, admin-fetchable from the dashboard**): **API `org-…`** (platform.openai.com → Settings → Organization) and the **ChatGPT workspace UUID** (ChatGPT **workspace admin settings**). ⚠ **Two different realms** — the id the plugin local-extracts (`chatgpt_account_id`) is the **ChatGPT workspace UUID**, so the customer reports *that* (not the API `org-…`). **Neither is injected into the hook → M3 ❌**, and ⚠ **neither is guaranteed 1:1 per customer** (a company can run several workspaces / API orgs).
- **M3-local ⚠ (ChatGPT sign-in only, undocumented):** `~/.codex/auth.json` → **`tokens.account_id`**, or base64url-decode the `id_token` → **`["https://api.openai.com/auth"].chatgpt_account_id`** = opaque **UUID**. Read the **account-id only, never the token fields**. ⚠ internal/undocumented → version-guard. **API-key mode:** `org-…` is **not** written to local state → requires an API call.
- **Authenticated email (per-user):** the `email` claim inside `~/.codex/auth.json`'s `id_token` (base64url-decode). `codex login status` reports the auth **method** (exits 0 if logged in), not reliably the email.

### Recommendation — Codex
If hooks are distributed as a **managed `hooks.json`**, prefer **M2 — command args** (verified).
**If hooks are bundled in a plugin** (Evalon's plan), Codex has **no plugin-variable/env path**, so:
- **(Recommended) M4 / admin-assigned token** — a managed `SessionStart` hook (or MDM-dropped file) writes an **Evalon-assigned opaque id** the hook reads: clean **1:1 per customer**.
- **Alternative — local-derive:** read `auth.json` `chatgpt_account_id` on `SessionStart`, cache in `PLUGIN_DATA`; ⚠ this is the **workspace id, not 1:1 per org** (a company can run several) → backend must **union**, and it's **ChatGPT-auth only**.
Not `shell_environment_policy` (shell-tool only) and not a plugin manifest variable (none exists).

---

## M4 — managed Startup hook → shared file (works where the plugin can't receive a value)
**Idea:** an **admin-set, org-wide `SessionStart` hook** — its command/script embeds the per-org id — writes it to a conventional file (`~/.evalon/org_id`; the user-home equivalent on Windows). Evalon's **plugin hooks read that file** on each event. **Delivery (admin-controlled managed hook) is decoupled from consumption (plugin)** — bypassing the plugin-can't-receive-a-value problem (Codex plugin; Cursor variables).

**Feasibility:**
- **Claude ✅** — server-managed settings distribute **hooks** (verified); an admin adds a `SessionStart` hook: `mkdir -p ~/.evalon && printf '%s' '<org-uuid>' > ~/.evalon/org_id`. (M2 env is simpler; M4 is the file-based alternative.)
- **Cursor ✅ Enterprise / MDM** — an **Enterprise team `sessionStart` hook** (dashboard *script content* = the writer; Supported-OS per platform) or an **MDM system `hooks.json`** writes the file. This is the cleanest working Cursor path — the id comes from an **admin hook**, not the unproven plugin `variables`. **❌ Teams/Pro without MDM:** Cursor's **cloud-dashboard team hooks are Enterprise-only**, so the **Teams tier can't set the admin hook per team via the dashboard** — only MDM (a Teams *marketplace plugin* bundles identical hooks and can't carry a per-team id). Teams-without-MDM fallback = **`user_email`**.
- **Codex ✅** — a **managed `SessionStart` hook** (`requirements.toml` / cloud config, command embeds the id) writes the file; the **plugin reads it** — how a Codex plugin obtains the id without a managed-value→plugin-hook channel.

**Caveats:** needs an **admin to set the managed hook once per org** (not zero-touch); `SessionStart` runs before the first reporting event (file written at session start, read on later events); handle **per-OS** script content (sh vs PowerShell); the id is **non-secret** → the file needs no special protection; make the write **idempotent**. ⚠ Confirm the **Cursor team-hooks form exposes `sessionStart`** and that **script content may write files** (high confidence; not separately tested).

## Cross-platform recommendation
1. **M2 (managed value → hook):** **Claude ✅** (managed `env` var). **Cursor ⚠** (plugin `variables`→hook undocumented/untested) → proven paths **`user_email` + SSO** or **M4**. **Codex (plugin) ❌** → **M3-local** or **M4**; command-args M2 only for a non-plugin managed `hooks.json`.
2. **Value to use:** the platform's **native hash-grade org id** where it exists (Claude `organizationUuid`; OpenAI `org-…` / workspace UUID) — the customer reads it from their console once and the admin sets it (or local-extracts it). For **Cursor** there's no usable org id in-context → attribute via **`user_email`** (map to org) or an MDM-dropped opaque id.
3. **M3-local** — a zero-config **fallback** on **Claude** (`~/.claude.json` → `oauthAccount.organizationUuid`, 1:1 per org); on **Codex** it yields the **workspace id** (⚠ **not 1:1 per org** — may need to union; prefer **M4**'s assigned token for a clean key); **unavailable** on Cursor. All undocumented → read one field, version-guard, tolerate absence.
4. **Granularity:** per-(platform × org) falls out naturally — each platform's id namespace is distinct; Evalon maps `(platform, id) → customer`.

## Validation gaps / to confirm
- **Cursor:** **empirically test whether a hook `command` interpolates a plugin `${VAR}`** (the "other plugin config" ambiguity — undocumented/untested; evidence leans stdin-only) · is `user_email` immutable / non-spoofable under SSO? · confirm the team-hooks form exposes `sessionStart` (for **M4**).
- **Claude:** does a benign custom `env` var apply **without** the approval dialog? · `oauthAccount` behavior on in-app org switch and under non-OAuth credentials.
- **Codex:** (resolved — no plugin `variables`; `shell_environment_policy` is shell-tool-only) → for **plugin** delivery, test whether cloud-managed `config.toml` preserves a **custom key** the hook reads; and the **cross-version stability** of `auth.json` `chatgpt_account_id`.
- **All:** cross-version stability of the local-extraction fields; multi-org correctness under CI / API-key credentials.

## Sources
- **Claude Code:** code.claude.com/docs/en/hooks · /settings · /settings-reference#env · /server-managed-settings · /managed-settings · /claude-directory · /authentication · platform.claude.com/docs/en/api/admin-api/organization/get-me · *(empirical: `~/.claude.json` `oauthAccount.organizationUuid`)*
- **Cursor:** cursor.com/docs/agent/hooks · /docs/hooks · /docs/reference/plugins · /docs/plugins/building · /docs/enterprise/identity-and-access-management · /docs/enterprise/deployment-patterns · *(community: forum.cursor.com `state.vscdb`/auth threads — ⚠ unofficial)*
- **Codex:** developers.openai.com/codex/hooks · /codex/local-config · /codex/config-sample · learn.chatgpt.com/docs/enterprise/managed-configuration · /docs/config-file/config-advanced · developers.openai.com/siwc/token-sharing-open-source/token-reference · platform.openai.com → Settings → Organization · *(third-party: `auth.json` / `id_token` claim layout — ⚠ unofficial)*
