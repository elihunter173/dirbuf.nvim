nnoremap <buffer><silent> <cr> <cmd>lua require'dirbuf'.enter()<cr>

augroup dirbuf_local
  autocmd! * <buffer>
  autocmd BufEnter <buffer> let b:dirbuf_old_dir = getcwd() | silent cd %
  autocmd BufLeave <buffer> execute 'silent cd '.fnameescape(b:dirbuf_old_dir)
  autocmd BufWriteCmd <buffer> lua require'dirbuf'.sync()
augroup END
