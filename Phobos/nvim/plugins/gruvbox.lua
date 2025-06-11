-- gruvbox colour scheme
require("gruvbox").setup({
  overrides = {
    GitSignsAdd    = { link = "GruvboxGreenSign" },
    GitSignsChange = { link = "GruvboxAquaSign" },
    GitSignsDelete = { link = "GruvboxRedSign" },
  }
})

vim.cmd("colorscheme gruvbox")
