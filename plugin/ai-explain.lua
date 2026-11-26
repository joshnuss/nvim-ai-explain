if vim.g.loaded_ai_explain then return end
vim.g.loaded_ai_explain = true

local function register(name, desc, usage)
  vim.api.nvim_create_user_command(name, function(args)
    require("ai_explain").explain({
      usage = usage,
      view = args.bang and "split" or nil,
      line1 = args.range > 0 and args.line1 or nil,
      line2 = args.line2,
    })
  end, { range = true, bang = true, desc = desc })

  for _, mode in ipairs({ "n", "x" }) do
    local visual = mode == "x"
    vim.keymap.set(mode, "<Plug>(" .. name .. ")", function()
      require("ai_explain").explain({ visual = visual, usage = usage })
    end, { silent = true, desc = desc })
  end
end

register("AISummary", "Summarize the selected code", false)
register("AIUsage", "Find how the project uses the selected code", true)
