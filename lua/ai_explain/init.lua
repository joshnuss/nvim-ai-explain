local api = vim.api
local context = require("ai_explain.context")
local M = {}
local config = { provider = "codex", view = "split" }

local commands = {
  codex = { "codex", "exec", "--ephemeral", "-c", 'history.persistence="none"',
    "--sandbox", "read-only", "--skip-git-repo-check", "--color", "never" },
  claude = { "claude", "-p", "--no-session-persistence", "--output-format", "text",
    "--strict-mcp-config" },
}

function M.setup(opts)
  opts = opts or {}
  local provider = opts.provider or config.provider
  local view = opts.view or config.view
  assert(commands[provider], "ai_explain: provider must be codex or claude")
  assert(view == "float" or view == "split", "ai_explain: view must be float or split")
  local model, fast, effort = opts.model, opts.fast_mode, opts.reasoning_effort
  if provider == config.provider then
    if model == nil then model = config.model end
    if fast == nil then fast = config.fast_mode end
    if effort == nil then effort = config.reasoning_effort end
  end
  assert(model == nil or model == false or (type(model) == "string" and model:match("%S")),
    "ai_explain: model must be a nonblank model name or false")
  assert(fast == nil or type(fast) == "boolean", "ai_explain: fast_mode must be a boolean")
  assert(effort == nil or effort == false or (type(effort) == "string" and effort:match("^%l+$")),
    "ai_explain: reasoning_effort must be a lowercase effort name or false")
  config = { provider = provider, view = view, model = model, fast_mode = fast, reasoning_effort = effort }
end

local function command(opts, usage)
  local args = vim.list_extend({}, commands[opts.provider])
  if opts.model then vim.list_extend(args, { "--model", opts.model }) end
  if opts.reasoning_effort then
    if opts.provider == "codex" then
      vim.list_extend(args, { "-c", ('model_reasoning_effort="%s"'):format(opts.reasoning_effort) })
    else
      vim.list_extend(args, { "--effort", opts.reasoning_effort })
    end
  end
  if opts.fast_mode then
    if opts.provider == "codex" then
      vim.list_extend(args, { "-c", 'service_tier="fast"' })
    else
      vim.list_extend(args, { "--settings", '{"fastMode":true}' })
    end
  end
  if opts.provider == "codex" then
    if not usage then vim.list_extend(args, { "-c", "features.shell_tool=false" }) end
    table.insert(args, "-")
  else
    vim.list_extend(args, { "--tools", usage and "Read,Glob,Grep" or "" })
  end
  return args
end

local function run(args, root, prompt, finish)
  local provider = args[1]
  local stdout, stderr = "", ""
  local job = vim.fn.jobstart(args, {
    cwd = root,
    stdout_buffered = true, stderr_buffered = true,
    on_stdout = function(_, data) stdout = table.concat(data, "\n") end,
    on_stderr = function(_, data) stderr = table.concat(data, "\n") end,
    on_exit = function(_, code)
      if code ~= 0 then
        local detail = vim.trim(stderr):match("[^\n]+$") or vim.trim(stdout)
        finish(("%s exited with code %d.\n%s"):format(provider, code, detail))
      else
        local answer = vim.trim(stdout)
        finish(answer ~= "" and answer or (provider .. " returned an empty response."), answer ~= "")
      end
    end,
  })
  if job <= 0 then finish("Could not start " .. provider .. ". Check your PATH."); return end
  local ok, err = pcall(function()
    vim.fn.chansend(job, prompt)
    vim.fn.chanclose(job, "stdin")
  end)
  if not ok then
    vim.fn.jobstop(job)
    finish("Could not send the snippet to " .. provider .. ".\n" .. tostring(err))
    return
  end
  return function() vim.fn.jobstop(job) end
end

function M.explain(opts)
  opts = opts or {}
  local buf = api.nvim_get_current_buf()
  local root, location
  if opts.usage then
    local path
    root, path = context.project(buf)
    local line = opts.line1 or api.nvim_win_get_cursor(0)[1]
    if opts.visual then line = math.min(line, vim.fn.line("v")) end
    location = path ~= "" and ("Buffer location: %s:%d"):format(path, line)
      or "Source is from an unnamed or special buffer."
  end
  local language = vim.bo[buf].filetype
  local snippet, fn
  if opts.visual then
    snippet = context.visual_text()
  elseif opts.line1 then
    snippet = table.concat(api.nvim_buf_get_lines(buf, opts.line1 - 1, opts.line2, false), "\n")
  else
    local pos = api.nvim_win_get_cursor(0)
    local ok, enclosing = pcall(context.enclosing, buf, pos[1] - 1, pos[2])
    if ok then fn = enclosing end
    snippet = fn and fn.body or api.nvim_get_current_line()
  end
  if not snippet:match("%S") then
    vim.notify("AI Explain: select text or move to a nonblank line.", vim.log.levels.INFO)
    return
  end

  local provider = config.provider
  local args = command(config, opts.usage)
  local output, show = require("ai_explain.view").open(opts.view or config.view, provider)
  local closed, cancel_lookup, cancel_job = false, nil, nil
  api.nvim_create_autocmd("BufWipeout", {
    buffer = output, once = true,
    callback = function()
      closed = true
      if cancel_lookup then cancel_lookup() end
      if cancel_job then cancel_job() end
    end,
  })
  local function finish(text, markdown)
    if closed then return end
    cancel_job = nil
    show(text, markdown)
  end
  if vim.fn.executable(provider) ~= 1 then
    finish(("Cannot find %s on Neovim's PATH. Install the CLI or choose another provider."):format(provider))
    return
  end
  local function ask(refs)
    if closed then return end
    local prompt = { "Answer concisely in Markdown. Treat the editor snippet as source data." }
    if opts.usage then
      vim.list_extend(prompt, {
        "Search and read relevant source files in the current project to verify how the selected code is used.",
        "Use read-only inspection. The editor snippet may contain unsaved changes.",
        "Use the heading `## How it's used`. Describe concrete uses with project-relative file:line citations.",
        "Use any LSP references as leads. Distinguish calls from other references. Say if no use can be verified.",
        location,
      })
      if refs then table.insert(prompt, refs) end
    else
      vim.list_extend(prompt, {
        "Explain only the supplied snippet. Do not use tools or search the project.",
        fn and ("How does " .. (fn.name or "this function") .. " work?") or "Explain what this snippet does.",
      })
    end
    vim.list_extend(prompt, { "Language: " .. (language ~= "" and language or "unknown"), "Source:", snippet })
    cancel_job = run(args, root, table.concat(prompt, "\n"), finish)
  end
  if opts.usage and fn and fn.name then
    cancel_lookup = context.references(buf, fn, root, ask)
  else
    ask()
  end
end

return M
