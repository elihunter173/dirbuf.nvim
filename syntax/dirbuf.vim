" What should I do for the skip?

syn region DirbufFile start=/'/ skip=/\\\\\|\\'/ end=/'/ keepend
hi link DirbufFile String

syn match DirbufHash /#\x\{7}$/
hi link DirbufHash Special
