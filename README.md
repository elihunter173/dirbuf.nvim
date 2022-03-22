# dirbuf.nvim

A directory buffer for Neovim that lets you edit your filesystem like you edit
text. Inspired by [vim-dirvish] and [vidir].

## Features

* *Intuitive:* Create, copy, delete, and rename files, directories, and more by
  editing their lines in the directory buffer. Buffer names are automatically
  updated to reflect these changes.
* *Minimal:* Works out of the box with no configuration. Default mappings
  easily changed.
* *Unobtrusive:* Preserves alternate buffers, letting you switch between
  files with `Ctrl-^` (`Ctrl-6`).
* *Safe:* Does not modify the filesystem until you save the buffer. Optionally
  request confirmation and dry-run saving.
* *Reliable:* Resolves inter-dependencies in batch renames, including cycles.
* *Polite:* Plays nicely with tree-based file viewers like [nvim-tree.lua],
  [fern.vim], and [carbon.nvim].

https://user-images.githubusercontent.com/42009212/154371256-6421e01c-e54b-4436-8999-6f8516f2a624.mp4

## Installation

Requires [Neovim 0.5](https://github.com/neovim/neovim/releases/tag/v0.5.0) or
higher.

* [vim-plug]: `Plug "elihunter173/dirbuf.nvim"`
* [packer.nvim]: `use "elihunter173/dirbuf.nvim"`

### Notes

If you use [`nvim-tree.lua`](https://github.com/kyazdani42/nvim-tree.lua), you
must disable the `:help nvim-tree.update_to_buf_dir` option. Otherwise, Dirbuf
will fail to open directory buffers.

```lua
require("nvim-tree").setup {
    update_to_buf_dir = { enable = false }
}
```

If you notice `nvim /some/directory` opening Netrw instead of Dirbuf, you can
disable Netrw by adding the following to your `init.vim` or `init.lua`. This
issue only appears with certain package managers and affects other file manager
plugins as well. I am searching for a more elegant solution.

```vim
" init.vim
let g:loaded_netrwPlugin = 1
let g:loaded_netrw = 1
```

```lua
-- init.lua
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrw = 1
```

## Usage

Run the command `:Dirbuf` to open a directory buffer for your current
directory. Press `-` in any buffer to open a directory buffer for its parent.
Editing a directory will also open up a directory buffer, overriding Netrw.

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
    hash_first = true,
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
