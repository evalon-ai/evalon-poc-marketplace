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
└─ NO MDM ─► vehicle depends on tier (binary always via the sh/PowerShell BOOTSTRAP: S3 + checksum, no Node/npx)
          │
          ├─ Enterprise ─► TWO options (can combine):
          │     ① CLOUD-DASHBOARD HOOKS — silent, no MDM, Enterprise-only. Configured in the web
          │        dashboard, pushed to every member on login + re-synced ~30 min; OS-targeted;
          │        also run in cloud agents. A sessionStart hook runs the bootstrap; enforcement
          │        hooks point at the launcher.  ⚠ delivery sometimes doesn't materialize → validate.
          │     ② TEAM MARKETPLACE "Required" PLUGIN — visible, can't-uninstall; bundles the same
          │        bootstrap. Use for the plugin UX or when cloud delivery is unreliable.
          │     (Prefer ① for silent / people-tracking enforcement; MDM still beats both if available.)
          │
          ├─ Teams ──────► team marketplace "Required" plugin (bootstrap)   (1-marketplace cap)
          └─ Pro / Free ─► self-service install from marketplace            (opt-in, not enforced)

          validate: Windows hook→PowerShell reliability; first-run enforce window; S3 egress;
                    cloud-dashboard hook delivery (Enterprise)
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
PowerShell bootstrap bug). **Enterprise cloud** does L3 at the delivery
layer: each dashboard hook has a **"Supported operating systems"** field, so you author one hook
entry per OS (no in-file branching) — but that form has **no `matcher`**, so tool-scoping must live
in the script.

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

### Cloud-dashboard hooks (Enterprise) — the silent, no-MDM option
**Enterprise-only.** Admins configure hooks in the **web dashboard**; Cursor **pushes them to every
member's machine on login and re-syncs ~every 30 min** — *no MDM, no per-repo setup*. Coverage
**tracks the person** (follows them into any repo they open), and the same hooks **also run inside
cloud agents**. Precedence **Enterprise-managed > Team (dashboard) > Project > User**, so dashboard
hooks outrank anything a user sets. This is the **silent alternative to the "Required" plugin**:
same enforcement, nothing visible in a marketplace, nothing for the user to opt into.

It distributes **hook definitions (config), not the binary** — identical binary story to the no-MDM
plugin. So a `sessionStart` hook runs the **bootstrap** to install the per-OS launcher, and the
enforcement hooks point at it; only the *delivery channel* differs (silent cloud push vs. visible
plugin).

