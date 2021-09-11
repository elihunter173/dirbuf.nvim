map <buffer><silent> <cr> <Plug>(dirbuf_enter)
map <buffer><silent> gh <Plug>(dirbuf_toggle_hide)

augroup dirbuf_local
  autocmd! * <buffer>
  autocmd BufWriteCmd <buffer> lua require'dirbuf'.sync()
augroup END
