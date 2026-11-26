local api = vim.api
local M = {}
local dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M.open(kind, provider)
  local buf = api.nvim_create_buf(false, true)
  local win
  if kind == "split" then
    local source = api.nvim_get_current_win()
    for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
      if vim.b[api.nvim_win_get_buf(candidate)].ai_explain_panel then
        win = candidate
        break
      end
    end
    if not win then
      local height = math.max(1, math.min(12, math.floor(api.nvim_win_get_height(source) / 3)))
      vim.cmd(("botright %dsplit"):format(height))
      win = api.nvim_get_current_win()
    end
    vim.b[buf].ai_explain_panel = true
    api.nvim_win_set_buf(win, buf)
    api.nvim_set_current_win(source)
  else
    local width = math.max(1, math.min(78, vim.o.columns - 4))
    local height = math.max(1, math.min(16, math.floor(vim.o.lines * 0.45)))
    win = api.nvim_open_win(buf, true, {
      relative = "cursor", row = 1, col = 0, width = width, height = height,
      style = "minimal", border = "rounded", title = " Explanation ", title_pos = "center",
    })
  end
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modeline = false
  vim.bo[buf].undolevels = -1
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].spell = false
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function() api.nvim_win_close(win, true) end, { buffer = buf, silent = true })
  end
  local function show(text)
    if not api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    vim.bo[buf].modifiable = false
  end
  local loading, frame = true, 1
  local status = " Asking " .. (provider == "codex" and "Codex" or "Claude") .. "…"
  local function animate()
    if not loading or not api.nvim_buf_is_valid(buf) then return end
    show(dots[frame] .. status)
    frame = frame % #dots + 1
    vim.defer_fn(animate, 80)
  end
  animate()
  return buf, function(text, markdown)
    loading = false
    show(text)
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= buf then return end
    if markdown then
      api.nvim_win_call(win, function()
        vim.bo[buf].filetype = "markdown"
        vim.cmd("runtime syntax/ai_explain.vim")
        vim.wo[win].conceallevel = 2
        vim.wo[win].concealcursor = "nc"
      end)
    end
    api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

return M
