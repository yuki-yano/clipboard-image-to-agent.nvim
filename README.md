# clipboard-image-to-agent.nvim

Simple Neovim helper that saves the current clipboard image to a local file and inserts its path into the buffer (handy for Codex / Claude Code CLIs).

## Features

- Tries multiple clipboard backends (`pngpaste`, `wl-paste`, `xclip`) and falls back automatically.
- Stores images under `stdpath('cache') .. '/clipboard-images'` with unique filenames.
- Exposes a single `paste()` function so you can map it to `<C-v>` or any key you like.

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
})
```

Each `command` entry describes a program that can dump the clipboard image. If `output` is `file`, the command must accept an output path placeholder (`$OUTPUT`). If `output` is `stdout`, the plugin captures stdout and writes it to the target file.

## Usage

- `:ClipboardImagePaste` — attempts to capture the clipboard image and insert its path at the cursor.
- `require('clipboard_image_to_agent').paste()` — the function to bind to keymaps.
