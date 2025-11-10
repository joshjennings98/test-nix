-- completion provider
vim.defer_fn(function()
  require("luasnip.loaders.from_vscode").lazy_load() 

  require("blink.cmp").setup({
    keymap = {
      preset = 'none',
      ['<Tab>'] = { 'snippet_forward', 'select_next', 'fallback' },
      ['<S-Tab>'] = { 'snippet_backward', 'select_prev', 'fallback' },
      ['<CR>'] = { 'accept', 'fallback' },
      ['<C-k>'] = { 'show_documentation', 'hide_documentation', 'fallback' },
    },
    completion = {
        list = { selection = { preselect = true, auto_insert = false }, cycle = { from_top = true } },
    },
    signature = { enabled = true },
  })
end, 0)
