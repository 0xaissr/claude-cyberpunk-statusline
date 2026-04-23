# Codex Multi-Backend Statusline Design

- **Date**: 2026-04-23
- **Status**: Approved
- **Goal**: Evolve `cyberpunk-statusline` from a Claude-only status line into a shared framework that supports Claude and Codex with one repo, one theme system, and one primary config surface.

## 1. Motivation

The current project has a reusable rendering core hidden inside a Claude-specific shell script. The renderer mostly cares about a few normalized fields such as model, workspace directory, rate limits, context usage, cost, and time. The Claude-only coupling lives around that renderer:

- installation writes Claude `statusLine` config
- effort is read from `~/.claude/settings.json`
- daily cost is read from Claude project logs or `ccusage`
- iTerm2 tab tint hooks are installed into Claude settings

The target state is a multi-backend framework:

1. One repository.
2. One shared theme/config model.
3. Backend-specific adapters for Claude and Codex.
4. Claude and Codex should look as aligned as possible.
5. When a backend cannot provide a field, the block should degrade gracefully rather than breaking.

## 2. Product Decision Summary

The approved direction is:

- Support **Claude and Codex in the same repo**.
- Keep **one shared configuration** rather than splitting into per-backend configs.
- Aim for **block parity when possible**.
- Use a **common runtime + backend adapters** architecture.
- For Codex v1, prefer a stable minimum integration over pretending unsupported telemetry exists.

## 3. Non-Goals For V1

These are explicitly out of scope for the first Codex-capable version:

- inventing synthetic context or rate-limit values for Codex
- reimplementing Codex as a custom plugin-first product
- moving Claude iTerm2 tab-state behavior into a backend-agnostic feature
- changing the theme schema
- splitting the repo into separate Claude and Codex products

## 4. Architecture

### 4.1 Layering

The repository should be split into three layers.

#### Core

`core/` owns backend-agnostic logic:

- config loading and defaults
- theme loading
- color helpers
- block rendering
- classic/rainbow layout assembly
- normalized payload handling

The core must not read `~/.claude/*`, `~/.codex/*`, or backend-specific hook payloads directly.

#### Adapters

`adapters/claude/` and `adapters/codex/` own backend-specific concerns:

- parse raw input from the host
- normalize it into the core schema
- install or remove host-specific integration
- expose backend-specific optional features

Claude-specific files such as tab-state helpers stay in the Claude adapter boundary.

#### Entrypoints

Repo-root scripts remain the public interface:

- `install.sh`
- `configure.sh`
- `uninstall.sh`
- backend render entrypoints if needed

The internal structure can change, but user-facing commands should stay simple.

### 4.2 Recommended Repository Shape

One acceptable target shape is:

```text
cyberpunk-statusline/
  core/
    config.sh
    render.sh
    blocks.sh
    theme.sh
    schema.sh
  adapters/
    claude/
      render.sh
      install.sh
      uninstall.sh
      tab-state.sh
      lib-tab-state.sh
    codex/
      render.sh
      install.sh
      uninstall.sh
      lib-hooks.sh
  themes/
  tests/
    core/
    adapters/
      claude/
      codex/
    installers/
  install.sh
  configure.sh
  uninstall.sh
```

The exact filenames can vary, but the ownership boundary should not.

## 5. Common Runtime Schema

The renderer should consume one normalized schema regardless of backend:

```json
{
  "agent": {
    "kind": "claude|codex",
    "session_id": "..."
  },
  "model": {
    "id": "...",
    "display_name": "...",
    "effort": "low|medium|high|xhigh|null"
  },
  "workspace": {
    "current_dir": "..."
  },
  "git": {
    "branch": "..."
  },
  "context_window": {
    "used_percentage": 58
  },
  "rate_limits": {
    "short_window": {
      "used_percentage": 76,
      "resets_at": 1234567890,
      "label": "5H"
    },
    "long_window": {
      "used_percentage": 33,
      "resets_at": 1234567890,
      "label": "7D"
    }
  },
  "cost": {
    "daily_usd": 12.34
  },
  "capabilities": {
    "context": true,
    "rate_limits": true,
    "cost": true,
    "effort": true
  }
}
```

The schema is intentionally close to the current renderer inputs so migration can be incremental.

## 6. Block Mapping Policy

### 6.1 Fully Shared Blocks

These blocks should work on both Claude and Codex in v1:

- `model`
- `directory`
- `git`
- `time`

Mapping rules:

- `model` comes from the backend adapter.
- `directory` is mapped from host payload to `workspace.current_dir`.
- `git` is always resolved locally from the working directory.
- `time` is generated locally by the renderer.

### 6.2 Claude-Native Blocks

These blocks remain first-class on Claude:

- `context`
- `rate_5h`
- `rate_7d`
- `cost`
- `effort`

### 6.3 Codex Fallback Policy

For Codex v1:

