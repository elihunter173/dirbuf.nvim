if !isdirectory('/tmp/plenary.nvim')
  !git clone https://github.com/nvim-lua/plenary.nvim.git /tmp/plenary.nvim
endif
set runtimepath+=/tmp/plenary.nvim,.
runtime plugin/plenary.vim
command Test PlenaryBustedDirectory tests/ tests/test_init.vim
