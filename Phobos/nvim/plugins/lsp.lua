local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    -- Enable completion triggered by <c-x><c-o>
    vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

    -- Enable inlay hint support
    vim.lsp.inlay_hint.enable(true) 

    -- Buffer local mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = function(str)
      return { buffer = ev.buf, desc = str }
    end

    vim.keymap.set('n', '<space>k', vim.lsp.buf.hover, opts("LSP Hover"))
    vim.keymap.set('i', '<M-k>', vim.lsp.buf.hover, opts("LSP Hover"))
    vim.keymap.set('n', '<space>r', vim.lsp.buf.rename, opts("Rename Symbol"))
    vim.keymap.set({ 'n', 'v' }, '<space>a', vim.lsp.buf.code_action, opts("Code Action"))
    vim.keymap.set('n', '<localleader>f', function()
      vim.lsp.buf.format { async = true }
    end, opts("Format Buffer"))
  end,
})

local lspconfig = require('lspconfig')

-- Setup gopls with your custom settings
lspconfig.gopls.setup {
    capabilities = capabilities,
    settings = {
        gopls = {
            hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
            },
        },
    },
}
lspconfig.nil_ls.setup {}

