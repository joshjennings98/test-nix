{lib, pkgs, ...}:
{
  home.file.".config/nvim/lua/autocommands.lua".source = ./lua/autocommands.lua;
  home.file.".config/nvim/lua/mappings.lua".source = ./lua/mappings.lua;
  home.file.".config/nvim/lua/options.lua".source = ./lua/options.lua;

  home.activation.mkdirNvimFolders = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p $HOME/.config/nvim/backups $HOME/.config/nvim/swaps $HOME/.config/nvim/undo
  '';

  programs.neovim = {
    enable = true;
    extraLuaConfig = lib.fileContents ./init.lua;
    plugins = with pkgs.vimPlugins; [
      # UI and Themes
      {
        plugin = gruvbox-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/gruvbox.lua;
      }
      {
        plugin = oil-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/oil.lua;
      }
      {
        plugin = eyeliner-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/eyeliner.lua;
      }
      {
        plugin = gitsigns-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/gitsigns.lua;
      }
      {
        plugin = telescope-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/telescope.lua;
      }
      # Treesitter
      {
        plugin = nvim-treesitter.withAllGrammars;
        type = "lua";
        config = lib.fileContents ./plugins/treesitter.lua;
      }
      {
        plugin = nvim-treesitter-textobjects;
        type = "lua";
        config = lib.fileContents ./plugins/treesitter-text-objects.lua;
      }
      # Misc
      {
        plugin = mini-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/mini.lua;
      }
      nvim-autopairs
      targets-vim
      vim-eunuch     
      vim-fugitive
      {
        plugin = undotree;
        type = "lua";
        config = lib.fileContents ./plugins/undotree.lua;
      }
      {
        plugin = nvim-spectre;
        type = "lua";
        config = lib.fileContents ./plugins/spectre.lua;
      }
      {
        plugin = refactoring-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/refactoring.lua;
      }
      {
        plugin = harpoon2;
        type = "lua";
        config = lib.fileContents ./plugins/harpoon.lua;
      }
      {
        plugin = yanky-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/yanky.lua;
      }
      # LSP and Completion
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-nvim-lsp-signature-help
      friendly-snippets
      luasnip
      cmp_luasnip
      {
        plugin = nvim-cmp;
        type = "lua";
        config = lib.fileContents ./plugins/cmp.lua;
      }
      {
        plugin = nvim-lspconfig;
        type = "lua";
        config = lib.fileContents ./plugins/lsp.lua;
      }
      # DAP
      nvim-dap-go
      nvim-dap-ui
      nvim-dap-virtual-text
      {
        plugin = nvim-dap;
        type = "lua";
        config = lib.fileContents ./plugins/dap.lua;
      }
    ];
  };
}

