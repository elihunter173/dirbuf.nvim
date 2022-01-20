" # Regex Breakdown
" (a) and (b) define all valid character units, so this regex matches one or
" more valid character units at the beginning of a line.
"
" /^\([^\\\t]\|\\[\\t]\)\+/
"     ^^(a)^^  ^^(b)^^
" (a): all valid single-characters (i.e. not tabs or escape sequences).
" (b): all valid escape sequences.
"
" Object suffixes (e.g. / for directories) are this regular expression with
" their appropriate suffix tacked on. The longest regex is the one
" highlighted, so the suffix always controls the color. We include me=e-1 set
" the 'match end' to be one before the normal 'end' so the suffix doesn't get
" highlighted.
"
" The suffixes are taken from `ls --clasisify` and zsh's tab completion.
syntax match DirbufFile /^\([^\\\t]\|\\[\\t]\)\+/
syntax match DirbufDirectory /^\([^\\\t]\|\\[\\t]\)\+\//me=e-1
syntax match DirbufLink /^\([^\\\t]\|\\[\\t]\)\+@/me=e-1
syntax match DirbufFifo /^\([^\\\t]\|\\[\\t]\)\+|/me=e-1
syntax match DirbufSocket /^\([^\\\t]\|\\[\\t]\)\+=/me=e-1
syntax match DirbufChar /^\([^\\\t]\|\\[\\t]\)\+%/me=e-1
syntax match DirbufBlock /^\([^\\\t]\|\\[\\t]\)\+#/me=e-1

" Highlight each object according to its color in by ls --color=always
highlight link DifbufFile Normal
function! s:SetColor(group_name, color_num)
  if !exists('g:terminal_color_0')
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num
  else
    let color = get(g:, 'terminal_color_'.a:color_num)
    execute 'highlight '.a:group_name.' ctermfg='.a:color_num.' gui=bold guifg='.color
  endif
endfunction
call s:SetColor('DirbufDirectory', 4)
call s:SetColor('DirbufLink', 6)
call s:SetColor('DirbufFifo', 2)
call s:SetColor('DirbufSocket', 5)
call s:SetColor('DirbufChar', 3)
call s:SetColor('DirbufBlock', 3)

" We include `ms=s+1` to not highlight the tab
syntax match DirbufHash /\t#\x\{8}\s*$/ms=s+1
highlight link DirbufHash Special

" ```
" ^\(\(The_Regular_Expression\)\@!.\)*$
" ```
" This finds every except for the regular expression
" See: https://vim.fandom.com/wiki/Search_for_lines_not_containing_pattern_and_other_helpful_searches#Searching_with_.2F
syntax match DirbufMalformedLine /^\(\(\_^\([^\\\t]\|\\[\\t]\)\+\(\t#\x\{8}\)\?\s*\_$\)\@!.\)*$/
highlight link DirbufMalformedLine Error
