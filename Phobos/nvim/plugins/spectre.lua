-- VSCode-like find and replace
vim.keymap.set('n', '<space>F', '<cmd>lua require("spectre").toggle()<CR>', {
    desc = "Find and replace (spectre)"
})
