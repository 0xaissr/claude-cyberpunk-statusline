---
name: cyberpunk-statusline:reinstall
description: Reinstall cyberpunk-statusline plugin from the marketplace. Use when user runs /cyberpunk-statusline reinstall or wants to update/reinstall the plugin.
---

# cyberpunk-statusline Reinstall

Reinstall the plugin by clearing the local cache and letting Claude Code re-fetch from the marketplace.

## Steps

### 1. Backup current config

Read `${CLAUDE_PLUGIN_ROOT}/config.json` and save its contents to a variable. If the file doesn't exist, skip this step.

### 2. Clear plugin cache and marketplace clone

Run these commands:

```bash
rm -rf ~/.claude/plugins/cache/cyberpunk-statusline-marketplace
rm -rf ~/.claude/plugins/marketplaces/cyberpunk-statusline-marketplace
```

### 3. Inform the user

Tell the user:

> Plugin cache cleared. Please restart your Claude Code session now.
>
> After restart, the plugin will be automatically re-fetched from GitHub with the latest version.

If a config backup was saved in step 1, also tell them:

> Your previous config has been backed up. After restart, run `/cyberpunk-statusline configure` to reconfigure, or I can restore your previous settings.

Show the backed-up config JSON so they can see what they had.
