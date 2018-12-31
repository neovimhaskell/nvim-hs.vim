function! nvimhs#stack#pluginstarter()
	return
				\ { 'build': function('nvimhs#stack#build')
				\ , 'start': function('nvimhs#stack#start')
				\ }
endfunction

function! nvimhs#stack#build(workingDirectory, name)
	" TODO error handling
	return jobwait(
				\ [ jobstart( [ 'stack', 'build' ]
				\           , { 'cwd': a:workingDirectory })
				\ ])
endfunction

function! nvimhs#stack#start(workingDirectory, name)
	return jobstart( [ 'stack', 'exec', a:name, '--', a:name ]
				\  , { 'rpc': v:true, 'cwd': a:workingDirectory }
				\  )
endfunction
