function! nvimhs#stack#pluginstarter()
	return
				\ { 'buildCommand': function('nvimhs#stack#buildCommand')
				\ , 'exePath': function('nvimhs#stack#exePath')
				\ }
endfunction


function! nvimhs#stack#buildCommand(name)
	return [ 'stack', 'build', a:name ]
endfunction


function! nvimhs#stack#exePath(workingDirectory, name)
	let l:stackPath = nvimhs#execute(a:workingDirectory,
				\ ['stack', 'path', '--local-install-root'])
	return join(l:stackPath, '') . '/bin/' . a:name
endfunction
