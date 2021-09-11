nnoremap <buffer><silent> <cr> <cmd>lua require'dirbuf'.enter()<cr>

augroup dirbuf_local
  autocmd! * <buffer>
  autocmd BufWriteCmd <buffer> lua require'dirbuf'.sync()
augroup END
