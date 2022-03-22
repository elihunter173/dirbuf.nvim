if exists("g:loaded_dirbuf")
  finish
endif

command! -nargs=? -complete=dir Dirbuf lua require'dirbuf'.open(<q-args>)
command! -nargs=? -complete=customlist,s:DirbufSyncOptions DirbufSync lua require'dirbuf'.sync(<q-args>)

function! s:DirbufSyncOptions(arg_lead, cmd_line, cursor_pos)
  let options = ['-confirm', '-dry-run']
  return filter(options, 'v:val =~ "^'.a:arg_lead.'"')
endfunction

" This (dirbuf_up) mapping was taken from vim-dirvish
noremap <silent> <unique> <Plug>(dirbuf_up)
      \ <cmd>execute 'Dirbuf %:p'.repeat(':h', v:count1 + isdirectory(expand('%')))<cr>
noremap <silent> <unique> <Plug>(dirbuf_enter)
      \ <cmd>execute 'lua require"dirbuf".enter()'<cr>
noremap <silent> <unique> <Plug>(dirbuf_toggle_hide)
      \ <cmd>execute 'lua require"dirbuf".toggle_hide()'<cr>

if mapcheck('-', 'n') ==# '' && !hasmapto('<Plug>(dirbuf_up)', 'n')
  nmap - <Plug>(dirbuf_up)
endif

augroup dirbuf
  autocmd!
  " Remove netrw directory handlers.
  autocmd VimEnter * if exists('#FileExplorer') | execute 'autocmd! FileExplorer *' | endif
  " Makes editing a directory open a dirbuf. We always re-init the dirbuf
  autocmd BufEnter * if isdirectory(expand('%')) && !&modified
        \ | execute 'lua require"dirbuf".init_dirbuf()'
        \ | endif
augroup END

let g:loaded_dirbuf = 1
