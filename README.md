# nvim-hs.vim

This repository/plugin contains functions to help start a
[nvim-hs](https://github.com/neovimhaskell/nvim-hs) plugin as a separate
process.

More detailed help is available via `:help nvim-hs.txt` once this plugin is
installed.

## Installation

Install this as you would any other github-based plugin.

If you use [vim-plug](https://github.com/junegunn/vim-plug), simply add
it as a plugin:

```vimL
Plug 'neovimhaskell/nvim-hs.vim'
```

If you have a preference for a tool chain, configure the variable
`g:nvimhsPluginStarter`. By default `stack` is used. The following starters are
shipped with this plugin, simply copy and paste the one you like to your neovim
configuration:

```vimL
let g:nvimhsPluginStarter=nvimhs#stack#pluginstarter()
```

## For plugin authors

The functions provided use the user-specified plugin starter to build and
start an `nvim-hs`-plugin. Since `stack` is used as the default and because of
its reproducibility, I would strongly recommend adding a working `stack.yaml`
configuration file to the repository.

Other than that, you are free to enrich your user's experience by providing
other means of installation, such as a `shell.nix` file for your nix user base.


