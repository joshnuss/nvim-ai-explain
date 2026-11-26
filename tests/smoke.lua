-- From the checkout: nvim --headless -u NONE -i NONE -n -l tests/smoke.lua
local api = vim.api
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.env.PATH = tmp .. ":" .. vim.env.PATH
vim.env.AI_EXPLAIN_TEST = tmp
for _, provider in ipairs({ "codex", "claude" }) do
  local path = tmp .. "/" .. provider
  vim.fn.writefile({
    "#!/bin/sh",
    [[pwd > "$AI_EXPLAIN_TEST/cwd"]],
    [[printf '%s\n' "$@" > "$AI_EXPLAIN_TEST/args"]],
    [[cat > "$AI_EXPLAIN_TEST/prompt"]],
    [[sleep 0.4]],
    [[if [ -n "$AI_EXPLAIN_FAIL" ]; then echo 'sign in first' >&2; exit 7; fi]],
    [[cat "$AI_EXPLAIN_TEST/reply"]],
  }, path)
  vim.fn.setfperm(path, "rwx------")
end

local function read(name)
  return table.concat(vim.fn.readfile(tmp .. "/" .. name), "\n")
end
local function keys(input)
  api.nvim_feedkeys(api.nvim_replace_termcodes(input, true, false, true), "xt", false)
end
local function answer(text)
  assert(vim.wait(3000, function()
    return api.nvim_get_current_line():find(text, 1, true) ~= nil
  end), vim.inspect(api.nvim_buf_get_lines(0, 0, -1, false)))
