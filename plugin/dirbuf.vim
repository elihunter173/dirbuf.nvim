if exists('g:loaded_dirbuf')
  finish
endif

command! -nargs=* -complete=file Dirbuf lua require'dirbuf'.open(vim.fn.glob(<q-args>), true)
command! DirbufNext lua require'dirbuf'.next()
command! DirbufPrev lua require'dirbuf'.prev()
command! DirbufQuit lua require'dirbuf'.quit()
command! -nargs=? -complete=customlist,s:DirbufSyncOptions DirbufSync lua require'dirbuf'.sync(<q-args>)

function! s:DirbufSyncOptions(arg_lead, cmd_line, cursor_pos)
  let options = ['-confirm', '-dry-run']
  return filter(options, 'v:val =~ "^'.a:arg_lead.'"')
endfunction

" This (dirbuf_up) mapping was taken from vim-dirvish
noremap <unique> <Plug>(dirbuf_up) <cmd>execute 'Dirbuf %:p'.repeat(':h', v:count1 + isdirectory(expand('%')))<cr>
noremap <unique> <Plug>(dirbuf_enter) <cmd>execute 'lua require"dirbuf".enter()'<cr>
noremap <unique> <Plug>(dirbuf_toggle_hide) <cmd>execute 'lua require"dirbuf".toggle_hide()'<cr>
noremap <unique> <Plug>(dirbuf_history_forward) <cmd>execute 'lua require"dirbuf".jump_history('v:count1')'<cr>
noremap <unique> <Plug>(dirbuf_history_backward) <cmd>execute 'lua require"dirbuf".jump_history(-'v:count1')'<cr>

if mapcheck('-', 'n') ==# '' && !hasmapto('<Plug>(dirbuf_up)', 'n')
  nmap - <Plug>(dirbuf_up)
endif

augroup dirbuf
  autocmd!
  " Makes editing a directory open a dirbuf. We always re-init the dirbuf
  autocmd BufEnter * if isdirectory(expand('%')) && !&modified
        \ | execute 'lua require"dirbuf".init_dirbuf(vim.b.dirbuf_history, vim.b.dirbuf_history_index, true)'
        \ | endif
  " Netrw hijacking for vim-plug and &rtp friends
  autocmd VimEnter * if exists('#FileExplorer') | execute 'autocmd! FileExplorer *' | endif
augroup END
" Netrw hijacking for packer and packages friends
if exists('#FileExplorer') | execute 'autocmd! FileExplorer *' | endif

let g:loaded_dirbuf = 1
