-- treesitter support for use in highlighting etc.
require'nvim-treesitter.configs'.setup {
  highlight = { 
    enable = true,
    additional_vim_regex_highlighting = true,
  },
  indent = { enable = true },
}
