# WIP Note

This plugin is a work in progress. It isn't feature complete and has bugs.
However, it is workable enough that I've started dogfooding it.

Here is a quick list of features implemented.

* Directory Viewing:
  * [x] Dirbuf refreshing after changes.
  * [x] Opening directories.
  * [x] Opening files.
  * [x] Hiding hidden files.
  * [ ] Previewing files.
  * [ ] Subdirectories as "folds".
* Directory Modification:
  * [x] Basic file deleting.
  * [x] Basic file copying. (As long as the names don't collide with any other
    files, even if those files are moved.)
  * [x] Basic file renaming. (Same note as above.)
  * [x] Creating new files.
  * [ ] Order dependent changes (e.g. renaming `a -> b` and `b -> c`).
  * [ ] Circular renaming.
  * [ ] Concurrent action execution.
* Misc:
  * [x] An easy way to refresh dirbufs.
  * [ ] Useful errors messages.
  * [ ] Docs.

# dirbuf.nvim

A directory buffer for Neovim, inspired by dirvish.vim and vidir.

## Development

Run the following command to run the tests.

```sh
$ make test
```

This will download plenary.vim's test harness and run the `*_spec.lua` tests in
`tests/`.
