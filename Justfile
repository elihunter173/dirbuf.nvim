all: test lint

test:
	nvim --headless --noplugin -u tests/test_init.vim +Test

lint:
	luacheck .
