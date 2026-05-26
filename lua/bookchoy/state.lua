local M = {}

local ref_ns = vim.api.nvim_create_namespace('bookchoy_refs')

-- Per-parent-bufnr state:
-- { row, col_char, line_fp, candidates, index }
local states = {}

-- Apply BookchoyWordRef highlight to each ref byte range so users can see
-- that the token is actionable (gd jumps to it).
local function highlight_refs(float_buf, refs)
  vim.api.nvim_buf_clear_namespace(float_buf, ref_ns, 0, -1)
  for _, r in ipairs(refs or {}) do
    pcall(vim.api.nvim_buf_set_extmark, float_buf, ref_ns, r.line - 1, r.col_start, {
      end_col = r.col_end,
      hl_group = 'BookchoyWordRef',
    })
  end
end

local function line_fingerprint(line)
  return #line .. ':' .. line:sub(1, 16) .. ':' .. line:sub(-16)
end

function M.get(bufnr)
  return states[bufnr]
end

function M.set(bufnr, row, col_char, line, candidates)
  states[bufnr] = {
    row = row,
    col_char = col_char,
    line_fp = line_fingerprint(line),
    candidates = candidates,
    index = 1,
  }
end

function M.advance(bufnr, delta)
  local s = states[bufnr]
  if not s or #s.candidates == 0 then return nil end
  s.index = ((s.index - 1 + delta) % #s.candidates) + 1
  return s.candidates[s.index], s.index, #s.candidates
end

function M.clear(bufnr)
  states[bufnr] = nil
end

local function render_lines(cand, index, total)
  local render = require('bookchoy.render')
  local opts = require('bookchoy').opts
  local md, refs = render.candidate(cand, index, total, opts)
  return vim.split(md, '\n', { plain = true }), refs
end

-- Visual line count for `lines` when soft-wrapped to `width` cells.
local function wrapped_height(lines, width)
  if not width or width <= 0 then return #lines end
  local total = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    total = total + math.max(1, math.ceil(w / width))
  end
  return total
end

-- Replace the contents of a floating-window's buffer in place, refresh the
-- ref table that `gd` reads from.
local function rewrite_float(float_win, lines, refs)
  local float_buf = vim.api.nvim_win_get_buf(float_win)
  vim.api.nvim_set_option_value('modifiable', true, { buf = float_buf })
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = float_buf })
  vim.b[float_buf].bookchoy_refs = refs or {}
  highlight_refs(float_buf, refs)

  local cfg = vim.api.nvim_win_get_config(float_win)
  if not cfg.height then return end
  local target = wrapped_height(lines, cfg.width)
  if target ~= cfg.height then
    pcall(vim.api.nvim_win_set_config, float_win, { height = target })
  end
end

-- Find the hover float belonging to `parent_bufnr`, if any is still open.
local function find_float(parent_bufnr)
  local win = vim.b[parent_bufnr].lsp_floating_preview
  if win and vim.api.nvim_win_is_valid(win) then return win end
  return nil
end

-- Cycle the candidate list and update the open hover float (or open a new one).
function M.step(parent_bufnr, delta)
  if not parent_bufnr or parent_bufnr == 0 then
    parent_bufnr = vim.api.nvim_get_current_buf()
  end
  local s = states[parent_bufnr]
  if not s or #s.candidates == 0 then
    vim.notify('bookchoy: press K first to look up a word', vim.log.levels.INFO)
    return
  end

  local cand, index, total = M.advance(parent_bufnr, delta)
  if not cand then return end
  local lines, refs = render_lines(cand, index, total)

  local float_win = find_float(parent_bufnr)
  if float_win then
    rewrite_float(float_win, lines, refs)
    return
  end

  local opts = require('bookchoy').opts
  local buf = vim.lsp.util.open_floating_preview(lines, 'markdown', {
    border = opts.border or 'single',
    focus_id = 'textDocument/hover',
    focusable = true,
    close_events = { 'CursorMoved', 'CursorMovedI', 'BufHidden', 'InsertCharPre' },
  })
  if buf then
    vim.b[buf].bookchoy_refs = refs or {}
    highlight_refs(buf, refs)
  end
end

