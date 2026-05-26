local M = {}

local function format_pinyin(word, fmt)
  local accented = word.pinyin or ''
  local numbered = word.pinyinNum or ''
  if fmt == 'numbered' then return numbered end
  if fmt == 'both' then
    if accented == '' then return numbered end
    if numbered == '' then return accented end
    return accented .. '  (' .. numbered .. ')'
  end
  return accented ~= '' and accented or numbered
end

-- [[word_ref jianti;fanti;id]] — produced by some dictionary sources to link
-- cross-references (measure words, etc). We display them as "jianti/fanti"
-- (or just "jianti" when they're identical) and return the byte ranges so
-- the gd handler can look up the underlying word_id at the cursor.
local WORD_REF_PATTERN = '%[%[word_ref ([^;]+);([^;]+);([^%]]+)%]%]'

local function normalize_definition(text)
  local out = {}
  local refs = {}
  local cur = 0  -- byte offset within the produced display string
  local pos = 1
  while pos <= #text do
    local s, e, jt, ft, id = text:find(WORD_REF_PATTERN, pos)
    if not s then
      out[#out + 1] = text:sub(pos)
      break
    end
    if s > pos then
      local before = text:sub(pos, s - 1)
      out[#out + 1] = before
      cur = cur + #before
    end
    local display = (jt == ft) and jt or (jt .. '/' .. ft)
    refs[#refs + 1] = { col_start = cur, col_end = cur + #display, word_id = id }
    out[#out + 1] = display
    cur = cur + #display
    pos = e + 1
  end
  return table.concat(out), refs
end

-- Render a candidate. Returns:
--   markdown_text :: string
--   refs          :: list of { line, col_start, col_end, word_id }
--                    line is 1-based, cols are 0-based byte offsets into that line
function M.candidate(cand, index, total, opts)
  local w = cand.word
  local lines = {}
  local all_refs = {}
  local pinyin = format_pinyin(w, opts.pinyin_format)

  local headline = '**' .. w.jianti .. '**'
  if w.fanti and w.fanti ~= '' and w.fanti ~= w.jianti then
    headline = headline .. ' (_' .. w.fanti .. '_)'
  end
  lines[#lines + 1] = headline

  if pinyin ~= '' then
    lines[#lines + 1] = pinyin
  end
  lines[#lines + 1] = ''

  local defs = cand.definitions or {}
  if #defs == 0 then
    lines[#lines + 1] = '_(no definitions)_'
  else
    for i, d in ipairs(defs) do
      local prefix = string.format('%d. ', i)
      local body, refs = normalize_definition(d.text or '')
      lines[#lines + 1] = prefix .. body
      for _, r in ipairs(refs) do
        all_refs[#all_refs + 1] = {
          line = #lines,
          col_start = r.col_start + #prefix,
          col_end = r.col_end + #prefix,
          word_id = r.word_id,
        }
      end
    end
  end

  if total > 1 then
    local nk = opts.next_key or '<C-k>'
    local pk = opts.prev_key or '<C-j>'
    lines[#lines + 1] = ''
    lines[#lines + 1] = string.format('%d/%d · `%s` next · `%s` prev', index, total, nk, pk)
  end

  return table.concat(lines, '\n'), all_refs
end

return M
