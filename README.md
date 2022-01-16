# dirbuf.nvim

A directory buffer for Neovim, inspired by [dirvish.vim] and [vidir].

## What is Dirbuf?

Dirbuf was created with the idea that you should be able to manipulate your
filesystem just like you manipulate text.

So to create a new file, add a new line with the file's name. You can also add
a `/` to make it a directory instead. To delete a file or directory, delete its
line. To copy, copy its line and give it a new name. To rename, change its
name.

You can make as many changes as you like. They won't take effect until you
save.

https://user-images.githubusercontent.com/42009212/149638284-c944bbcc-bb25-4bd5-b8a3-994d03c79d95.mp4

## Installation

Requires [Neovim 0.5](https://github.com/neovim/neovim/releases/tag/v0.5.0) or
higher.

* [vim-plug]: `Plug "elihunter173/dirbuf.nvim"`
* [packer.nvim]: `use "elihunter173/dirbuf.nvim"`

## Usage

Run the command `:Dirbuf` to open a directory buffer for your current
directory. Press `-` in any buffer to open a directory buffer for its parent.
Editing a directory will also open up a directory buffer, overriding Netrw.

Inside a directory buffer, there are the following keybindings:
* `<CR>`: Open the file or directory at the cursor.
* `gh`: Toggle showing hidden files (i.e. dot files).

See `:help dirbuf.txt` for more info.

## Configuration

Configuration is not necessary for Dirbuf to work. But for those that want to
override the default config, the following options are available.

```lua
require("dirbuf").setup {
    hash_padding = 2,
    show_hidden = true,
}
```

Read the [documentation](/doc/dirbuf.txt) for more information (`:help
dirbuf-options`).

## Development

Run the following command to run the tests.

```sh
$ make test
```

This will download [plenary.nvim]'s test harness and run the `*_spec.lua` tests
in `tests/`.

[dirvish.vim]: https://github.com/justinmk/vim-dirvish
[packer.nvim]: https://github.com/wbthomason/packer.nvim
[plenary.nvim]: https://github.com/nvim-lua/plenary.nvim
[vidir]: https://github.com/trapd00r/vidir
[vim-plug]: https://github.com/junegunn/vim-plug
