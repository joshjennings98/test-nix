-- undotree for keeping track of changes
vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle, { desc = "Toggle UndoTree" } )
vim.g.undotree_WindowLayout = 2
vim.g.undotree_SplitWidth = 50
