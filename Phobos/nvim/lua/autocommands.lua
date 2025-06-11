-- auto resize buffers when window is resized
vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("WinResize", { clear = true }),
    pattern = "*",
    command = "wincmd =",
})

-- auto format on save
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    group = vim.api.nvim_create_augroup("buf_write_pre_format", { clear = true }),
    pattern = "*",
    command = "lua vim.lsp.buf.format()",
})
