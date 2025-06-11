vim.g.mapleader = " "             -- change leader key to space
vim.wo.number = true              -- show line numbers
vim.wo.relativenumber = true      -- show relative line numbers
vim.wo.colorcolumn = "120"        -- line at 120 characters
vim.opt.signcolumn = "yes"        -- always show signcolumn
vim.opt.tabstop = 4               -- set tabwidth to 4
vim.opt.shiftwidth = 4            -- number of spaces for auto indent
vim.opt.shiftround = true         -- round indent to nearest multiple of shiftwidth
vim.opt.expandtab = true          -- tabs == spaces
vim.opt.termguicolors = true      -- fix colours
vim.opt.shell = "/usr/bin/fish"   -- set shell to fish
vim.opt.linebreak = true          -- don"t break in middle of word
vim.opt.ignorecase = true         -- ignore the case in search
vim.opt.smartcase = true          -- unless upper case is used
vim.opt.smartindent = true        -- smart autoindenting when starting a new line
vim.opt.scrolloff = 10            -- keep 10 lines belopw cursor
vim.opt.undofile = true           -- use persistent undofile (keep undotree between loads)
vim.cmd.colorscheme "gruvbox"     -- set colour scheme to gruvbox
vim.o.background = "dark"         -- set background to dark (for gruvbox)
vim.o.updatetime = 250            -- set updatetime to 1/4 seconds

-- indent blanklines without plugin
vim.opt.list = true
vim.opt.listchars = {
    tab = "│ ",
    trail = " ",
    precedes = " ",
    extends = " ",
    space = " ",
    nbsp = " ",
}
local function update_lead()
    local lcs = vim.opt_local.listchars:get()
    local tab = vim.fn.str2list(lcs.tab)
    local space = vim.fn.str2list(lcs.multispace or lcs.space)
    local lead = {tab[1]}
    for i = 1, vim.bo.tabstop-1 do
        lead[#lead+1] = space[i % #space + 1]
    end
    vim.opt_local.listchars:append({ leadmultispace = vim.fn.list2str(lead) })
end
vim.api.nvim_create_autocmd("OptionSet", { pattern = { "listchars", "tabstop", "filetype" }, callback = update_lead })
vim.api.nvim_create_autocmd("VimEnter", { callback = update_lead, once = true })

-- clipboard=unnamedplus slows down neovim initial load so defer it 
vim.defer_fn(function()
    vim.opt.clipboard = "unnamedplus" -- copy to system clipboard
end, 0)

-- use rg
vim.o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
vim.opt.grepformat = vim.opt.grepformat ^ { "%f:%l:%c:%m" }

vim.fn.sign_define("DiagnosticSignError", {text = "E", hl = "DiagnosticSignError", texthl = "DiagnosticSignError", culhl = "DiagnosticSignErrorLine"})
vim.fn.sign_define("DiagnosticSignWarn", {text = "W", hl = "DiagnosticSignWarn", texthl = "DiagnosticSignWarn", culhl = "DiagnosticSignWarnLine"})
vim.fn.sign_define("DiagnosticSignInfo", {text = "I", hl = "DiagnosticSignInfo", texthl = "DiagnosticSignInfo", culhl = "DiagnosticSignInfoLine"})
vim.fn.sign_define("DiagnosticSignHint", {text = "H", hl = "DiagnosticSignHint", texthl = "DiagnosticSignHint", culhl = "DiagnosticSignHintLine"})

-- make <Tab> work for snippets
vim.keymap.set({ 'i', 's' }, '<Tab>', function()
   if vim.snippet.active({ direction = 1 }) then
     return '<cmd>lua vim.snippet.jump(1)<cr>'
   else
     return '<Tab>'
   end
end, { expr = true })

-- setup directories for undo and swaps etc.
vim.opt.backupdir = { vim.fn.expand("~/.config/nvim/backups"), "." }
vim.opt.directory = { vim.fn.expand("~/.config/nvim/swaps"), "." }
if vim.fn.has("persistent_undo") == 1 or vim.opt.undodir ~= nil then
  vim.opt.undodir = { vim.fn.expand("~/.config/nvim/undo"), "." }
end
