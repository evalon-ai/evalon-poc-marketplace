# Evalon Cursor Plugin — Distribution Research & Mapping (POC)

> **Research only — nothing implemented.** Maps the Claude Code 4-layer concept
> (`readme-claude.md`) to Cursor: trigger, OS handling, runtime, distribution (incl. plugin
> source-from-GitHub, per-team/per-org, and automation). Claims from official Cursor docs
> (Oct 2026); uncertainties flagged. Sources at end.

## Goal
Evalon's hook-based agent on every Cursor dev machine: **central, ideally silent enforcement**;
**intercept & block**; **OS-agnostic** (mac/win/linux × x64/arm64); **no Node**.

## Conclusions
**Recommendation — ship a plugin from a GitHub marketplace.**
- **Enterprise / Teams:** publish the plugin to **Evalon's GitHub marketplace**, register it, and set
  it **"Required"** — org-wide on **Enterprise**, or **per team** on **Teams** (**recipe A3**).
- **Teams + customer already uses their one marketplace:** the **1-marketplace-per-team cap**
  (Teams only) blocks a second one, so **add Evalon's plugin to the customer's existing marketplace**
  via an external-GitHub `source` entry (**recipe A4**). *(Enterprise has no cap — just add Evalon's
  own marketplace, A3.)*
- **Backup plan:** **MDM** (system-path `hooks.json` + binary) where it's available and silent,
  non-bypassable enforcement is required — see the decision tree and **Distribution vehicles** below.

**Two implementation depths:**
- **Quick win — a plugin whose `hooks.json` runs `npx`, OS-agnostic (recipe A5):** the same entry
  on every OS (npm resolves the build); no per-OS dispatch, bootstrap, or native binary. **Coverage
  gap:** machines **without Node** aren't protected.
- **Full chain — no reliance on installed Node:**
  - **L1 Distribution** — the **plugin** (GitHub marketplace, "Required").
  - **L2 Trigger** — the plugin's **embedded hooks** (`hooks/hooks.json`).
  - **L3 OS handling** — **two entries per event**, a `.ps1` and a `.sh`. Because a Windows + Git-Bash
    box can run **both**, the `.sh` **checks whether a PowerShell runner is present and backs off**
    when it is (deferring to the `.ps1` on Windows) — so exactly one does the work.
  - **L4 Runtime** — a **portable, self-contained runtime per OS/arch** (the Bun-compiled binary /
    portable Node), so there's **no dependency on a system-installed Node**.

**Updatability — start quick, upgrade in place.** Both depths ship as the **same plugin**, so moving
from the **quick win** (L1 + L2 + `npx`, A5) to the **full chain** (L1–L4 native, no Node) is just a
**new plugin version**: publish it to the marketplace and **Auto Refresh propagates it
automatically** — Cursor re-indexes the marketplace **at most once every ~10 min** after a push (the
IDE then pulls the new copy, sometimes slower/less reliably). No re-provisioning or customer action;
**bump the plugin `version`** to signal the update.

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
channel that ships **both `hooks.json` and the binary** (one installer), silent and non-bypassable.
**Without MDM**, distribution shifts to the **plugin/bootstrap** (all no-MDM tiers) — plus, on
**Enterprise**, the alternative of **cloud-dashboard hooks**. See the branches below.

