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
        plugin = telescope-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/telescope.lua;
      }
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
      targets-vim
      {
        plugin = mini-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/mini.lua;
      }
      {
        plugin = multicursor-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/multicursor.lua;
      }
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
      {
        plugin = which-key-nvim;
        type = "lua";
        config = lib.fileContents ./plugins/which-key.lua;
      }
      friendly-snippets
      luasnip
      {
        plugin = blink-cmp;
        type = "lua";
        config = lib.fileContents ./plugins/cmp.lua;
      }
      {
        plugin = nvim-lspconfig;
        type = "lua";
        config = lib.fileContents ./plugins/lsp.lua;
      }
      nvim-dap-go
      nvim-dap-view
      {
        plugin = nvim-dap;
        type = "lua";
        config = lib.fileContents ./plugins/dap.lua;
      }
    ];
  };
}
