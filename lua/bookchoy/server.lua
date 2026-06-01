local M = {}

local function handle_hover(params, opts)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  if not vim.api.nvim_buf_is_loaded(bufnr) then return nil end

  local row = params.position.line
  local utf16_col = params.position.character
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line = lines[row + 1] or ''

  local candidates_mod = require('bookchoy.candidates')
  -- Map across hard-wrapped lines so words split by a linebreak inside the
  -- same paragraph stay continuous; blank lines (`\n\n`) stay as boundaries.
  local chars, cursor_char = candidates_mod.paragraph_window(lines, row, utf16_col)

  local state = require('bookchoy.state')

  local enumerated = candidates_mod.enumerate(chars, cursor_char, opts.max_window)
  if #enumerated == 0 then
    state.clear(bufnr)
    return nil
  end

  local texts = {}
  for _, e in ipairs(enumerated) do texts[#texts + 1] = e.text end

  local db = require('bookchoy.db')
  local rows = db.lookup_words(texts)
  if #rows == 0 then
    state.clear(bufnr)
    return nil
  end

  local by_text = {}
  for _, r in ipairs(rows) do
    by_text[r.jianti] = by_text[r.jianti] or {}
    table.insert(by_text[r.jianti], r)
    if r.fanti and r.fanti ~= '' and r.fanti ~= r.jianti then
      by_text[r.fanti] = by_text[r.fanti] or {}
      table.insert(by_text[r.fanti], r)
    end
  end

  local matched = {}
  for _, e in ipairs(enumerated) do
    local hits = by_text[e.text]
    if hits then
      for _, w in ipairs(hits) do
        matched[#matched + 1] = { word = w, start = e.start, length = e.length }
      end
    end
  end
  if #matched == 0 then
    state.clear(bufnr)
    return nil
  end

  candidates_mod.rank(matched, cursor_char)

  local seen = {}
  local final = {}
  for _, m in ipairs(matched) do
    if not seen[m.word.id] then
      seen[m.word.id] = true
      final[#final + 1] = m
    end
  end

  local ids = {}
  for _, m in ipairs(final) do ids[#ids + 1] = m.word.id end
  local defs = db.lookup_definitions(ids)
  for _, m in ipairs(final) do
    m.definitions = defs[m.word.id] or {}
  end

  state.set(bufnr, row, cursor_char, line, final)

  -- After Neovim opens the floating window (next event loop tick), enable
  -- soft wrap + cap width on the float, and install cycling keymaps if there
  -- is more than one candidate.
  vim.schedule(function()
    state.attach_float_keymaps(bufnr)
  end)

  local cand = final[1]
  local render = require('bookchoy.render')
  return { contents = { kind = 'markdown', value = render.candidate(cand, 1, #final, opts) } }
end

function M.make_cmd(opts)
  return function(dispatchers)
    local closing = false
    local request_id = 0

    local methods = {
      initialize = function()
        return nil, {
          capabilities = {
            hoverProvider = true,
            textDocumentSync = { openClose = true, change = 0 },
          },
          serverInfo = { name = 'bookchoy', version = '0.1.0' },
        }
      end,
      shutdown = function() return nil, nil end,
      ['textDocument/hover'] = function(params)
        local ok, result = pcall(handle_hover, params, opts)
        if not ok then
          return { code = -32603, message = tostring(result) }, nil
        end
        return nil, result
      end,
    }

    return {
      request = function(method, params, callback, _notify_reply_callback)
        request_id = request_id + 1
        local handler = methods[method]
        if handler then
          local err, result = handler(params)
          callback(err, result)
        else
          callback(nil, nil)
        end
        return true, request_id
      end,
      notify = function(method, _params)
        if method == 'exit' then
          closing = true
          if dispatchers and dispatchers.on_exit then dispatchers.on_exit(0, 0) end
        end
        return true
      end,
      is_closing = function() return closing end,
      terminate = function() closing = true end,
    }
  end
end

M._handle_hover = handle_hover

return M
