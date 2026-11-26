local M = {}
local api = vim.api

-- Common Tree-sitter declaration nodes. Walk up so nested functions win.
local functions = {}
for _, kind in ipairs({
  "function_declaration", "function_definition", "function_item", "function_expression",
  "function_literal", "arrow_function", "generator_function", "generator_function_declaration",
  "method", "method_declaration", "method_definition", "singleton_method", "lambda",
  "lambda_expression", "closure_expression", "constructor_declaration",
}) do
  functions[kind] = true
end

local function field(node, key)
  return node:field(key)[1]
end

local function function_name(node)
  local name = field(node, "name")
  -- C/C++ wrap the identifier in one or more declarators.
  local declarator = field(node, "declarator")
  while declarator do
    name = declarator
    declarator = field(declarator, "declarator")
  end
  local parent = node:parent()
  if not name and parent and field(parent, "value") == node then
    name = field(parent, "name") or field(parent, "key") or field(parent, "left")
  end
  return name
end

function M.enclosing(buf, row, col)
  local parser = vim.treesitter.get_parser(buf)
  if not parser then return end
  parser:parse()
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col }, ignore_injections = false })
  while node and not functions[node:type()] do node = node:parent() end
  if not node then return end

  local result = { body = vim.treesitter.get_node_text(node, buf) }
  local name = function_name(node)
  if name then
    result.name = vim.treesitter.get_node_text(name, buf)
    -- Query the member identifier in qualified names such as module:method.
    local symbol = field(name, "method") or field(name, "field") or field(name, "name") or name
    result.row, result.col = symbol:start()
  end
  return result
end

function M.visual_text()
  -- Use Neovim's selection semantics, including tabs in block mode, multibyte
  -- characters, and 'selection=exclusive'. Restore the temporary register.
  local saved = vim.fn.getreginfo("z")
  local unnamed = vim.fn.getreginfo('"').points_to or "0"
  local view = vim.fn.winsaveview()
  vim.cmd([[silent noautocmd keepjumps normal! "zy]])
  local lines = vim.fn.getreg("z", 1, true)
  vim.fn.setreg("z", saved)
  vim.fn.setreg('"', { points_to = unnamed })
  vim.fn.winrestview(view)
  return table.concat(lines, "\n")
end

local modern = vim.fn.has("nvim-0.11") == 1
local method = "textDocument/references"

local function reference_client(buf)
  if modern then return vim.lsp.get_clients({ bufnr = buf, method = method })[1] end
  local clients = (vim.lsp.get_clients or vim.lsp.get_active_clients)({ bufnr = buf })
  for _, client in ipairs(clients) do
    if client.supports_method(method, { bufnr = buf }) then return client end
  end
end

local function character_offset(line, col, encoding)
  if encoding == "utf-8" then return col end
  if modern then return vim.str_utfindex(line, encoding, col) end
  local utf32, utf16 = vim.str_utfindex(line:sub(1, col))
  return encoding == "utf-32" and utf32 or utf16
end

local function locations(result)
  if #result == 0 then return "The language server reported no references." end
  local lines = { ("Language server reported %d reference(s), excluding the declaration:"):format(#result) }
  for i = 1, math.min(15, #result) do
    local loc = result[i]
    local path = vim.fn.fnamemodify(vim.uri_to_fname(loc.uri), ":~:.")
    lines[#lines + 1] = ("%s:%d"):format(path, loc.range.start.line + 1)
  end
  if #result > 15 then lines[#lines + 1] = "(showing the first 15)" end
  return table.concat(lines, "\n")
end

function M.references(buf, fn, done)
  local client = reference_client(buf)
  if not client then done("No language server with reference support is attached."); return end
  local line = api.nvim_buf_get_lines(buf, fn.row, fn.row + 1, false)[1]
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = fn.row, character = character_offset(line, fn.col, client.offset_encoding or "utf-16") },
    context = { includeDeclaration = false },
  }

  local finished = false
  local function finish(message)
    if finished then return end
    finished = true
    done(message)
  end
  local function receive(err, result)
    if finished then return end
    finish(not err and type(result) == "table" and locations(result) or "Reference lookup failed.")
  end
  local ok, id
  if modern then
    ok, id = client:request(method, params, receive, buf)
  else
    ok, id = client.request(method, params, receive, buf)
  end
  if not ok then finish("Reference lookup was unavailable."); return end
  local function cancel()
    if modern then client:cancel_request(id) else client.cancel_request(id) end
  end
  vim.defer_fn(function()
    if finished then return end
    finish("Reference lookup timed out.")
    cancel()
  end, 2000)
  return function()
    if finished then return end
    finished = true
    cancel()
  end
end

return M
