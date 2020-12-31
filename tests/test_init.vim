if !isdirectory('/tmp/plenary.nvim')
  !git clone https://github.com/nvim-lua/plenary.nvim.git /tmp/plenary.nvim
  !git -C /tmp/plenary.nvim reset --hard 08c0eabcb1fdcc5b72f60c3a328ae8eeb7ad374e
endif
set runtimepath+=/tmp/plenary.nvim,.
runtime plugin/plenary.vim
command Test PlenaryBustedDirectory tests/ {minimal_init = 'tests/test_init.vim'}
