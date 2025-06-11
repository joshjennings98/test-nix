-- show git information in gutter
vim.defer_fn(function()
  require('gitsigns').setup({
    signs = {
      add          = { text = '+' },
      change       = { text = '~' },
      delete       = { text = '_' },
      topdelete    = { text = '‾' },
      changedelete = { text = '-' },
      untracked    = { text = '*' },
    },
  })
end, 0)
