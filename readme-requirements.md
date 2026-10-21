# Evalon Agent Hooks — Requirements & Platform Support

What we need from each platform, and how well each one meets it.
- Platform details: `readme-claude.md`, `readme-cursor.md`, `readme-codex.md`.
- Tenant provisioning: `readme-seamless-provisioning.md`.

Legend: ✅ met · ⚠ partial or untested · ❌ not met

## Requirements

### Must-have

| ID | Requirement | Done when |
|---|---|---|
| **R1** | **Native centralized distribution.** We deploy from one central place, using the platform's own documented channels (marketplace, managed settings, MDM keys) and follow its terms. | We don't patch or wrap the agent, and nothing critical depends on undocumented files or APIs. |
| **R2** | **Admin-managed.** The customer admin deploys and enforces the hooks. Users get no prompt and can't remove or disable the hooks from their own settings. | Hooks run from the first session, and user config can't turn them off. Limits the platform documents (e.g. a local machine admin) are listed. |
| **R3** | **Simple one-time setup.** A short, documented setup by the customer admin, ideally in the admin console. MDM is fine if the customer already has it. | About 30 min, no per-user or per-machine steps. Repeating setup per workspace or team counts against this. |
| **R4** | **All OSes and architectures.** macOS, Windows and Linux, on x64 and arm64. | Works on all 6 targets. |
| **R5** | **No runtime dependency.** No need for Node or any other installed runtime. | Works on a clean machine. |
| **R6** | **Seamless tenant attribution.** The tenant ID comes with the same admin setup, with no extra changes on endpoints, or reports are linked to the tenant automatically. | Every report maps to one tenant. |
| **R7** *(new)* | **Can block.** Hooks can stop an agent action, not only watch it. | A pre-tool hook can deny an action. |
| **R8** *(new)* | **Surface coverage.** CLI, IDE, desktop app and CI, with any gaps documented. | Each surface is marked covered, partial or not covered. |
| **R9** *(new)* | **Fail-open.** If our handler fails or times out, the action continues. | The handler never blocks because of its own error. |

### Nice-to-have

| ID | Requirement | Note |
|---|---|---|
| **N1** | **Central updates.** Updates are pushed centrally and clients get them over time. | We already have our own update mechanism. |
| **N2** *(new)* | **Drift visibility.** We notice when a machine stops reporting. | This is how vendors deal with removal by a local admin. |
| **N3** *(new)* | **No MDM needed.** | Many customers don't manage developer machines with MDM. |

## Support matrix

| Req | Claude Code | Cursor | Codex |
|---|---|---|---|
| **R1** Native, central | ✅ Plugin marketplace + managed settings | ✅ Team marketplace, Enterprise cloud hooks or MDM | ✅ Managed `requirements.toml` + workspace plugin or MDM package |
| **R2** Admin-managed | ✅ Managed settings win; plugin is force-enabled. ⚠ A managed hooks change may show a one-time approval dialog | ✅ MDM / Enterprise cloud hooks. ⚠ Teams: "Required" plugin can't be uninstalled but is visible | ✅ Managed hooks can't be disabled by users. Plugin hooks alone are user-level, so enforcement lives in requirements |
| **R3** Setup | ✅ Paste JSON in the admin console | **Enterprise** ✅ Add Evalon's marketplace, set the plugin to "Required". **Teams** ⚠ Per team; only one marketplace allowed, so add our plugin to the team's existing marketplace if it has one | ⚠ Plugin: import once **per workspace**, UI only. Requirements: paste TOML. Sign-in lock: needs MDM |
| **R4** OS / arch | ✅ One `sh` script (Git Bash on Windows). ⚠ Linux untested | ⚠ No per-OS field; needs `sh` + `.ps1` entries | ✅ `command` + `command_windows`. ⚠ Untested |
| **R5** No runtime | ⚠ Portable runtime; tested on macOS only | ⚠ Same; the `npx` quick win needs Node | ⚠ Same; untested |
| **R6** Seamless tenant | ✅ Managed `env` var (tested locally) | ⚠ Plugin variable → hook untested; fallback: SSO email domain | ⚠ Admin-set managed hook with an Evalon ID; or the ChatGPT workspace ID (not 1:1 per org) |
| **R7** Block | ✅ | ✅ | ✅ ❌ WebSearch isn't hooked |
| **R8** Surfaces | ✅ CLI, IDE. ⚠ Bedrock/Vertex skip managed settings | ⚠ IDE ✅; CLI has limited hooks | ⚠ CLI, app ✅. IDE: no plugins. Cloud runs: `mcp_tool` hooks only |
| **R9** Fail-open | ✅ Default | ✅ Default (leave `failClosed` unset) | ✅ Default |
| **N1** Updates | ✅ Marketplace auto-update | ✅ Auto-refresh (~10 min) | ✅ Plugin daily sync; MDM path via our updater |
| **N2** Drift | ⚠ To build (heartbeat) | ⚠ To build | ⚠ To build |
| **N3** No MDM | ✅ | ⚠ Enterprise or Teams only | ⚠ Works, but personal-account or API-key sign-ins skip the org policy |

## Summary
- **Claude Code** — closest to full support: one admin-console paste covers R1–R3 and R6. Still to test: Windows and Linux.
- **Cursor** — fully meets R2 only on Enterprise or with MDM. R6 and CLI coverage are the weak points.
- **Codex** — strong enforcement through managed requirements, but the handler needs its own channel (MDM or workspace plugin). The plugin is set up per workspace, and the sign-in lock needs MDM.

## Open decisions
- Do we require Enterprise or MDM for full R2, or accept the ⚠ tiers and tell the customer?
- Do we list Evalon in OpenAI's public plugin directory to make Codex setup (R3) easier?
