nnoremap <buffer><silent> <CR> <Cmd>execute 'lua require"dirbuf".enter()'<CR>
nnoremap <buffer><silent> gh <Cmd>execute 'lua require"dirbuf".toggle_hide()'<CR>

augroup dirbuf_local
  autocmd! * <buffer>
  autocmd BufWriteCmd <buffer> lua require'dirbuf'.sync()
augroup END
