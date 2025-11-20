# clipboard-image-to-agent.nvim

Simple Neovim helper that saves the current clipboard image to a local file and inserts its path into the buffer (handy for Codex / Claude Code CLIs).

## Features

- Tries multiple clipboard backends (`pngpaste`, `wl-paste`, `xclip`) and falls back automatically.
- Stores images under `$TMPDIR/clipboard-images` by default (falling back to `stdpath('cache') .. '/clipboard-images'`) with unique filenames.
- Exposes a single `paste()` function so you can map it to `<C-v>` or any key you like.
- Optional fallback handler when the clipboard is not an image.

Neovim 0.10+ is required because the plugin relies on `vim.system`.

## Installation

### Lazy.nvim

```lua
{
  'yuki-yano/clipboard-image-to-agent.nvim',
  event = 'VeryLazy',
  config = function()
    local clip = require('clipboard_image_to_agent')
    clip.setup() -- override defaults here if you need custom options
  end,
  keys = {
    {
      '<C-v>',
      function()
        local clip = require('clipboard_image_to_agent')
        local ok, err = clip.paste()
        if not ok and err then
          vim.notify(err, vim.log.levels.WARN, { title = 'clipboard-image-to-agent.nvim' })
        end
      end,
      mode = 'i',
      desc = 'Paste clipboard image path',
    },
  },
}
```

Feel free to adjust `event` or `keys` to match your setup. If you prefer a local clone, add `dir`; for a fork, supply `url` or any other Lazy.nvim options you need.

## Configuration

```lua
require('clipboard_image_to_agent').setup({
  cache_dir = vim.fn.stdpath('data') .. '/codex-clipboard',
  filename_prefix = 'codex-clipboard',
  commands = {
    { command = { 'pngpaste', '$OUTPUT' }, output = 'file', description = 'pngpaste (macOS)' },
    { command = { 'wl-paste', '--type', 'image/png' }, output = 'stdout', description = 'wl-paste (Wayland)' },
    { command = { 'xclip', '-selection', 'clipboard', '-t', 'image/png', '-o' }, output = 'stdout', description = 'xclip (X11)' },
  },
  trailing_space = true,
  fallback = nil, -- function(err) -> string|{text=..., trailing_space=boolean}
})
```

Each `command` entry describes a program that can dump the clipboard image. If `output` is `file`, the command must accept an output path placeholder (`$OUTPUT`). If `output` is `stdout`, the plugin captures stdout and writes it to the target file.

`fallback` is invoked only when no configured command succeeds. It receives the aggregated error message and can return either a string (inserted as-is), or a table `{ text = '...', trailing_space = false }` to override the trailing-space behavior. Returning `nil` keeps the default failure behavior.

Example: fall back to inserting the text clipboard when there is no image.

```lua
require('clipboard_image_to_agent').setup({
  fallback = function(err)
    -- Only fall back when the clipboard is simply not an image.
    if not err:lower():find('no image') and not err:lower():find('clipboard') then
      return nil
    end
    -- Use the unnamed register to insert whatever the user last yanked.
    local text = vim.fn.getreg('"')
    if text == '' then
      return nil
    end
    return { text = text, trailing_space = false }
  end,
})
```

## Usage

- `:ClipboardImagePaste` — attempts to capture the clipboard image and insert its path at the cursor.
- `require('clipboard_image_to_agent').paste()` — the function to bind to keymaps.
