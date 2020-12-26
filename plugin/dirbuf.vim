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

" TODO: Automatically open directories with dirbuf

let g:loaded_dirbuf = 1