-- Look up a word by id and replace the float content with its definitions.
-- Used by the `gd` keymap. Does not touch the candidate state, so cycling
-- with <C-k>/<C-j> still steps through the original word's candidates.
function M.jump_to_word_id(parent_bufnr, word_id)
  local db = require('bookchoy.db')
  local word = db.lookup_word_by_id(word_id)
  if not word then
    vim.notify('bookchoy: referenced word not in dictionary: ' .. tostring(word_id), vim.log.levels.WARN)
    return
  end
  local defs = db.lookup_definitions({ word.id })[word.id] or {}
  local cand = { word = word, definitions = defs }
  local opts = require('bookchoy').opts
  local md, refs = require('bookchoy.render').candidate(cand, 1, 1, opts)
  local lines = vim.split(md, '\n', { plain = true })

  local float_win = find_float(parent_bufnr)
  if float_win then
    rewrite_float(float_win, lines, refs)
    return
  end
  local buf = vim.lsp.util.open_floating_preview(lines, 'markdown', {
    border = opts.border or 'single',
    focus_id = 'textDocument/hover',
    focusable = true,
    close_events = { 'CursorMoved', 'CursorMovedI', 'BufHidden', 'InsertCharPre' },
  })
  if buf then
    vim.b[buf].bookchoy_refs = refs or {}
    highlight_refs(buf, refs)
  end
end

-- Find a ref under the cursor in the float buffer, jump to it.
local function jump_to_ref_at_cursor(parent_bufnr, float_buf)
  local refs = vim.b[float_buf].bookchoy_refs or {}
  if #refs == 0 then
    vim.notify('bookchoy: no word references in this definition', vim.log.levels.INFO)
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2]  -- 1-based row, 0-based byte col
  for _, r in ipairs(refs) do
    if r.line == row and col >= r.col_start and col < r.col_end then
      M.jump_to_word_id(parent_bufnr, r.word_id)
      return
    end
  end
  vim.notify('bookchoy: no word reference under cursor', vim.log.levels.INFO)
end

-- Install <C-k>/<C-j> on the float's buffer AND on the parent buffer so the
-- user can cycle whether they've focused into the float or not. Parent-buffer
-- mappings are removed when the float closes, so they don't shadow the user's
-- own bindings when no hover is visible. Called from server.lua via
-- vim.schedule, after Neovim has opened the float.
function M.attach_float_keymaps(parent_bufnr)
  local float_win = find_float(parent_bufnr)
  if not float_win then return end
  local float_buf = vim.api.nvim_win_get_buf(float_win)

  local opts = require('bookchoy').opts

  -- Soft-wrap long content. Cap width to opts.max_width and recompute height
  -- so wrapped lines stay visible. Skip if user disabled the cap.
  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true
  if opts.max_width then
    local cfg = vim.api.nvim_win_get_config(float_win)
    if cfg.width and cfg.width > opts.max_width then
      local lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
      pcall(vim.api.nvim_win_set_config, float_win, {
        width = opts.max_width,
        height = wrapped_height(lines, opts.max_width),
      })
    end
  end

  -- Stash the ref table on the float so `gd` can find them, and apply the
  -- BookchoyWordRef highlight so the user can see which tokens are
  -- actionable. Neovim's hover handler built the buffer without our refs
  -- metadata, so re-render here to recover it.
  local s = states[parent_bufnr]
  if s and s.candidates and s.candidates[s.index] then
    local _, refs = require('bookchoy.render').candidate(
      s.candidates[s.index], s.index, #s.candidates, opts)
    vim.b[float_buf].bookchoy_refs = refs or {}
    highlight_refs(float_buf, refs)
  end

  vim.keymap.set('n', 'gd', function()
    jump_to_ref_at_cursor(parent_bufnr, float_buf)
  end, { buffer = float_buf, nowait = true, silent = true,
         desc = 'bookchoy: jump to referenced word' })

  -- Only install cycle keymaps when there's something to cycle to.
  if not s or #s.candidates <= 1 then return end

  local nk, pk = opts.next_key or '<C-k>', opts.prev_key or '<C-j>'

  local function next_cb() M.step(parent_bufnr, 1) end
  local function prev_cb() M.step(parent_bufnr, -1) end

  vim.keymap.set('n', nk, next_cb,
    { buffer = float_buf, nowait = true, silent = true, desc = 'bookchoy: next candidate' })
  vim.keymap.set('n', pk, prev_cb,
    { buffer = float_buf, nowait = true, silent = true, desc = 'bookchoy: prev candidate' })

  vim.keymap.set('n', nk, next_cb,
    { buffer = parent_bufnr, nowait = true, silent = true, desc = 'bookchoy: next candidate' })
  vim.keymap.set('n', pk, prev_cb,
    { buffer = parent_bufnr, nowait = true, silent = true, desc = 'bookchoy: prev candidate' })

  -- Cleanup parent mappings when the float closes (cursor move, etc.).
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(float_win),
    once = true,
    callback = function()
      if vim.api.nvim_buf_is_valid(parent_bufnr) then
        pcall(vim.keymap.del, 'n', nk, { buffer = parent_bufnr })
        pcall(vim.keymap.del, 'n', pk, { buffer = parent_bufnr })
      end
    end,
  })
end

return M
