local clip = require('clipboard_image_to_agent')

vim.api.nvim_create_user_command('ClipboardImagePaste', function()
  local ok, result = clip.paste()
  if not ok then
    vim.notify(result or 'Failed to capture clipboard image', vim.log.levels.WARN, {
      title = 'clipboard-image-to-agent.nvim',
    })
  end
end, { desc = 'Paste clipboard image path into the current buffer' })

return clip