end
local function test()
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  vim.cmd("runtime plugin/ai-explain.lua")
  for _, mode in ipairs({ "n", "x" }) do
    assert(vim.fn.maparg(",ae", mode) == "")
  end
  vim.g.mapleader = ","
  vim.keymap.set({ "n", "x" }, "<leader>a", "<Plug>(AISummary)")
  vim.keymap.set({ "n", "x" }, "<leader>u", "<Plug>(AIUsage)")
  vim.fn.writefile({ "## Test explanation", "", "- **Doubles** the `input`.",
    "", "```lua", "  -- **literal**", "```" }, tmp .. "/reply")
  local src = api.nvim_get_current_buf()
  local project = tmp .. "/sample project"
  vim.fn.mkdir(project .. "/.git", "p")
  vim.fn.mkdir(project .. "/src", "p")
  api.nvim_buf_set_name(src, project .. "/src/math.lua")
  api.nvim_buf_set_lines(src, 0, -1, false, {
    "local function twice(n)", "  return n * 2", "end", "print(twice(3))",
  })
  vim.bo.filetype = "lua"
  api.nvim_win_set_cursor(0, { 2, 9 })

  -- Deterministic reference locations, exercising the same request as an
  -- attached server, including the symbol position and declaration filter.
  local reference_requests = 0
  local request = function(method, params, callback)
    reference_requests = reference_requests + 1
    assert(method == "textDocument/references" and not params.context.includeDeclaration)
    assert(params.position.line == 0 and params.position.character == 15)
    vim.schedule(function()
      callback(nil, { { uri = vim.uri_from_fname(project .. "/sample.lua"),
        range = { start = { line = 3, character = 6 } } } })
    end)
    return true, 1
  end
  local current = vim.fn.has("nvim-0.11") == 1
  local client = { cancel_request = function() end, supports_method = function() return true end,
    request = current and function(_, ...) return request(...) end or request }
  local list = vim.lsp.get_clients and "get_clients" or "get_active_clients"
  local original = vim.lsp[list]
  vim.lsp[list] = function() return { client } end

  keys(",a")
  local source_win = api.nvim_get_current_win()
  local panel_win = vim.fn.win_getid(vim.fn.winnr("j"))
  local panel = api.nvim_win_get_buf(panel_win)
  assert(panel ~= src and api.nvim_get_current_buf() == src)
  assert(vim.deep_equal(api.nvim_win_get_cursor(source_win), { 2, 9 }))
  assert(api.nvim_win_get_config(panel_win).relative == "")
  assert(not vim.bo[panel].swapfile and not vim.bo[panel].buflisted)
  local function first_line() return api.nvim_buf_get_lines(panel, 0, 1, false)[1] end
  local first = first_line()
  assert(first == "⠋ Asking Codex…")
  assert(vim.wait(350, function() return first_line() ~= first end))
  assert(vim.wait(3000, function() return first_line() == "## Test explanation" end))
  assert(api.nvim_get_current_win() == source_win)
  api.nvim_win_call(panel_win, function()
    assert(vim.wo.conceallevel == 2 and vim.fn.synconcealed(1, 1)[1] == 1)
    assert(vim.fn.synconcealed(3, 1)[2] == "•" and vim.fn.synconcealed(3, 3)[1] == 1)
    assert(vim.fn.synconcealed(3, 19)[1] == 1 and vim.fn.synconcealed(5, 1)[1] == 1)
    assert(vim.fn.synconcealed(6, 6)[1] == 0 and vim.fn.getline(6) == "  -- **literal**")
  end)
  assert(not read("args"):find("--model", 1, true) and not read("args"):find("service_tier", 1, true))
  assert(read("args"):find("--ephemeral", 1, true))
  assert(read("args"):find("--sandbox\nread-only", 1, true))
  assert(reference_requests == 0 and not read("prompt"):find("## How it's used", 1, true))
  assert(read("args"):find("features.shell_tool=false", 1, true))
  assert(read("prompt"):find("How does twice work?", 1, true))
  assert(not read("prompt"):find("print(twice", 1, true))
  require("ai_explain").setup({ model = "gpt-6.2-astra", reasoning_effort = "medium", fast_mode = true })
  vim.cmd("AIUsage")
  assert(vim.wait(2000, function() return read("args"):find('service_tier="fast"', 1, true) end))
  assert(vim.wait(2000, function() return read("prompt"):find("sample.lua:4", 1, true) end))
  assert(read("cwd") == project and read("prompt"):find("Buffer location: src/math.lua:2", 1, true))
  assert(reference_requests == 1 and read("prompt"):find("## How it's used", 1, true))
  assert(not read("args"):find("features.shell_tool=false", 1, true))
  assert(read("args"):find("--model\ngpt-6.2-astra\n", 1, true))
  assert(read("args"):find('-c\nmodel_reasoning_effort="medium"\n', 1, true))
  assert(#api.nvim_tabpage_list_wins(0) == 2 and not api.nvim_buf_is_valid(panel))
  keys("<C-w>j")
  assert(api.nvim_get_current_win() == panel_win)
  keys("q")
  vim.lsp[list] = original

  require("ai_explain").setup({ provider = "claude", view = "float", model = "opus", fast_mode = true })
  vim.fn.setreg("z", "saved")
  vim.fn.setreg("a", "untouched")
  vim.fn.setreg('"', { points_to = "a" })
  api.nvim_buf_set_lines(src, 0, -1, false, { "aé中 xyz", "defg" })
  api.nvim_win_set_cursor(0, { 1, 1 })
  keys("vl,u")
  assert(api.nvim_win_get_config(0).relative ~= "")
  answer("Test explanation")
  assert(read("prompt"):match("Source:\né中$"))
  assert(read("args"):find("--no-session-persistence", 1, true))
  assert(read("args"):find("--tools\nRead,Glob,Grep", 1, true) and read("cwd") == project)
  assert(read("args"):find("--model\nopus\n", 1, true))
  assert(read("args"):find('--settings\n{"fastMode":true}', 1, true))
  assert(vim.fn.getreg("z") == "saved" and vim.fn.getreginfo('"').points_to == "a")
  keys("<Esc>")

  require("ai_explain").setup({ model = false, fast_mode = false })
  vim.bo.filetype = "no_such_parser"
  api.nvim_win_set_cursor(0, { 2, 1 })
  vim.cmd("AISummary")
  answer("Test explanation")
  assert(read("prompt"):match("Source:\ndefg$"))
  assert(read("args"):match("%-%-tools\n$"))
  assert(not read("args"):find("--settings", 1, true) and not read("args"):find("--model", 1, true))
  keys("q")
  vim.env.AI_EXPLAIN_FAIL = "1"
  vim.cmd("1,2AISummary!")
  assert(api.nvim_get_current_buf() == src)
  keys("<C-w>j")
  answer("exited with code 7")
  assert(api.nvim_buf_get_lines(0, 1, 2, false)[1] == "sign in first")
  assert(read("prompt"):match("Source:\naé中 xyz\ndefg$"))
  keys("q")
  vim.cmd("AISummary")
  local cancelled = api.nvim_get_current_buf()
  keys("q")
  vim.wait(500, function() return false end)
  assert(not api.nvim_buf_is_valid(cancelled) and api.nvim_get_current_buf() == src)
end
local ok, err = xpcall(test, debug.traceback)
vim.fn.delete(tmp, "rf")
if not ok then error(err) end
print("AI Explain smoke tests passed")
