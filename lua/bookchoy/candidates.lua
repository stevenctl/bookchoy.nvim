local M = {}

local function utf8_chars(s)
  local chars = {}
  local i = 1
  while i <= #s do
    local b = string.byte(s, i)
    local len
    if b < 0x80 then len = 1
    elseif b < 0xC0 then len = 1
    elseif b < 0xE0 then len = 2
    elseif b < 0xF0 then len = 3
    else len = 4
    end
    chars[#chars + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return chars
end

local function is_chinese(c)
  if c == nil or c == '' then return false end
  local cp = vim.fn.char2nr(c)
  return (cp >= 0x4E00 and cp <= 0x9FFF)
      or (cp >= 0x3400 and cp <= 0x4DBF)
      or (cp >= 0xF900 and cp <= 0xFAFF)
end

-- LSP `character` is UTF-16 code units; for BMP (incl. common CJK) this equals
-- char index. Convert the line's UTF-16 column to a 1-based char index.
function M.utf16_col_to_char_index(line, utf16_col)
  local chars = utf8_chars(line)
  local seen_u16 = 0
  for i, c in ipairs(chars) do
    local cp = vim.fn.char2nr(c)
    local units = (cp >= 0x10000) and 2 or 1
    if seen_u16 + units > utf16_col then
      return i, chars
    end
    seen_u16 = seen_u16 + units
  end
  return #chars + 1, chars
end

-- Enumerate substrings (as chars) that contain char index `c`, up to window W.
function M.enumerate(chars, c, W)
  if c < 1 or c > #chars then return {} end
  if not is_chinese(chars[c]) then return {} end

  local n = #chars
  local out = {}
  local seen = {}
  local lo = math.max(1, c - W + 1)
  for s = lo, c do
    local lmax = math.min(W, n - s + 1)
    for l = 1, lmax do
      local last = s + l - 1
      if last >= c then
        local all_zh = true
        for i = s, last do
          if not is_chinese(chars[i]) then all_zh = false; break end
        end
        if all_zh then
          local sub = table.concat(chars, '', s, last)
          if not seen[sub] then
            seen[sub] = { start = s, length = l }
            out[#out + 1] = { text = sub, start = s, length = l }
          end
        end
      end
    end
  end
  return out
end

function M.rank(matched, cursor_c)
  table.sort(matched, function(a, b)
    -- Longest match wins; lookback (e.g. 喜欢 when cursor is on 欢) beats
    -- shorter starts-at-cursor candidates.
    if a.length ~= b.length then return a.length > b.length end
    -- Same length: prefer the one starting at the cursor.
    local a_at = (a.start == cursor_c) and 0 or 1
    local b_at = (b.start == cursor_c) and 0 or 1
    if a_at ~= b_at then return a_at < b_at end
    return (a.word.frequency or 0) > (b.word.frequency or 0)
  end)
  return matched
end

return M