```
MDM available (Jamf / Intune / Kandji)?          ← ask first
│
├─ YES ─► ① hooks.json via MDM system path   — use regardless of Cursor tier
│          • ANY tier; silent, non-bypassable, org-wide (device)
│          • MDM runs an installer → system hooks.json + per-OS binaries → COMPLETE (one artifact)
│          • CLI gap: cursor-agent may skip hooks — mitigate (AllowedTeamId account-lock + network/EDR egress); full close needs CLI hook parity or blocking the CLI
│
└─ NO MDM ─► vehicle depends on tier (default binary path = sh/PowerShell BOOTSTRAP: S3 + checksum, no Node;
          │             quick-win alt = npx plugin where Node is present — A5)
          │
          ├─ Enterprise ─► TWO options (can combine):
          │     ① TEAM MARKETPLACE "Required" PLUGIN — GitHub-sourced, auto-refresh, config-as-code
          │        → scalable & versioned; bundles the bootstrap; "Required" = can't-uninstall (visible).
          │     ② CLOUD-DASHBOARD HOOKS — silent, no MDM, Enterprise-only; pushed on login +
          │        re-synced ~30 min; OS-targeted; also run in cloud agents. BUT config is a manual
          │        per-hook FORM (no matcher, no Admin API) → tedious, doesn't scale; ⚠ delivery
          │        sometimes doesn't materialize → validate.
          │     (Prefer ① for scalable git-driven rollout; use ② when you need silent / people-tracking
          │      enforcement and can tolerate manual form entry. MDM still beats both if available.)
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
selected by a fail-open bootstrap. **On Windows, invoke scripts via an explicit `sh`/`powershell` prefix, never a bare `.sh` path** (a bare path opens the file in an editor via file association; the prefix makes it fail cleanly when the interpreter is absent). The community `sh`+`powershell` dual-entry idiom is
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
**Enterprise-only.** Admins configure hooks in the **web dashboard** ([https://cursor.com/dashboard/team-content?section=hooks](https://cursor.com/dashboard/team-content?section=hooks), Enterprise login); Cursor **pushes them to every
member's machine on login and re-syncs ~every 30 min** — *no MDM, no per-repo setup*. Coverage
**tracks the person** (follows them into any repo they open), and the same hooks **also run inside
cloud agents**. Precedence **Enterprise-managed > Team (dashboard) > Project > User**, so dashboard
hooks outrank anything a user sets. This is the **silent alternative to the "Required" plugin**:
same enforcement, nothing visible in a marketplace, nothing for the user to opt into.

**Scale caveat.** The dashboard is a **manual per-hook form** (no `matcher`, and the Admin API does
**not** cover hooks), so every hook — and every OS variant — is entered by hand and isn't
versioned. Fine for a few hooks; **tedious and non-scalable** beyond that. For config-as-code /
git-driven rollout, prefer the **GitHub-sourced plugin (A3)**; reach for cloud-dashboard hooks when
you specifically need the **silent, people-tracking** delivery.

It distributes **hook definitions (config), not the binary** — identical binary story to the no-MDM
plugin. So a `sessionStart` hook runs the **bootstrap** to install the per-OS launcher, and the
enforcement hooks point at it; only the *delivery channel* differs (silent cloud push vs. visible
plugin).

**OS-specific config — it's a dashboard _form_, not a file upload.** Each team hook is a **Command
Hook created in the dashboard form**; its fields are **hook name · hook type · hook step** (the
event, e.g. *Before Tool Use*) **· script content · supported operating systems** ([form fields + screenshots](https://forum.cursor.com/t/team-hooks-dashboard-does-not-allow-configuring-a-matcher/167411)). **Per-OS
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
  (needs Cursor GitHub App) re-indexes on push (**at most once / ~10 min**; rapid pushes batched to
  the latest commit; the dashboard updates in ~1–2 min, the IDE then pulls its local copy, sometimes
  slower/less reliably). Not a silent push; dashboard-registered, per-team, "Required" install.
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
- Team-hooks dashboard form (fields, no-matcher, screenshots): https://forum.cursor.com/t/team-hooks-dashboard-does-not-allow-configuring-a-matcher/167411
- Plugins / marketplaces: cursor.com/docs/plugins · /docs/plugins/building (marketplace.json `source`) · /docs/reference/plugins · /marketplace
- Plugin update / Auto-Refresh sync delay (re-index at most once / ~10 min; IDE-lag reports): cursor.com/docs/plugins · forum.cursor.com/t/cursor-2-6-team-marketplaces-for-plugins/153484
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
> supported OS; **no `matcher`**); ✅ `${CURSOR_PLUGIN_ROOT}` expansion; ✅ plugin.json fields + `hooks` wiring
> (cursor/plugins `plugin.schema.json`).

### A1 · Enterprise cloud — one OS-independent config via `npx`
**Idea:** a single team hook whose command is `npx`, so **one entry covers mac/win/linux** (npm
resolves the right build). **Trade-off:** requires **Node/npx on every machine** — reintroduces the
Node dependency the native-binary paths avoid. See **A5** for the
**plugin-delivered** npx variant (the recommended quick win, consistent with shipping a plugin).

**Steps**
1. Publish the hook to npm as `@evalon/cursor-hook` (bin = a Node CLI that reads the hook JSON on stdin and prints the permission JSON on stdout).
2. Dashboard ([https://cursor.com/dashboard/team-content?section=hooks](https://cursor.com/dashboard/team-content?section=hooks)) → **Team Hooks → Create Command Hook**: step **Before Tool Use**; script content `npx -y @evalon/cursor-hook`; Supported OS **macOS + Windows + Linux** (all).
3. Save → syncs to members (~30 min / next login).

```json
// Effective hooks.json Cursor assembles on EVERY machine (one OS-independent entry)
{ "version": 1, "hooks": {
  "beforeShellExecution": [
    { "command": "npx -y @evalon/cursor-hook", "failClosed": false }   // failClosed decision: see A5
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
2. Dashboard ([https://cursor.com/dashboard/team-content?section=hooks](https://cursor.com/dashboard/team-content?section=hooks)) → create, per OS: a **Session Start** hook (script content = that OS's bootstrap; Supported OS = that OS) **and** a **Before Tool Use** hook (script content = that OS's launcher path; Supported OS = that OS; `failClosed`).
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

### A3 · Enterprise / Teams — our GitHub marketplace + a plugin bundling the hooks
**Idea:** Evalon owns a marketplace repo (Enterprise allows multiple; on **Teams** it's the team's
**one** marketplace — within the cap) holding one plugin that bundles the hooks; registered once and
set **Required**.

**Steps**
1. Create the marketplace repo (tree below) and push.
2. Install the **Cursor GitHub App** on it (enables Auto Refresh).
3. Dashboard (Enterprise) → **Plugins → add team marketplace** → repo URL → **Enable Auto Refresh**.
4. Set `evalon-guard` install mode → **Required**.
5. Members receive it on next sync; the plugin's Session-Start bootstrap stages the launcher **and writes the OS-correct enforcement hook** (active from the next session — see *Enforcement wiring* below).

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
// plugins/evalon-guard/.cursor-plugin/plugin.json      ✅ fields per cursor/plugins plugin.schema.json
{
  "name": "evalon-guard",
  "version": "0.1.0",
  "description": "Evalon policy-enforcement hooks",
  "hooks": "hooks/hooks.json"
}
// `hooks` (string | object) = path to a hooks file OR an inline hooks object. Omit it and Cursor
// AUTO-DISCOVERS the conventional hooks/hooks.json. (Other optional keys: author, repository,
// rules, skills, commands, mcpServers, variables …)
```
```json
// plugins/evalon-guard/hooks/hooks.json
// Wiring: referenced by plugin.json "hooks", or auto-discovered at this conventional path.
// Command paths are relative to THIS file (${CURSOR_PLUGIN_ROOT} also expands).
{ "version": 1, "hooks": {
  // A plugin ships ONE hooks.json to every OS and entries have NO os field, so dispatch by listing
  // BOTH bootstraps: each interpreter exists only on its own OS, the other no-ops. Keep fail-open.
  "sessionStart": [
    { "command": "sh ./bin/evalon-bootstrap.sh" },
    { "command": "powershell -ExecutionPolicy Bypass -File ./bin/evalon-bootstrap.ps1" }
  ]
} }
```
**Plugin→hooks wiring (✅ resolved).** `plugin.json` has a `hooks` field (`string | object`) — a
path to a hooks file or an inline hooks object; omit it and Cursor **auto-discovers `hooks/hooks.json`**.
Either way the plugin's hooks load with no extra config.

**What picks sh vs powershell (✅ answered).** Nothing in the config — a plugin can't branch by OS.
The `sessionStart` entry lists **both** bootstraps; the wrong-OS one no-ops because that interpreter
is absent (so keep them **fail-open**). ⚠ *Git-Bash caveat:* if the Windows terminal profile is Git
Bash, `sh` **is** present, so the `sh` entry also runs on Windows — guard inside the script.

**Rule — always prefix the interpreter; never a bare script path.** Write `sh ./bootstrap.sh` and
`powershell -ExecutionPolicy Bypass -File ./bootstrap.ps1`. A **bare `.sh` path** (or an
extensionless shebang file) makes Windows resolve it by **file association and open it in an editor**
instead of running it; with an explicit `sh`/`powershell` prefix the launched program is the
**interpreter**, so on a machine without it the hook simply **fails cleanly** (no editor).

**If both interpreters are present (Windows + Git Bash), BOTH entries run.** Cursor executes every
configured entry for an event, so with `sh` on PATH the bootstrap fires **twice** (once via `sh`,
once via `powershell`) — risking double install/consolidation and `~/.cursor/hooks.json` races. Make
each script **self-guard** so only the OS-correct one does work, and make the write **idempotent +
lock-guarded**:
```sh
# bootstrap.sh — back off to the .ps1 on Windows: `powershell` is on PATH only on Windows
command -v powershell >/dev/null 2>&1 && exit 0
```
```powershell
# bootstrap.ps1 — bail off Windows
if (-not $IsWindows) { exit 0 }
```
⚠ Whether Cursor runs the two entries sequentially or concurrently is undocumented — assume
concurrent (hence the lockfile).

**Enforcement wiring (the real snag).** You can't name both `evalon-launcher` and
`evalon-launcher.exe` in one entry, and **dual-listing a `failClosed` enforcement entry would block
on the wrong OS** (its missing-path variant fails *closed*). So let the **bootstrap** — which already
knows its OS — install the native launcher **and write the OS-correct `beforeShellExecution` entry
to `~/.cursor/hooks.json` (or a system path)**. The plugin reliably contributes only the fail-open
`sessionStart` dual-bootstrap; the enforcement hook is written by whichever bootstrap ran. (Or
sidestep with A1's `npx`/`node` single cross-OS command, at the cost of a Node dependency.)

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
  .cursor-plugin/plugin.json      # ✅ name + `hooks` field (plugin.schema.json)
  hooks/hooks.json                # same bundled hooks as A3 (${CURSOR_PLUGIN_ROOT})
  bin/evalon-bootstrap.sh
  bin/evalon-bootstrap.ps1
```
⚠ Auto-refresh of an **external** source is reported stale-prone → validate propagation. Note: plugin-bundled `hooks.json` **does** support `matcher` (unlike the dashboard form), so tool-scoping is available here.

### A5 · Quick Win — a plugin whose `hooks.json` runs `npx` (OS-agnostic)
**Idea:** the simplest ship — a **plugin** whose bundled `hooks.json` calls **`npx @evalon/cursor-hook`**.
One entry works on every OS (npm resolves the right build), so **no per-OS dispatch (L3), no
bootstrap, and no native binary (L4)**. Distributed like any plugin — marketplace **"Required"**
(A3) or co-located in the customer's marketplace (A4). **Trade-off:** needs **Node/npx on the
machine**; machines **without Node** are **unprotected** (the coverage gap).

**Steps**
1. Publish the hook to npm as `@evalon/cursor-hook` (bin = Node CLI; stdin→stdout permission JSON).
2. Create the plugin (tree below) with a `hooks/hooks.json` that runs `npx`.
3. Distribute it exactly like **A3** (own marketplace, "Required") or **A4** (co-locate in the customer's marketplace) — only the `hooks.json` contents differ.

**Files created (in the plugin repo, or inside the marketplace repo as in A3)**
```
evalon-cursor-plugin/
  .cursor-plugin/plugin.json
  hooks/hooks.json
# plus the npm package (NOT committed): @evalon/cursor-hook (package.json + dist/hook.js)
```
```json
// .cursor-plugin/plugin.json
{ "name": "evalon-guard", "version": "0.1.0",
  "description": "Evalon policy-enforcement hooks (npx)",
  "hooks": "hooks/hooks.json" }
```
```json
// hooks/hooks.json — ONE OS-agnostic entry; npm resolves the right build per machine
{ "version": 1, "hooks": {
  "beforeShellExecution": [
    { "command": "npx -y @evalon/cursor-hook", "failClosed": false }
  ]
} }
```
**Why it's the quick win:** the plugin *is* the whole install — no L3 dual-entry, no L4 staging, no
first-run bootstrap window; `npx` handles OS/arch. ⚠ **`failClosed` decision:** with `npx`/Node
**missing**, a `failClosed: true` entry would **block the dev**; set **`failClosed: false`** (shown)
for the intended *coverage gap* — unprotected, not blocking — on Node-less machines. For full
no-Node coverage, use the native-binary chain (**A3** + L3/L4).

