local M = {}

M.filetypes = { 'markdown', 'text', 'gitcommit' }
M.spelllang = 'nl,en_us'

-- Keep prose as one logical line in the file, but wrap it on screen at word
-- boundaries.  list:-1 makes continuations of Markdown lists line up with the
-- text after the marker instead of with the dash or number.
function M.apply(buf, win)
  buf = buf or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].breakindentopt = 'min:40,list:-1'
  vim.wo[win].showbreak = ''
  vim.wo[win].smoothscroll = true
  vim.wo[win].list = false
  vim.wo[win].colorcolumn = ''
  vim.wo[win].spell = true
  vim.wo[win].conceallevel = 0
  vim.wo[win].concealcursor = ''

  vim.bo[buf].spelllang = M.spelllang
  vim.bo[buf].textwidth = 0
  vim.bo[buf].wrapmargin = 0

  vim.keymap.set('n', 'j', function()
    return vim.v.count == 0 and 'gj' or 'j'
  end, { expr = true, silent = true, buffer = buf })

  vim.keymap.set('n', 'k', function()
    return vim.v.count == 0 and 'gk' or 'k'
  end, { expr = true, silent = true, buffer = buf })

  vim.keymap.set('n', '0', 'g0', { buffer = buf })
  vim.keymap.set('n', '$', 'g$', { buffer = buf })
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ProseEditor', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = M.filetypes,
    callback = function(args)
      M.apply(args.buf, vim.api.nvim_get_current_win())
    end,
  })
end

return M