**OS-specific config — it's a dashboard _form_, not a file upload.** Each team hook is a **Command
Hook created in the dashboard form**; its fields are **hook name · hook type · hook step** (the
event, e.g. *Before Tool Use*) **· script content · supported operating systems**. **Per-OS
targeting = the "Supported operating systems" field on each hook.** So you **do not upload a
`hooks.json` per OS** — you **create one hook entry per OS**: same hook step, each with its own
*script content* (pointing at that platform's launcher) and its own Supported-OS tag. Cursor
**delivers each hook only to matching-OS machines** and assembles the machine-side `hooks.json`
itself, so the file a given machine ends up with is a plain single-OS file (the entry schema has
**no OS field**):

```json
// What ONE machine receives (Cursor-assembled). You author the equivalent per-OS entries in the
// dashboard FORM (script content + Supported-OS) — NOT as an uploaded hooks.json file.

// macOS machine → effective hooks.json
{ "version": 1, "hooks": { "beforeShellExecution": [
  { "command": "/Library/Application Support/Evalon/bin/evalon-hook-darwin-arm64", "failClosed": true } ] } }
// Windows machine → effective hooks.json
{ "version": 1, "hooks": { "beforeShellExecution": [
  { "command": "C:\\Program Files\\Evalon\\bin\\evalon-hook-windows-x64.exe", "failClosed": true } ] } }
```

**⚠ No `matcher` in the dashboard form.** The form exposes no `matcher` field (open feature
request), so dashboard team hooks **can't be scoped to specific tools/commands** — the hook fires
broadly and Evalon must **filter inside its own script**, or fall back to MDM/project `hooks.json`
(which *do* support `matcher`) where tool-level scoping matters.

You add the **bootstrap** the same way — another hook entry with **hook step = Session Start**,
*script content* = the per-OS bootstrap (`sh` on mac/linux, PowerShell on Windows), Supported-OS set
per platform — so the launcher is pre-staged before the enforcement hooks fire:

```json
// sessionStart bootstrap (per OS) — installs/updates the launcher, then enforcement hooks use it.
{ "hooks": { "sessionStart": [
  { "command": "/Library/Application Support/Evalon/bin/evalon-bootstrap.sh" } ] } }      // mac/linux
{ "hooks": { "sessionStart": [
  { "command": "powershell -ExecutionPolicy Bypass -File C:\\Program Files\\Evalon\\bin\\evalon-bootstrap.ps1" } ] } }  // windows
```

**Caveat — delivery reliability.** Dashboard hooks are **reported to sometimes not materialize** at
the endpoint path Cursor reads; MDM-delivered `hooks.json` is the more reliable enforcement channel.
On Enterprise: prefer **MDM if available**, use **cloud-dashboard hooks** as the silent no-MDM
option, and **validate end-to-end delivery** before relying on it (two open unknowns remain: the
Supported-OS field's granularity/labels, and whether *script content* can reference a path or is
inline-only).

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
  plugins (`.cursor-plugin/marketplace.json`), and a plugin entry's `source` can point at an
  **external GitHub repo**, so Evalon can co-locate in a team's existing marketplace and still
  update from its own repo (see **Co-locating Evalon via external `source`** below). No
  nesting/cascade between marketplaces exists. Lifting the cap = Enterprise or MDM.
- **"Required" is admin-set**, not user-set; a user can only self-install (opt-in).

### Co-locating Evalon via external `source` (no own marketplace needed)
When a team has already spent its single marketplace, don't ask for a second one — add Evalon as an
**entry in that repo's** `.cursor-plugin/marketplace.json`. A plugin `source` may be a **local
path** *or* an **external GitHub repo object**, so Evalon's code stays in Evalon's repo and ships on
push; they add the one entry once and never edit their repo again:

```json
// <their-marketplace-repo>/.cursor-plugin/marketplace.json
{
  "name": "acme-team-marketplace",
  "plugins": [
    { "name": "acme-internal", "source": "./plugins/acme-internal" },
    { "name": "evalon-guard",
      "source": { "type": "github", "owner": "evalon-ai", "repo": "evalon-cursor-plugin" } }
  ]
}
```

**Not a git submodule.** A submodule pins a commit (your push doesn't move their pointer — they'd
`git submodule update --remote` + commit + push every release), and Cursor's marketplace reader
almost certainly doesn't `--recurse-submodules`, so the files may not resolve at all. The native
external `source` is the supported, update-on-push mechanism.

*Validate (Cursor refresh is reported stale-prone):* (1) whether auto-refresh re-pulls the
**external** source's new commits or only re-reads the marketplace repo — reports show auto-refresh
missing plugin changes (manual Refresh + cache-clear + reinstall needed); (2) **bump the plugin
`version` each release** so updates are detected rather than relying on "latest on branch".

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
- Team Marketplace "Required" round-trip; Teams-tier admin-API key.
- **Cloud-dashboard hooks (Enterprise):** end-to-end delivery to the endpoint path (reported to sometimes not materialize → MDM more reliable); Supported-OS field granularity/labels; **no `matcher` in the dashboard form** → tool-scoping must be in-script.
- External-GitHub `source` in a shared marketplace: does auto-refresh propagate the **source** repo's new commits, or only the marketplace repo's? (reports show stale refresh).
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
- Plugins / marketplaces: cursor.com/docs/plugins · /docs/plugins/building (marketplace.json `source`) · /docs/reference/plugins · /marketplace
- Rules: cursor.com/docs/context/rules · MCP: /docs/mcp
- Enterprise / MDM: cursor.com/docs/enterprise/deployment-patterns · /enterprise/model-and-integration-management · /enterprise/organizations
- Teams / SSO / Admin API / SCIM / service accounts: cursor.com/docs/account/teams/{dashboard,sso,admin-api,scim} · /docs/api · /docs/account/enterprise/service-accounts
- CLI: cursor.com/docs/cli/overview · /docs/cli/reference/configuration
- Extensions / Open VSX: cursor.com/help/customization/extensions · open-vsx.org
## Appendix — Deployment recipes (steps · configs · files)

> **Legend.** ✅ verified against Cursor docs/forum · ⚠ illustrative (exact schema/UI not
> published — validate). ✅ `hooks.json` entry schema (`version`, `command`, `type`, `matcher`,
> `timeout`, `loop_limit`, `failClosed`); ✅ `marketplace.json` `source` (local path **or**
> `{type,owner,repo}`); ✅ dashboard team-hook form fields (name, type, step, script content,
> supported OS; **no `matcher`**); ✅ `${CURSOR_PLUGIN_ROOT}` expansion. ⚠ plugin manifest keys and
> plugin→hooks wiring.

### A1 · Enterprise cloud — one OS-independent config via `npx`
**Idea:** a single team hook whose command is `npx`, so **one entry covers mac/win/linux** (npm
resolves the right build). **Trade-off:** requires **Node/npx on every machine** — reintroduces the
Node dependency the native-binary paths avoid.

**Steps**
1. Publish the hook to npm as `@evalon/cursor-hook` (bin = a Node CLI that reads the hook JSON on stdin and prints the permission JSON on stdout).
2. Dashboard → **Team Hooks → Create Command Hook**: step **Before Tool Use**; script content `npx -y @evalon/cursor-hook`; Supported OS **macOS + Windows + Linux** (all).
3. Save → syncs to members (~30 min / next login).

```json
// Effective hooks.json Cursor assembles on EVERY machine (one OS-independent entry)
{ "version": 1, "hooks": {
  "beforeShellExecution": [
    { "command": "npx -y @evalon/cursor-hook", "failClosed": true }
  ]
} }
```

**Files created / modified**
```
@evalon/cursor-hook/            # published to npm (NOT committed to the team)
  package.json                  # { "name":"@evalon/cursor-hook", "bin":{ "evalon-cursor-hook":"dist/hook.js" } }
  dist/hook.js                  # stdin -> stdout permission logic
# Cursor: 1 dashboard Team Hook entry (no file you commit; machine hooks.json is Cursor-assembled)
```

### A2 · Enterprise cloud — one config per OS (native binaries, no Node)
**Idea:** one **Command Hook per OS**, each tagged with its Supported-OS and pointing at that
platform's native launcher. The dashboard ships **config only**, so a **Session-Start bootstrap**
stages the binary first.

**Steps**
1. Host the 6 native launchers + `bootstrap.sh`/`bootstrap.ps1` (e.g. S3 + checksums).
2. Dashboard → create, per OS: a **Session Start** hook (script content = that OS's bootstrap; Supported OS = that OS) **and** a **Before Tool Use** hook (script content = that OS's launcher path; Supported OS = that OS; `failClosed`).
3. Save → Cursor delivers each entry only to matching-OS machines.

```json
// macOS machine -> effective hooks.json
{ "version": 1, "hooks": {
  "sessionStart":         [ { "command": "/Library/Application Support/Evalon/bin/evalon-bootstrap.sh" } ],
  "beforeShellExecution": [ { "command": "/Library/Application Support/Evalon/bin/evalon-hook-darwin-arm64", "failClosed": true } ]
} }
```
```json
// Windows machine -> effective hooks.json   (Linux/WSL analogous with /opt/evalon/bin/...)
{ "version": 1, "hooks": {
  "sessionStart":         [ { "command": "powershell -ExecutionPolicy Bypass -File C:\\Program Files\\Evalon\\bin\\evalon-bootstrap.ps1" } ],
  "beforeShellExecution": [ { "command": "C:\\Program Files\\Evalon\\bin\\evalon-hook-windows-x64.exe", "failClosed": true } ]
} }
```

**Files created / modified**
```
# hosted (S3) — NOT committed to the team
evalon-hook-{darwin-arm64,darwin-x64,linux-x64,linux-arm64,windows-x64.exe,windows-arm64.exe}
evalon-bootstrap.sh, evalon-bootstrap.ps1
# Cursor: 2 dashboard hook entries per OS (Session Start + Before Tool Use)
```
⚠ No `matcher` in the dashboard form → scope inside the launcher. ⚠ Validate dashboard delivery (reported stale-prone) and `.ps1` reliability on Windows.

### A3 · Enterprise — our GitHub marketplace + a plugin bundling the hooks
**Idea:** Evalon owns a marketplace repo (Enterprise allows multiple) holding one plugin that
bundles the hooks; registered once and set **Required**.

**Steps**
1. Create the marketplace repo (tree below) and push.
2. Install the **Cursor GitHub App** on it (enables Auto Refresh).
3. Dashboard (Enterprise) → **Plugins → add team marketplace** → repo URL → **Enable Auto Refresh**.
4. Set `evalon-guard` install mode → **Required**.
5. Members receive it on next sync; the plugin's Session-Start bootstrap stages the launcher; the enforcement hook runs.

**Files created (in the marketplace repo)**
```
evalon-cursor-marketplace/
  .cursor-plugin/marketplace.json
  plugins/evalon-guard/
    .cursor-plugin/plugin.json
    hooks/hooks.json
    bin/evalon-bootstrap.sh
    bin/evalon-bootstrap.ps1
```
```json
// .cursor-plugin/marketplace.json                                   ✅ schema
{ "name": "evalon-marketplace",
  "plugins": [ { "name": "evalon-guard", "source": "./plugins/evalon-guard" } ] }
```
```json
// plugins/evalon-guard/.cursor-plugin/plugin.json                   ⚠ keys illustrative
{ "name": "evalon-guard", "version": "0.1.0", "description": "Evalon policy-enforcement hooks" }
```
```json
// plugins/evalon-guard/hooks/hooks.json   (bundled; ${CURSOR_PLUGIN_ROOT} ✅ expands)
{ "version": 1, "hooks": {
  "sessionStart":         [ { "command": "sh ${CURSOR_PLUGIN_ROOT}/bin/evalon-bootstrap.sh" } ],
  "beforeShellExecution": [ { "command": "${CURSOR_PLUGIN_ROOT}/bin/evalon-launcher", "failClosed": true } ]
} }
```
⚠ Plugin→hooks wiring (does Cursor auto-load `hooks/hooks.json`, or must `plugin.json` reference it?) is undocumented — validate. ⚠ One `command` per entry → use a host-native `evalon-launcher` that self-selects arch, or stage per-OS via the bootstrap (Windows `.ps1` caveat).

### A4 · Teams — add our plugin to the team's existing marketplace (external `source`)
**Idea:** the team keeps its one marketplace; Evalon lives in **its own** repo and is referenced by
an **external-GitHub `source`** entry, so it updates on push without touching their repo again.

**Steps**
1. Publish the plugin in Evalon's own repo (tree below).
2. Open a PR on the **team's marketplace repo** adding one entry to `.cursor-plugin/marketplace.json` (diff below).
3. Merge → the team marketplace auto-refreshes (GitHub App) and picks up `evalon-guard`.
4. Admin sets `evalon-guard` → **Required**.
5. Thereafter Evalon ships by pushing to **its own** repo; **bump `version`** to signal updates.

**File MODIFIED (in the team's marketplace repo)**
```diff
  // <team-marketplace-repo>/.cursor-plugin/marketplace.json          ✅ external source
  { "name": "acme-team-marketplace",
    "plugins": [
      { "name": "acme-internal", "source": "./plugins/acme-internal" },
+     { "name": "evalon-guard",
+       "source": { "type": "github", "owner": "evalon-ai", "repo": "evalon-cursor-plugin" } }
    ] }
```
**Files created (in Evalon's own repo `evalon-cursor-plugin`)**
```
evalon-cursor-plugin/
  .cursor-plugin/plugin.json      # ⚠ keys illustrative
  hooks/hooks.json                # same bundled hooks as A3 (${CURSOR_PLUGIN_ROOT})
  bin/evalon-bootstrap.sh
  bin/evalon-bootstrap.ps1
```
⚠ Auto-refresh of an **external** source is reported stale-prone → validate propagation. Note: plugin-bundled `hooks.json` **does** support `matcher` (unlike the dashboard form), so tool-scoping is available here.

