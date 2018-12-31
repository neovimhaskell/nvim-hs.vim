function! s:buildStartAndRegister(pluginStarter, workingDirectory, name, host_info)
	" host_info is required by remote#host#register, but ignored here
	call call(a:pluginStarter.build, [ a:workingDirectory, a:name ])
	return call(a:pluginStarter.start, [ a:workingDirectory, a:name ])
endfunction

function! nvimhs#start(workingDirectory, name)
	try
		return remote#host#Require(a:name)
	catch
		let l:starter = get(g:, 'nvimhsPluginStarter')
		if ! l:starter
			let l:starter = nvimhs#stack#pluginstarter()
		endif

		let l:Factory = function('s:buildStartAndRegister'
					\ , [ l:starter, a:workingDirectory, a:name ])
		call remote#host#Register(a:name, '*', l:Factory)
	endtry
endfunction

function! nvimhs#restart(workingDirectory, name)
	try
		if remote#host#IsRunning(a:name)
			call chanclose(remote#host#Require(a:name))
		endif
	catch
		call nvimhs#start(a:workingDirectory, a:name)
	endtry
endfunction
