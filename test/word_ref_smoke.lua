-- Verifies [[word_ref jianti;fanti;id]] is normalized in display and that
-- jump_to_word_id can rewrite the float with the referenced word's defs.

local function fail(msg) io.stderr:write('FAIL: ' .. msg .. '\n'); os.exit(1) end

local render = require('bookchoy.render')
local cd = require('bookchoy')
require('bookchoy.db').ensure_open(cd.opts, function()

-- Build a synthetic candidate whose definition contains a word_ref
local cand = {
  word = { id = 'fake', jianti = '思南县', fanti = '思南縣',
           pinyin = 'Sī nán xiàn', pinyinNum = 'Si1nan2xian4', frequency = 0 },
  definitions = {
    { text = 'Sinan, a county in Tongren [[word_ref 铜仁市;銅仁市;3cb4e9f25ed68d92]], Guizhou', source = 'cedict' },
  },
}

local md, refs = render.candidate(cand, 1, 1, cd.opts)
io.stdout:write(md .. '\n---\n')

if md:find('word_ref', 1, true) then fail('raw word_ref markup leaked into display') end
if not md:find('铜仁市/銅仁市', 1, true) then fail('expected normalized "铜仁市/銅仁市" in display') end
io.stdout:write('ok word_ref normalized to jianti/fanti\n')

if #refs ~= 1 then fail('expected exactly 1 ref, got ' .. #refs) end
if refs[1].word_id ~= '3cb4e9f25ed68d92' then fail('wrong word_id: ' .. refs[1].word_id) end
io.stdout:write('ok ref byte-range tracked\n')

-- Verify the byte range actually points to the normalized token in the rendered line
local lines = vim.split(md, '\n', { plain = true })
local line = lines[refs[1].line]
local slice = line:sub(refs[1].col_start + 1, refs[1].col_end)
if slice ~= '铜仁市/銅仁市' then
  fail('ref range points to "' .. slice .. '", expected "铜仁市/銅仁市"')
end
io.stdout:write('ok ref range slice = "' .. slice .. '"\n')

-- Look up the referenced word in the real DB — should resolve to a row
local row = require('bookchoy.db').lookup_word_by_id(refs[1].word_id)
if not row then fail('lookup_word_by_id returned nil for ' .. refs[1].word_id) end
if row.jianti ~= '铜仁市' then fail('looked-up jianti mismatch: ' .. (row.jianti or '<nil>')) end
io.stdout:write('ok lookup_word_by_id resolved 铜仁市\n')

-- Sanity: a candidate with NO word_ref should produce zero refs
local cand2 = {
  word = { id = 'x', jianti = '中', fanti = '中', pinyin = 'zhōng', pinyinNum = 'zhong1', frequency = 0 },
  definitions = { { text = 'middle', source = 'cedict' } },
}
local _, refs2 = render.candidate(cand2, 1, 1, cd.opts)
if #refs2 ~= 0 then fail('plain definition produced refs: ' .. vim.inspect(refs2)) end
io.stdout:write('ok plain definition has no refs\n')

io.stdout:write('PASS\n')

end)
