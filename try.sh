#!/bin/sh
set -eu
AI_EXPLAIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export AI_EXPLAIN_DIR
if [ "$#" -eq 0 ]; then
  set -- '+/local function function_name' "$AI_EXPLAIN_DIR/lua/ai_explain/context.lua"
fi
exec nvim -u NONE -i NONE -n \
  --cmd "let mapleader = ','" \
  --cmd 'lua vim.opt.runtimepath:prepend(vim.env.AI_EXPLAIN_DIR)' \
  --cmd 'filetype on' \
  -c 'runtime plugin/ai-explain.lua' \
  -c 'lua require("ai_explain").setup({ provider = vim.env.AI_EXPLAIN_PROVIDER })' \
  "$@"
