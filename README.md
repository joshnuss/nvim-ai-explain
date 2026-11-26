# NVIM AI Explain

Explain code in a split pane using Codex or Claude Code.

Requires Neovim 0.9+ and a signed-in CLI.

```sh
./try.sh                              # Codex, no install
AI_EXPLAIN_PROVIDER=claude ./try.sh   # Claude
```

- `,ae` explains the selection or enclosing function (current line as fallback). LSP supplies references when available.
- `Ctrl-w j` enters the split. `q` closes it.

```lua
require("ai_explain").setup({
  provider = "codex",      -- or "claude"
  model = "gpt-6.2-sol",   -- omit for CLI default
  fast_mode = true,        -- optional, requires provider support
  view = "split",          -- or "float"
})
```

Fast mode may cost more. Local CLI session history is disabled. Provider retention applies.
