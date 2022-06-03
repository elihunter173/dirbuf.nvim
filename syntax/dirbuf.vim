" # Regex Breakdown
"
" /^\([^\\\t]\|\\[\\t]\)\+$/
"     ^^(a)^^  ^^(b)^^   (c)
" (a): all valid single-characters (i.e. not tabs or escape sequences).
" (b): all valid escape sequences.
" (c): suffix + $ (end of line)
"
" The longest regex is the one highlighted, so the suffix always controls the
" color. We include `me=e-suffix_len` to set the 'match end' to be one before
" the normal 'end' so the suffix doesn't get highlighted.
"
" The suffixes are taken from `ls --classify` and zsh's tab completion.
function! s:SetMatch(group_name, suffix, suffix_len)
  execute 'syntax match 'a:group_name.' /\([^\\\t]\|\\[\\nt]\)\+'.a:suffix.'$/me=e-'.a:suffix_len
endfunction
call s:SetMatch('DirbufFile', '', 0)
call s:SetMatch('DirbufDirectory', '[/\\]', 1)
call s:SetMatch('DirbufLink', '@', 1)
call s:SetMatch('DirbufFifo', '|', 1)
call s:SetMatch('DirbufSocket', '=', 1)
call s:SetMatch('DirbufChar', '%', 1)
call s:SetMatch('DirbufBlock', '\\$', 1)

" We include `ms=s-1` to not highlight the tab
syntax match DirbufHash /^#\x\{8}\t/ms=s-1

" /^\(\(The_Regular_Expression\)\@!.\)*$/
" Finds every except for the regular expression
" See: https://vim.fandom.com/wiki/Search_for_lines_not_containing_pattern_and_other_helpful_searches#Searching_with_.2F
syntax match DirbufMalformedLine /^\(\(\_^\(#\x\{8}\t\)\?\([^\\\t]\|\\[\\nt]\)\+\\\?\_$\)\@!.\)*$/

" Highlight each object according to its color in by ls --color=always. This
" fallback system was taken and modified from nvim-tree.lua's colors.lua
function! s:SetColor(group_name, color_num, fallback_group, fallback_color)
  if exists('g:terminal_color_'.a:color_num)
    let l:color = get(g:, 'terminal_color_'.a:color_num)
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num.' gui=bold guifg='.l:color
    return
  endif
  let l:id = v:lua.vim.api.nvim_get_hl_id_by_name(a:fallback_group)
  let l:foreground = synIDattr(synIDtrans(id), "fg")
  if l:foreground !=# ''
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num.' gui=bold guifg='.l:foreground
  else
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num.' gui=bold guifg='.a:fallback_color
  endif
endfunction

highlight link DifbufFile Normal
if exists('g:terminal_color_4')
  execute 'highlight DirbufDirectory ctermfg=4 gui=bold guifg='.g:terminal_color_4
else
  highlight link DirbufDirectory Directory
endif
call s:SetColor('DirbufLink', 6, 'Conditional', 'Cyan')
call s:SetColor('DirbufFifo', 2, 'Character', 'Green')
call s:SetColor('DirbufSocket', 5, 'Define', 'Purple')
call s:SetColor('DirbufChar', 3, 'PreProc', 'Yellow')
call s:SetColor('DirbufBlock', 3, 'PreProc', 'Yellow')

highlight link DirbufHash Special

highlight link DirbufMalformedLine Error
