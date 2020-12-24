if exists("g:loaded_dirbuf")
  finish
endif

command! -nargs=? -complete=dir Dirbuf lua require'dirbuf'.open(<q-args>)

" Taken from dirvish.vim
if mapcheck('-', 'n') ==# ''
  nnoremap <silent> - <cmd>exe 'Dirbuf %:p'.repeat(':h', v:count1)<cr>
endif

" TODO: Can I dispatch these commands by filetype?
augroup dirbuf
  autocmd!
  autocmd BufWriteCmd dirbuf://* lua require'dirbuf'.sync()
augroup END

let g:loaded_dirbuf = 1
