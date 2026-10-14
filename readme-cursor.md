# Evalon Cursor Plugin — Distribution Research & Mapping (POC)

> **Research only — nothing implemented.** Maps the Claude Code 4-layer concept
> (`readme-claude.md`) to Cursor: trigger, OS handling, runtime, distribution (incl. plugin
> source-from-GitHub, per-team/per-org, and automation). Claims from official Cursor docs
> (Oct 2026); uncertainties flagged. Sources at end.

## Goal
Evalon's hook-based agent on every Cursor dev machine: **central, ideally silent enforcement**;
**intercept & block**; **OS-agnostic** (mac/win/linux × x64/arm64); **no Node**.

## Headline
Ports well. **Cursor Hooks ≈ Claude Code hooks and can block** → "intercept & block" is met, and
the **L4 portable runtime reuses as-is**. The divergence is **L1 distribution**: no silent
"managed-settings → GitHub" push. GitHub-as-source exists via **Team Marketplace auto-refresh**
(dashboard-registered once, per-team; "Required" install = can't uninstall, but visible). Fully
silent org-wide still needs **MDM or Enterprise cloud**.

## Reuse from the Claude POC
- **L4 runtime** — Bun portable binary runs unchanged as a hook `command` (no Node).
- **L2 hooks** — Cursor accepts **Claude-format hooks** (`third-party-hooks` compat) → existing hook logic largely ports.
- **L3 per-OS** — same per-OS native binaries; select at deploy (MDM/installer) or via `${CURSOR_PLUGIN_ROOT}`.
- **L1 distribution** — the real rebuild: GitHub-source only via team marketplace; silent org-wide = MDM / Enterprise cloud.

## Decision tree — pick a vehicle

**MDM is the primary question:** if available, it's the best path on **any tier** — the only
channel that ships **both `hooks.json` and the binary**, silent and non-bypassable. Packaging
options: **① `hooks.json`** (config; needs a binary channel) · **② plugin bundle** (hooks +
assets, GitHub-synced, may carry the binary).

```
MDM available (Jamf / Intune / Kandji)?          ← ask first
│
├─ YES ─► ① hooks.json via MDM system path   — use regardless of Cursor tier
│          • ANY tier; silent, non-bypassable, org-wide (device)
│          • MDM runs an installer → system hooks.json + per-OS binaries → COMPLETE (one artifact)
│          • CLI gap: cursor-agent may skip hooks — mitigate (AllowedTeamId account-lock + network/EDR egress); full close needs CLI hook parity or blocking the CLI
│
└─ NO MDM ─► PLUGIN bundles the sh/PowerShell BOOTSTRAP → installs launcher (S3 + checksum)
          │   plugin ships only the bootstrap + hook defs; no binary bundling, no Node/npx
          │
          ├─ Enterprise / Teams ─► team marketplace "Required"  (enforced; Teams = 1 marketplace)
          │                         (Enterprise could instead use silent cloud-dashboard hooks)
          └─ Pro / Free ─────────► self-service install from marketplace  (opt-in, not enforced)

          validate: Windows hook→PowerShell reliability; first-run enforce window; S3 egress
```

**No-MDM path — what "validate" means (these gate the plugin/bootstrap approach):**
- **Windows hook→PowerShell** — will a Cursor hook reliably run the `.ps1` bootstrap on Windows? (known Git-Bash-terminal-profile bug that breaks Cursor's PowerShell hook bootstrap; execution policy). If not, no-MDM is broken on Windows.
- **First-run enforce window** — before the bootstrap installs the launcher, blocking hooks have no binary: **fail-open** (actions slip through = security gap) or **fail-closed** (blocks the dev)? Decide the policy; measure latency.
- **S3 egress** — can the machine reach S3 to download the launcher? (corporate proxy / allowlist / offline) — bootstrap needs proxy support + a defined fallback.

## Layer-by-layer mapping

| Layer | Claude Code | Cursor | Fit |
|---|---|---|---|
| **L1 Distribution** | GitHub marketplace + org-wide `managed-settings.json` | MDM / Enterprise cloud / team marketplace (GitHub auto-refresh) | ⚠️ Different model |
| **L2 Trigger** | Plugin hooks | **Cursor Hooks** — richer events, permission hooks **deny/modify** | ✅ incl. blocking |
| **L3 OS detection** | one `sh` script via `uname` | per-OS native binary selected at deploy / `${CURSOR_PLUGIN_ROOT}` | ✅ no shell needed |
| **L4 Runtime** | system `node` else Bun binary | hook `command` = any executable, **no Node** | ✅ reuse as-is |

**L2 — Cursor Hooks.** Events (superset of Claude's): `sessionStart/End`, `preToolUse`,
`postToolUse(+Failure)`, `subagentStart/Stop`, `beforeShellExecution`/`after…`,
`beforeMCPExecution`/`after…`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`,
`preCompact`, `stop`, `afterAgentResponse/Thought`; Tab hooks; `workspaceOpen`.
**Blocking:** permission hooks (`preToolUse`, `beforeShellExecution`, `beforeMCPExecution`,
`beforeReadFile`, `beforeTabFileRead`, `subagentStart`) return `{"permission":"allow"|"deny"|
"ask"}` or exit 2; `preToolUse` can return `updated_input`. **Config:** `~/.cursor/hooks.json`
(user), `.cursor/hooks.json` (project), system paths (`/Library/Application Support/Cursor/`,
`/etc/cursor/`, `C:\ProgramData\Cursor\`), or bundled in a plugin. Precedence **Enterprise →
Team → Project → User**; all matching hooks run and **merge** (deny > ask > allow). **Fail-open
by default**; `failClosed: true` to block on failure.
*Caveats:* no GA/beta label; **Windows hook shell undocumented**; `cursor-agent` CLI fires only
`beforeShellExecution`/`afterShellExecution` (parity roadmap); `afterFileEdit` batch-edit bugs.
*Reuse bonus:* Cursor maps **Claude-format hooks** (`third-party-hooks`), so Evalon's Claude
hooks largely carry over.

**L3 — OS handling.** `hooks.json` has **no per-OS field** (`command`, `matcher`,
`timeout`, `loop_limit`, `failClosed` only), and all entries run, so you can't branch inside one
file. **Robust approach:** the installer/vehicle writes a per-OS `hooks.json` whose `command`
points at the per-OS native binary (no shell) —

```json
// macOS — /Library/Application Support/Cursor/hooks.json
{ "hooks": { "beforeShellExecution": [
  { "command": "/Library/Application Support/Evalon/bin/evalon-hook-darwin-arm64", "failClosed": true } ] } }
// Windows — C:\ProgramData\Cursor\hooks.json
{ "hooks": { "beforeShellExecution": [
  { "command": "C:\\Program Files\\Evalon\\bin\\evalon-hook-windows-x64.exe", "failClosed": true } ] } }
```

*Install paths above are illustrative.* **Plugin path without MDM:** reference bundled binaries
via confirmed `${CURSOR_PLUGIN_ROOT}` expansion; prefer **one host-native launcher per OS**
selected by a fail-open bootstrap. The community `sh`+`powershell` dual-entry idiom is
**unverified** (not in official docs/plugins; breaks when the terminal profile is **Git Bash** —
PowerShell bootstrap bug). **Enterprise cloud** offers dashboard *"OS targeting for
platform-specific hooks"* (syntax not exposed).

**L4 — Runtime.** Hook `command` is any executable (Bash/Python/Bun shown; **no Node**). The
Bun-compiled portable runtime + launcher drop in unchanged across all 6 targets.

## Distribution vehicles

| | **A. MDM** | **B. Enterprise cloud** | **C. Team marketplace** |
|---|---|---|---|
| Ships | system `hooks.json` + binary | hooks/rules/MCP synced (~30 min) | plugin bundling hooks |
| Tier | **Any** | **Enterprise** | **Teams (1 mkt) / Enterprise (∞)** |
| Scope | **Org-wide** (device) | per-team / Org Groups | **per-team** |
| Silent? | ✅ non-bypassable | ✅ non-disableable | ◻️ visible; "Required" = can't uninstall |
| GitHub source? | no (CI → MDM) | no | ✅ repo + auto-refresh (GitHub App) |
| Needs IT? | yes (Jamf/Intune/Kandji) | no | no |

MDM policy keys (6 total): `AllowedTeamId`, `AllowedExtensions`, `ExtensionGalleryServiceUrl`,
`UpdateMode`, `WorkspaceTrustEnabled`, `NetworkDisableHttp2`; plus managed `~/.cursor/hooks.json`
+ `permissions.json`. **No MDM key force-enables/locks a plugin** → for non-bypassable user-level
enforcement, MDM ships **hooks at the system path** (outranks user), not a "locked plugin."

**Binary delivery.** With **MDM**: the installer pre-places the binary — complete, no bootstrap. **Without MDM**: the **plugin bundles the sh/PowerShell bootstrap** (the launcher script you already have); on `sessionStart` it downloads + checksums the per-OS launcher from S3, installs it, and the enforcement hooks point at it. The plugin ships only the **small bootstrap + hook defs** — **no binary bundling, no Node/npx** (`sh` on mac/linux, PowerShell on Windows are the runtime). *Validate:* Windows hook→PowerShell reliability (Git-Bash-profile bug; execution policy), first-run enforcement window (fail-open vs block), S3 egress behind proxies.

**Single artifact:** the enforced one-artifact deploy is an **MDM installer package** (system `hooks.json` + binaries). A **plugin can't reliably be that artifact via MDM** — a file-dropped local plugin (`~/.cursor/plugins/local/`) has **undocumented auto-activation** and **can't be locked** (no MDM plugin-enable key; local plugins are user-removable). The plugin UX is the marketplace "Required" path, not MDM.

## Enforcement vs. observation — only Hooks can block
- **Hooks** — the **only** mechanism that intercepts/blocks the agent (`deny`/`ask`/`updated_input`).
- **Extensions ("mods")** — **observe only**: run on startup, spawn a binary, watch terminal/files, but **cannot intercept Cursor’s AI agent** (no API). Distributable off-marketplace (Open VSX / custom gallery via `ExtensionGalleryServiceUrl`), but force-install is undocumented → still needs MDM/CI.
- **MCP servers** — launch a local binary; gating only via tool-approval prompts (weaker, not blocking).
- **Rules / AGENTS.md** — prompt/context only; no execution.
- **Patching the Cursor app** (Electron) — possible but unsupported, breaks on every app update; ruled out.
- **No-MDM, all-plans way to *run* enforcement code** = a **Required marketplace plugin with bundled hooks** (visible, per-team; "Required" blocks uninstall, but disabling its individual hooks is undocumented). Team Rules can’t (prompt-only); project `.cursor/hooks.json` is opt-in/editable.

## GitHub source · per-team · per-org
- **GitHub as source:** ✅ via **Team Marketplaces** — import a repo, "Enable Auto Refresh"
  (needs Cursor GitHub App) re-indexes on push (≤10 min). Not a silent push; dashboard-registered,
  per-team, "Required" install.
- **Per team:** ✅ Team Rules (Teams+, mandatory), marketplace "Required" plugins, MCP lock (Enterprise).
- **Per org:** the Organization→Teams hierarchy + Org Groups is **Enterprise only**, and governs
  identity/spend/models — **not** plugin marketplaces (silent). On **Teams** tier there is no
  multi-team Organization (team-wide = org). Org-group policy resolves **most-permissive-wins**, so
  set the strictest value at team level. **Org-wide enforcement = MDM or Enterprise cloud hooks,
  not the marketplace.**
- **1-marketplace-per-team (Teams):** cap is on **sources, not plugins** — one repo can hold many
  plugins (`.cursor-plugin/marketplace.json`). Workaround: **add Evalon to the team's existing
  marketplace** (no nesting/cascade exists; external-URL `source` undocumented, so vendor/submodule
  into that repo). Lifting the cap = Enterprise or MDM.
- **"Required" is admin-set**, not user-set; a user can only self-install (opt-in).

## Automating config
**Admin API** (`api.cursor.com`, Basic auth, Team+) automates: members/audit/usage/spend (read),
spend limits (Ent), directory/billing groups, model access (Ent preview), repo blocklists.
**No API** for: Team Rules, hooks, MCP allowlist, plugin publishing, extension allowlist, member
invite (dashboard/MDM/GitHub-sync only). **SCIM** (Ent+SSO): users/groups only. **Service
accounts** (Ent): CI tokens (`CURSOR_API_KEY`). No admin CLI.

**Patterns:** (1) **Team config-as-code** = GitHub plugin repo → team marketplace Auto Refresh →
"Required"; every push ships, only first-time registration is manual. (2) **API-less governance**
(hooks/MCP/extensions) → generate static MDM files in CI → Jamf/Intune/Kandji. (3) Members/groups
→ SCIM + directory-groups API. (4) Monitoring → service accounts pull audit logs / set policy.

## CLI (`cursor-agent`)
Terminal/headless agent with non-interactive **print mode** (`-p`) for CI. **Hooks in CLI:
officially silent; community-reported as limited (only `beforeShellExecution`/`afterShellExecution`).**
CLI config = `~/.cursor/cli-config.json` + project `.cursor/cli.json` (permissions only); whether
it reads `hooks.json`/MDM/plugins is **undocumented**. **⚠ Bypass risk:** if IDE hooks don't fire
under the CLI it's an enforcement escape. No clean fix: `AllowedTeamId` only locks the account, and network/EDR egress inspection enforces below the editor — a true close needs CLI hook parity or blocking the CLI.

## Open items / risks
- **No GitHub-native silent distribution** → CI publishes to MDM/dashboard/marketplace.
- **Silent enforcement needs MDM or Enterprise**; Teams = visible "Required" plugins + Team Rules.
- **`failClosed` vs availability** — blocking makes the runtime a hard inner-loop dependency; pre-stage + warm on `sessionStart`.
- **Hook maturity** — no GA label; CLI partial coverage; `afterFileEdit` bugs; Windows shell undocumented.
- **Trust** — checksum + macOS notarization / Windows signing.

## Validation gaps (POC)
- Hooks `deny` in the IDE per OS; native-`.exe` `command` with no shell on Windows.
- MDM push of system `hooks.json` (mac `.mobileconfig`, Win ADMX, Linux `policy.json`).
- Team Marketplace "Required" round-trip; cloud per-OS targeting syntax; Teams-tier admin-API key.
- Plugin per-OS without MDM: single host-native launcher reliability (Git-Bash PowerShell bug); two-command idiom unverified.
- CLI (`cursor-agent`) hook coverage + closing the bypass.
- Does a file-dropped local plugin (`~/.cursor/plugins/local/`) auto-activate, and can it be locked? (likely not — no MDM plugin-enable key).
- Claude-format hook compat (`third-party-hooks`) coverage for Evalon's hooks.

## Action items
**Build**
- [ ] Confirm Bun launcher runs as a hook `command` (stdin→stdout permission JSON) on all 6 targets (**L4**).
- [ ] Map Cursor events → Evalon decisions (`deny`/`ask`/`updated_input`); set `failClosed` strategy; test Claude-compat path.
- [ ] Per-OS `hooks.json` templates + installer that writes the right `command` (**L3**).
- [ ] Package the plugin + GitHub repo + Cursor GitHub App + Auto Refresh.

**Decide**
- [ ] Per customer: **MDM available?** → if yes, go MDM regardless of tier; else Enterprise? / Teams? via the tree.
- [ ] `failClosed` vs availability (pre-stage runtime, warm on `sessionStart`).
- [ ] Trust: checksum + macOS notarization / Windows signing.

**Integrate**
- [ ] CI: build 6 binaries → generate per-OS `hooks.json`/MDM profiles → publish plugin to GitHub.
- [ ] Admin API / service accounts for audit, spend limits, repo/model policy.

## Sources
- Hooks: cursor.com/docs/hooks · /docs/agent/hooks · /docs/reference/third-party-hooks
- Plugins / marketplaces: cursor.com/docs/plugins · /docs/reference/plugins · /marketplace
- Rules: cursor.com/docs/context/rules · MCP: /docs/mcp
- Enterprise / MDM: cursor.com/docs/enterprise/deployment-patterns · /enterprise/model-and-integration-management · /enterprise/organizations
- Teams / SSO / Admin API / SCIM / service accounts: cursor.com/docs/account/teams/{dashboard,sso,admin-api,scim} · /docs/api · /docs/account/enterprise/service-accounts
- CLI: cursor.com/docs/cli/overview · /docs/cli/reference/configuration
- Extensions / Open VSX: cursor.com/help/customization/extensions · open-vsx.org
