if exists("g:loaded_dirbuf")
  finish
endif
let g:loaded_dirbuf = 1

command! -nargs=? -complete=dir Dirbuf lua require'dirbuf'.open(<q-args>)

" TODO: Can I dispatch these commands by filetype?
augroup dirbuf
  autocmd!
  autocmd BufWriteCmd dirbuf://* lua require'dirbuf'.sync()
augroup END
