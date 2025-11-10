-- simple statusline
require('mini.statusline').setup({ use_icons = false }) -- don't defer statusline

vim.defer_fn(function()
  -- go forward/backward with square brackets (like vim-unimpaired)
  require('mini.bracketed').setup({})

  -- easily comment stuff
  require('mini.comment').setup({
    mappings = {
      comment_line = '<space>c',
      comment_visual = '<space>c',
    },
  })

  -- autopairs
  require('mini.pairs').setup({})

  -- add, delete, replace, find, highlight surrounding
  require('mini.surround').setup({
    custom_surroundings = { ['l'] = { output = { left = '[', right = ']()'} } }
  })

  -- diff stuff
  require('mini.diff').setup({})

  -- easily jump to words
  require('mini.jump2d').setup({
    view = { n_steps_ahead = 5 }
  })
  vim.keymap.set('n', 'G', function()
    MiniJump2d.start(MiniJump2d.builtin_opts.word_start)
  end, { desc = "Jump to word" })
end, 0)
