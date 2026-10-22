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

One-glance view. Details and options: the **Requirements coverage** section at the top of each vendor doc (`readme-claude.md`, `readme-cursor.md`, `readme-codex.md`).

| Req | Claude Code | Cursor | Codex |
|---|---|---|---|
| **R1** Native, central | ✅ Marketplace + managed settings | ✅ Team marketplace | ✅ Managed requirements + installer |
| **R2** Admin-managed | ✅ ⚠ one-time approval dialog | ⚠ "Required" plugin; MDM option | ✅ ⚠ sign-in lock needs MDM |
| **R3** Setup | ✅ Admin-console paste | ✅ Enterprise · ⚠ Teams per team | ✅ TOML paste per workspace |
| **R4** OS / arch | ⚠ Linux untested | ⚠ Dual `sh` + `.ps1` | ✅ ⚠ untested |
| **R5** No runtime | ⚠ macOS only so far | ⚠ Bootstrap; `npx` needs Node | ⚠ Untested |
| **R6** Seamless tenant | ✅ Managed `env` var | ⚠ Plugin variable untested | ✅ `--org` in hooks |
| **R7** Block | ✅ | ✅ | ✅ ⚠ WebSearch not hooked |
| **R8** Surfaces | ⚠ Bedrock/Vertex gap | ⚠ CLI limited | ⚠ IDE untested; cloud limited |
| **R9** Fail-open | ✅ | ✅ | ✅ |
| **N1** Updates | ✅ Auto-update | ✅ Auto-refresh | ✅ Self-update |
| **N2** Drift | ⚠ To build | ⚠ To build | ⚠ To build |
| **N3** No MDM | ✅ | ✅ Plugin path | ⚠ Sign-in gap |

## Summary
- **Claude Code** — closest to full support: one admin-console paste covers R1–R3 and R6. Still to test: Windows and Linux.
- **Cursor** — fully meets R2 only on Enterprise or with MDM. R6 and CLI coverage are the weak points.
- **Codex** — one TOML paste in the Admin Console covers R1–R3 and R6: managed hooks enforce, a hash-pinned installer delivers the handler, and the tenant ID rides in the hooks. No plugin needed. The sign-in lock needs MDM.

## Open decisions
- Do we require Enterprise or MDM for full R2, or accept the ⚠ tiers and tell the customer?
