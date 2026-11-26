# Neovim AI Explain Plugin

Explain code in a split pane using Codex or Claude Code.
Requires Neovim 0.9+ and a signed-in CLI.

## Demo

https://github.com/user-attachments/assets/237a499d-f022-4bf5-ad6a-30024b5fc297

## Usage

- `:AISummary` explains the enclosing function, current line, or supplied range from the snippet alone.
- `:AIUsage` searches the project for uses and cites `file:line` examples, using LSP references when available.
- `Ctrl-w j` enters the split. `q` closes it.

## Configure

```lua
require("ai_explain").setup({
  provider = "codex",      -- or "claude"
  model = "gpt-6.2-astra", -- omit for CLI default
  reasoning = "medium",
  fast = true,        -- optional, requires provider support
  view = "split",          -- or "float"
})
```

To map a key shortcut:

```lua
-- adds shortcut to <leader>a
vim.keymap.set({ "n", "x" }, "<leader>a", "<Plug>(AISummary)")
vim.keymap.set({ "n", "x" }, "<leader>u", "<Plug>(AIUsage)")
```

## Development usage

```sh
./try.sh                              # Codex, no install
AI_EXPLAIN_PROVIDER=claude ./try.sh   # Claude
```
