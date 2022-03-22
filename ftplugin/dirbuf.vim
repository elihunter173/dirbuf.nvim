if !hasmapto('<Plug>(dirbuf_enter)')
  nmap <buffer> <cr> <Plug>(dirbuf_enter)
endif
if !hasmapto('<Plug>(dirbuf_toggle_hide)')
  nmap <buffer> gh <Plug>(dirbuf_toggle_hide)
endif
if !hasmapto('<Plug>(dirbuf_up)')
  nmap <buffer> - <Plug>(dirbuf_up)
endif

augroup dirbuf_local
  autocmd! * <buffer>
  autocmd BufWriteCmd <buffer> execute v:lua.require('dirbuf.config').get('write_cmd')
augroup END
