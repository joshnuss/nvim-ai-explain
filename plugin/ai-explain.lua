if vim.g.loaded_ai_explain then return end
vim.g.loaded_ai_explain = true

vim.api.nvim_create_user_command("AIExplain", function(args)
  require("ai_explain").explain({
    view = args.bang and "split" or nil,
    line1 = args.range > 0 and args.line1 or nil,
    line2 = args.line2,
  })
end, { range = true, bang = true, desc = "Explain code (use ! for a split)" })

for _, mode in ipairs({ "n", "x" }) do
  local visual = mode == "x"
  vim.keymap.set(mode, "<Plug>(AIExplain)", function()
    require("ai_explain").explain({ visual = visual })
  end, { silent = true, desc = "Explain code with AI" })
end
