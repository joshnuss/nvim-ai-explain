# NVIM AI Explain

Explain code in a split pane using Codex or Claude Code.

Requires Neovim 0.9+ and a signed-in CLI.

- `:AIExplain` explains the enclosing function or current line. Pass a range to explain selected lines. LSP supplies references when available.
- `Ctrl-w j` enters the split. `q` closes it.

```lua
require("ai_explain").setup({
  provider = "codex",      -- or "claude"
  model = "gpt-6.2-astra", -- omit for CLI default
  reasoning_effort = "medium",
  fast_mode = true,        -- optional, requires provider support
  view = "split",          -- or "float"
})
```

To map a key shortcut:

```lua
-- adds shortcut to <leader>a
vim.keymap.set({ "n", "x" }, "<leader>a", "<Plug>(AIExplain)")
```

## Development usage

```sh
./try.sh                              # Codex, no install
AI_EXPLAIN_PROVIDER=claude ./try.sh   # Claude
```
