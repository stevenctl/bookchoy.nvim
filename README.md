# bookchoy.nvim

Lookup pinyin and translation for Chinese words using LSP hover

使用LSP hover功能查询中文单词的拼音和翻译.

## Usage

Install using your package manager of choice, for lazy.nvim:

```lua
{
    "stevenctl/bookchoy.nvim",
    dependencies = { "kkharji/sqlite.lua" },
    config = function()
        require("bookchoy").setup({
            db_path = "/absolute/path/to/dict.db",
        })
    end,
}
```

* By default, it will attach to Markdown and text buffers.
* Use `K` or your `lsp.buf.hover` keybinding to look up words.
* Use `gd` or `lsp.buf.definition` to jump to other words referenced in the hover window.
* `<C-j>` and `<C-k>` can be used to navigate between multiple results (multiple pronunciations or segmentations).

## Configuration

```lua
require("bookchoy").setup({
    db_path       = nil,                       -- defaults to stdpath('data')/bookchoy/zh_en_dictionary.sqlite3
    db_url        = nil,                       -- auto-downloaded to db_path on first use if set
    filetypes     = { "markdown", "text" },
    pinyin_format = "accented",                -- 'accented' | 'numbered' | 'both'
    max_window    = 8,                         -- chars on either side of cursor to consider
    border        = "single",
    next_key      = "<C-k>",
    prev_key      = "<C-j>",
    max_width     = 80,                        -- cap float width and soft-wrap; nil to disable
})
```

Word references inside hover content use the `BookchoyWordRef` highlight group
(linked to `@markup.link` by default).

## Requirements

`gzip` must be available on PATH to decompress the bundled dictionary on first use.
This is pre-installed on macOS and Linux; Windows users may need Git Bash, MSYS2, or WSL.

## Dictionary Schema

A dictionary is bundled with the plugin (`zh_en_dictionary.sqlite3.gz`). It is
decompressed to `stdpath('data')/bookchoy/` on first use. You can also supply
your own database via `db_path` as long as it matches this schema:

```sql
CREATE TABLE Word (
    id        TEXT PRIMARY KEY NOT NULL,
    jianti    TEXT NOT NULL,              -- simplified Chinese
    fanti     TEXT NOT NULL,              -- traditional Chinese
    pinyin    TEXT NOT NULL,              -- accented pinyin (e.g. "nǐ hǎo")
    pinyinNum TEXT NOT NULL,              -- numbered pinyin (e.g. "ni3 hao3")
    frequency DOUBLE NOT NULL            -- relative frequency score
);

CREATE TABLE WordDefinition (
    wordId TEXT NOT NULL,                 -- references Word.id
    text   TEXT NOT NULL,                 -- English definition
    source TEXT NOT NULL                  -- dictionary source (e.g. "cedict")
);
```

Lookups match against both `jianti` and `fanti` columns, so the database works with either simplified or traditional input.

## License

The plugin source code is licensed under the [MIT License](LICENSE).

## Dictionary Attribution

The bundled dictionary (`zh_en_dictionary.sqlite3.gz`) is built from [bookchoy/cidian](https://github.com/bookchoy/cidian), a fork of CC-CEDICT.

It uses a lot of data from [MDBG's CEDICT](https://www.mdbg.net/chinese/dictionary?page=cedict), which is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.

[![Creative Commons Badge](https://i.creativecommons.org/l/by-sa/4.0/88x31.png)](https://creativecommons.org/licenses/by-sa/4.0/)

