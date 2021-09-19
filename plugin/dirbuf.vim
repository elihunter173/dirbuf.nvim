if exists("g:loaded_dirbuf")
  finish
endif

command! -nargs=? -complete=dir Dirbuf lua require'dirbuf'.open(<q-args>)

" This (dirbuf_up) mapping was from dirvish.vim
nnoremap <silent> <Plug>(dirbuf_up)
      \ <cmd>execute 'Dirbuf %:p'.repeat(':h', v:count1 + isdirectory(expand('%')))<cr>
nnoremap <silent> <Plug>(dirbuf_enter) <cmd>execute 'lua require"dirbuf".enter()'<cr>
nnoremap <silent> <Plug>(dirbuf_toggle_hide) <cmd>execute 'lua require"dirbuf".toggle_hide()'<cr>

if mapcheck('-', 'n') ==# '' && !hasmapto('<Plug>(dirbuf_up)', 'n')
  nmap - <Plug>(dirbuf_up)
endif

augroup dirbuf
  autocmd!
  " Makes editing a directory open a dirbuf
  autocmd BufEnter * if isdirectory(expand('<afile>'))
        \ | execute 'lua require"dirbuf".init_dirbuf(vim.fn.expand("<abuf>"))'
        \ | endif
augroup END

let g:loaded_dirbuf = 1
