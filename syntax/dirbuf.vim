let s:hash_first = v:lua.require('dirbuf.config').get('hash_first')

" # Regex Breakdown
" (a) and (b) define all valid character units, so this regex matches one or
" more valid character units at the beginning of a line.
"
" /^\([^\\\t]\|\\[\\t]\)\+\t/
"     ^^(a)^^  ^^(b)^^    (c)
" (a): all valid single-characters (i.e. not tabs or escape sequences).
" (b): all valid escape sequences.
" (c): the end character (either \t or $)
"
" Object suffixes (e.g. / for directories) are this regular expression with
" their appropriate suffix tacked on. The longest regex is the one
" highlighted, so the suffix always controls the color. We include me=e-1 (or
" me=e-2 depending on suffix) to set the 'match end' to be one before the
" normal 'end' so the suffix doesn't get highlighted.
"
" The suffixes are taken from `ls --classify` and zsh's tab completion.
if s:hash_first
  function! s:SetMatch(group_name, suffix, suffix_len)
    execute 'syntax match 'a:group_name.' /\([^\\\t]\|\\[\\t]\)\+'.a:suffix.'$/me=e-'.(a:suffix_len)
  endfunction
else
  function! s:SetMatch(group_name, suffix, suffix_len)
    execute 'syntax match 'a:group_name.' /^\([^\\\t]\|\\[\\t]\)\+'.a:suffix.'\t/me=e-'.(a:suffix_len + 1)
    execute 'syntax match 'a:group_name.' /^\([^\\\t]\|\\[\\t]\)\+'.a:suffix.'$/me=e-'.(a:suffix_len)
  endfunction
endif
call s:SetMatch('DirbufFile', '', 0)
call s:SetMatch('DirbufDirectory', '[/\\]', 1)
call s:SetMatch('DirbufLink', '@', 1)
call s:SetMatch('DirbufFifo', '|', 1)
call s:SetMatch('DirbufSocket', '=', 1)
call s:SetMatch('DirbufChar', '%', 1)
call s:SetMatch('DirbufBlock', '\\$', 1)

" We include `ms=s+/-1` to not highlight the tab
if s:hash_first
  syntax match DirbufHash /^#\x\{8}\t/ms=s-1
else
  syntax match DirbufHash /\t#\x\{8}\s*$/ms=s+1
endif

" /^\(\(The_Regular_Expression\)\@!.\)*$/
" Finds every except for the regular expression
" See: https://vim.fandom.com/wiki/Search_for_lines_not_containing_pattern_and_other_helpful_searches#Searching_with_.2F
if s:hash_first
  syntax match DirbufMalformedLine /^\(\(\_^\(#\x\{8}\t\)\?\([^\\\t]\|\\[\\t]\)\+\\\?\_$\)\@!.\)*$/
else
  syntax match DirbufMalformedLine /^\(\(\_^\([^\\\t]\|\\[\\t]\)\+\\\?\(\t#\x\{8}\)\?\s*\_$\)\@!.\)*$/
endif

" Highlight each object according to its color in by ls --color=always
function! s:SetColor(group_name, color_num)
  if !exists('g:terminal_color_0')
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num
  else
    let color = get(g:, 'terminal_color_'.a:color_num)
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num.' gui=bold guifg='.color
  endif
endfunction
highlight link DifbufFile Normal
call s:SetColor('DirbufDirectory', 4)
call s:SetColor('DirbufLink', 6)
call s:SetColor('DirbufFifo', 2)
call s:SetColor('DirbufSocket', 5)
call s:SetColor('DirbufChar', 3)
call s:SetColor('DirbufBlock', 3)
highlight link DirbufHash Special

highlight link DirbufMalformedLine Error
