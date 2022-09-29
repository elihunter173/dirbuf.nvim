# dirbuf.nvim

A directory buffer for Neovim that lets you edit your filesystem like you edit
text. Inspired by [vim-dirvish] and [vidir].

## Features

* *Intuitive:* Create, copy, delete, and rename files, directories, and more by
  editing their lines in the directory buffer. Buffer names are automatically
  updated to reflect changes.
* *Minimal:* Works out of the box with no configuration. Default mappings
  easily changed.
* *Unobtrusive:* Preserves alternate buffers and navigation history. Switch
  between files with `Ctrl-^` (`Ctrl-6`) and jump around your navigation history
  with custom `<Plug>` mappings.
* *Safe:* Does not modify the filesystem until you save the buffer. Optionally
  request confirmation and dry-run saving.
* *Reliable:* Resolves inter-dependencies in batch renames, including cycles.
* *Polite:* Plays nicely with tree-based file viewers like [nvim-tree.lua],
  [fern.vim], and [carbon.nvim].

https://user-images.githubusercontent.com/42009212/162110083-9fd3701f-8ffb-4cf7-9333-d57020a9242e.mp4

## Installation

Requires [Neovim 0.6](https://github.com/neovim/neovim/releases/tag/v0.6.0) or
higher.

* [vim-plug]: `Plug "elihunter173/dirbuf.nvim"`
* [packer.nvim]: `use "elihunter173/dirbuf.nvim"`

### Notes

Other filesystem plugins can potentially prevent Dirbuf from opening directory buffers:

* If you use [`nvim-tree.lua`](https://github.com/kyazdani42/nvim-tree.lua),
  disable the `:help nvim-tree.update_to_buf_dir` option. 

```lua
require("nvim-tree").setup {
    update_to_buf_dir = { enable = false }
}
```

* If you use [`rnvimr`](https://github.com/kevinhwang91/rnvimr),
  disable the `:help rnvimr_enable_ex` option. 

```lua
vim.g.rnvimr_ex_enable = 0
```

## Usage

Run the command `:Dirbuf` to open a directory buffer. Press `-` in any buffer
to open a directory buffer for its parent. Editing a directory will also open
up a directory buffer, overriding Netrw.

Inside a directory buffer, there are the following keybindings:
* `<CR>`: Open the file or directory at the cursor.
* `gh`: Toggle showing hidden files (i.e. dot files).
* `-`: Open parent directory.

See `:help dirbuf.txt` for more info.

## Configuration

Configuration is not necessary for Dirbuf to work. But for those that want to
override the default config, the following options are available with their
default values listed.

```lua
require("dirbuf").setup {
    hash_padding = 2,
    show_hidden = true,
    sort_order = "default",
    write_cmd = "DirbufSync",
}
```

Read the [documentation](/doc/dirbuf.txt) for more information (`:help
dirbuf-options`).

## Development

A [Justfile][just] is provided to test and lint the project.

```sh
# Run unit tests
$ just test
# Run luacheck
$ just lint
```

`just test` will automatically download [plenary.nvim]'s test harness and run
the `*_spec.lua` tests in `tests/`.

[carbon.nvim]: https://github.com/SidOfc/carbon.nvim
[fern.vim]: https://github.com/lambdalisue/fern.vim
[just]: https://github.com/casey/just
[nvim-tree.lua]: https://github.com/kyazdani42/nvim-tree.lua
[packer.nvim]: https://github.com/wbthomason/packer.nvim
[plenary.nvim]: https://github.com/nvim-lua/plenary.nvim
[vidir]: https://github.com/trapd00r/vidir
[vim-dirvish]: https://github.com/justinmk/vim-dirvish
[vim-plug]: https://github.com/junegunn/vim-plug
