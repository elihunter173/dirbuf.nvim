all: test lint

test:
	nvim --headless --clean -u tests/test_init.vim +Test

lint:
	luacheck .
