-- simple statusline
require('mini.statusline').setup({ use_icons = false }) -- don't defer statusline

vim.defer_fn(function()
  -- go forward/backward with square brackets (like vim-unimpaired)
  require('mini.bracketed').setup()

  -- easily comment stuff
  require('mini.comment').setup({
    mappings = {
      comment_line = '<space>c',
      comment_visual = '<space>c',
    },
  })

  -- add, delete, replace, find, highlight surrounding
  require('mini.surround').setup({ custom_surroundings = { ['l'] = { output = { left = '[', right = ']()'} } } })

  -- easily jump to words
  require('mini.jump2d').setup({ mappings = { start_jumping = 'G' } })

  -- show next key clues
  local miniclue = require('mini.clue')
  miniclue.setup({                   
    triggers = {
      { mode = 'n', keys = '<Leader>' },
      { mode = 'x', keys = '<Leader>' },
      { mode = 'n', keys = '<space>' },
      { mode = 'x', keys = '<space>' },

      -- Built-in completion
      { mode = 'i', keys = '<C-x>' },

      -- `g` key
      { mode = 'n', keys = 'g' },
      { mode = 'x', keys = 'g' },

      -- Marks
      { mode = 'n', keys = "'" },
      { mode = 'n', keys = '`' },
      { mode = 'x', keys = "'" },
      { mode = 'x', keys = '`' },

      -- Registers
      { mode = 'n', keys = '"' },
      { mode = 'x', keys = '"' },
      { mode = 'i', keys = '<C-r>' },
      { mode = 'c', keys = '<C-r>' },

      -- Window commands
      { mode = 'n', keys = '<C-w>' },

      -- `z` key
      { mode = 'n', keys = 'z' },
      { mode = 'x', keys = 'z' },

      -- Bracketed
      { mode = 'n', keys = '[' },
      { mode = 'n', keys = ']' },
    },
    clues = {
      miniclue.gen_clues.builtin_completion(),
      miniclue.gen_clues.g(),
      miniclue.gen_clues.marks(),
      miniclue.gen_clues.registers(),
      miniclue.gen_clues.windows(),
      miniclue.gen_clues.z(),
    },
    window = {
      delay = 0,
    },
  })
end, 0)
