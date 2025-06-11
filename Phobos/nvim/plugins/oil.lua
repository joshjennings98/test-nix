-- oil file explorer to replace netrw
require("oil").setup({
  view_options = {
    show_hidden = true
  }
})

vim.keymap.set("n", "<space>o", "<cmd>Oil<cr>", { desc = "Launch oil file explorer" })
