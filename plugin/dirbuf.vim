if exists("g:loaded_dirbuf")
  finish
endif

command! -nargs=? -complete=dir Dirbuf lua require'dirbuf'.open(<q-args>)

" Taken from dirvish.vim
nnoremap <silent> <Plug>(dirbuf_up)
      \ <cmd>execute 'Dirbuf %:p'.repeat(':h', v:count1 + isdirectory(expand('%')))<cr>
if mapcheck('-', 'n') ==# '' && !hasmapto('<Plug>(dirbuf_up)', 'n')
  nmap - <Plug>(dirbuf_up)
endif

augroup dirbuf
  autocmd!
  " Makes editing a directory open a dirbuf
  " TODO: For some reason `:edit .` on an already loaded dirbuf removes the
  " content
  autocmd BufEnter * if isdirectory(expand('<afile>'))
        \ | execute 'lua require"dirbuf".init_dirbuf(vim.fn.expand("<abuf>"))'
        \ | endif
augroup END

let g:loaded_dirbuf = 1