- `context` displays unavailable state unless an official source is available.
- `rate_5h` and `rate_7d` display unavailable state unless an official source is available.
- `cost` displays unavailable state unless a reliable Codex-native source is available.
- `effort` displays only if the adapter can retrieve it from an official Codex source.

Unavailable must be treated as a valid backend capability state, not a runtime error.

## 7. Configuration Model

The current flat config should evolve into shared settings plus backend integrations:

```json
{
  "theme": "terminal-glitch",
  "blocks": [
    "model",
    "context",
    "rate_5h",
    "rate_7d",
    "directory",
    "git",
    "time"
  ],
  "symbol_set": "unicode",
  "spacing": "compact",
  "style": "rainbow",
  "integrations": {
    "claude": {
      "enabled": true,
      "tab_state": {
        "enabled": true,
        "running": "accent_1",
        "waiting": "warning",
        "idle": "accent_3",
        "error": "alert"
      }
    },
    "codex": {
      "enabled": true,
      "hooks": {
        "enabled": true
      }
    }
  },
  "behavior": {
    "hide_unavailable_blocks": false
  }
}
```

Policy:

- visual settings stay shared
- backend-specific installation/config lives under `integrations.*`
- block visibility stays shared
- behavior flags like `hide_unavailable_blocks` remain global unless proven backend-specific

## 8. Install And Configure UX

### 8.1 Installation

`install.sh` should:

1. detect whether `claude` and `codex` are installed
2. offer `Claude`, `Codex`, or `Both` when both are available
3. run only the selected backend installers
4. keep the current Claude-only experience lightweight when Claude is the only installed host

### 8.2 Configure Wizard

`configure.sh` should stay single-source:

- shared theme and block steps remain common
- add a backend selection step
- show backend-specific substeps only when relevant
- keep Claude tab-state configuration within the Claude integration branch

### 8.3 Uninstall

`uninstall.sh` should:

- support removing Claude integration, Codex integration, or both
- only remove hooks/config entries written by this repo
- leave unrelated user settings intact

## 9. Claude Adapter

The Claude adapter owns:

- Claude `statusLine` installation
- parsing Claude stdin payloads
- effort fallback from Claude settings
- Claude cost collection from Claude-native sources
- iTerm2 tab-state hook lifecycle

The Claude experience should remain functionally equivalent during migration.

## 10. Codex Adapter

Codex v1 should prefer hooks-based integration instead of a plugin-first design.

Responsibilities:

- parse Codex hook/event payloads into the normalized schema
- install/remove Codex hook configuration
- provide a stable minimum render path for model, directory, git, and time

Codex v1 should not claim parity for unavailable telemetry.

### 10.1 Codex Integration Policy

Codex integration should:

- use official Codex hook/config surfaces
- keep the adapter thin because Codex hooks are still evolving
- avoid coupling Codex support to experimental plugin behavior when hooks are sufficient

### 10.2 Codex V1 Event Surface

Start with the smallest useful event set:

- `SessionStart`
- `UserPromptSubmit`
- `Stop`

Additional events can be added later after the integration proves stable.

## 11. Compatibility And Migration

The migration must be non-breaking for existing Claude users.

### 11.1 Legacy Config Support

If `config.json` does not contain `integrations`, treat it as legacy Claude mode:

- `integrations.claude.enabled = true`
- `integrations.codex.enabled = false`

### 11.2 Theme Compatibility

Existing theme files remain unchanged in v1.

### 11.3 Incremental Refactor Strategy

The recommended sequence is:

1. extract normalized payload handling and a core renderer
2. move Claude rendering onto the new architecture without feature loss
3. add Codex adapter and Codex installer support
4. then update install/configure UX for multi-backend operation

## 12. Testing Strategy

Testing should split by responsibility.

### 12.1 Core Tests

Core tests should feed normalized fixtures into the renderer and verify:

- non-empty output
- all spacing modes
- rainbow/classic styles
- unavailable field rendering

### 12.2 Adapter Tests

Adapter tests should verify raw-input-to-normalized-payload mapping:

- `tests/adapters/claude/*`
- `tests/adapters/codex/*`

### 12.3 Installer Tests

Installer tests should verify merge/remove behavior for both hosts:

- Claude settings mutation preserves unrelated hooks
- Codex hooks mutation preserves unrelated hooks
- uninstall removes only this repo's entries

## 13. Risks

The main risks are:

1. Codex hooks are still evolving, so the Codex adapter must stay thin.
2. Codex does not currently expose all Claude-equivalent telemetry, so unavailable states must be intentional.
3. The shell refactor touches installation, runtime, and tests, so the migration should be phased rather than all-at-once.

## 14. Success Criteria

The design is successful when:

1. Claude users can upgrade without losing current functionality.
2. Codex users can install the same project and get a working themed status line.
3. The renderer no longer depends directly on Claude-specific files or payload shapes.
4. Unsupported Codex blocks degrade gracefully.
5. Theme and block configuration stays shared across backends.
