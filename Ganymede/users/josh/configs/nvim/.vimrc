" TODO: get rid of this and do it all in lua like https://github.com/joshjennings98/linux-stuff/tree/master/homedir/.config/nvim

" Load plugins
filetype plugin indent on

" Search
set ignorecase
set smartcase

" Tab completion
set wildmode=list:longest,full
set wildignore=*.swp,*.o,*.so,*.exe,*.dll

" Tab settings
set sw=4
set ts=4
set expandtab

" Hud
set termguicolors
syntax on
set ruler
set number
set nowrap
set fillchars=vert:\│
set colorcolumn=120
set cursorline
set relativenumber
set hidden
set list
set scrolloff=5

" Tags
set tags=./tags;/,tags;/

" Backup Directories
set backupdir=~/.config/nvim/backups,.
set directory=~/.config/nvim/swaps,.
if exists('&undodir')
  set undodir=~/.config/nvim/undo,.
endif

let mapleader=','
let maplocalleader=','

" Trim trailing whitespace
nnoremap <localleader>tw m`:%s/\s\+$//e<CR>:nohlsearch<CR>``

