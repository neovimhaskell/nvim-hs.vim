" This script is used to manage compiling and starting nvim-hs based plugin hosts.
"
" Since commands a la 'stack exec' can delay the startup time of a plugin
" significantly (a few secondes) and executing the appropriately built
" binary is almost instant, this script uses a simple caching mechanism to
" optimistically start existing binaries whose location is read from a
" cache file.
"
" Only if there is no cached entry or the binary inside that entry doesn't
" exist, the compilation is done before starting the binary/plugin host.
"
" If the started binary is old, the user is notified of this and can restart
" neovim to have it start with the current version of the plugins.

" Exposed API {{{1

function! nvimhs#start(workingDirectory, name, args)
	if ! len(s:cached_bin_paths)
		call s:readCachedBinPaths()
	endif
	call s:addStartParams(a:name, a:workingDirectory, a:args)
	try
		let l:chan = remote#host#Require(a:name)
		if l:chan
			try
				" Hack to test if the channel is still working
				call rpcrequest(l:chan, 'Ping', [])
				return l:chan
			catch 'No Provider for:.*'
				" Message returned by nvim-hs if the function does not exist
				return l:chan
			catch
				" Channel is not working, call the usual starting mechanism
			endtry
		endif
	catch
		" continue
	endtry
	let l:starter = get(g:, 'nvimhsPluginStarter', {})
	if len(l:starter) == 0
		let l:starter = nvimhs#stack#pluginstarter()
	endif

	let l:Factory = function('s:buildStartAndRegister'
				\ , [ { 'pluginStarter': l:starter
				\     , 'cwd': a:workingDirectory
				\     , 'name': a:name
				\     , 'args': a:args
				\     }
				\   ])
	call remote#host#Register(a:name, '*', l:Factory)
	return remote#host#Require(a:name)
endfunction

" This will forcibly close the RPC channel and call nvimhs#start. This will
" cause the state of the plugin to be lost. There is no standard way to keep
" state across restarts yet, so use with care.
function! nvimhs#restart(name)
	try
		if remote#host#IsRunning(a:name)
			call chanclose(remote#host#Require(a:name))
		endif
	finally
		let l:startParams = get(s:cached_start_params_by_name, a:name, {})
		if len(l:startParams)
			call nvimhs#start(l:startParams.cwd, a:name, l:startParams.args)
		else
			throw 'Cannot find cached startup information for ' . a:name
		endif
	endtry
endfunction

" This function basically calls nvimhs#restart, except that the
" recompilation of the plugin is guaranteed. For implementation reasons,
" this variant can be useful if you did not commit your changes in the
" repository that the plugin resides in.
function! nvimhs#compileAndRestart(name)
	let l:startParams = get(s:cached_start_params_by_name, a:name, {})
	if len(l:startParams)
		let s:cached_bin_paths[l:startParams.cwd]['hash'] = ''
	endif
	call nvimhs#restart(a:name)
endfunction

" Utility functions {{{2
" Synchronously determine the git commit hash of a directory.
function! nvimhs#gitCommitHash(directory)
	return join(
				\ nvimhs#execute(a:directory,
				\   { 'cmd': 'git rev-parse HEAD || echo no-commits-or-repository' })
				\ , '')
endfunction

" Internal functions {{{1
" The output of started processes via jobstart seems to always leave a
" trailing empty line. This function removes it.
function! s:removeTrailingEmptyLine(lines)
	if len(a:lines) && ! len(a:lines[-1])
		return a:lines[0:-2]
	else
		return a:lines
	endif
endfunction

" Jobs are started with buffered output for stdout and stderr, this function
" is used as the callback to store that output without creating temporary
" files or buffers.
function! s:appendToList(list, jobId, data, event)
	for l:e in s:removeTrailingEmptyLine(a:data)
		call add(a:list, l:e)
	endfor
endfunction

" General template for a callback function that also allows chaining
" commands. The approach is continuation based and works as follows.
function! s:onExit(directory, cmd, out, err, jobId, code, event)
	if a:code != 0
		if type(a:cmd) == type([])
			let l:cmd = join(a:cmd)
		else
			let l:cmd = join(a:cmd.cmd)
		endif
		echohl Error
		echom 'Failed to execute (cwd: ' . a:directory . '): ' . l:cmd
		echohl None
		if len(a:err) || len(a:out)
			tabnew
			call append(0, 'Failed to execute (cwd: ' . a:directory . '): '
						\ . l:cmd)
			for l:errLine in a:err
				call append(line('$'), l:errLine)
			endfor
			for l:outLine in a:out
				call append(line('$'), l:outLine)
			endfor
			setlocal nomodifiable
		endif
	elseif get(a:cmd, 'nextStep', 0) != 0
		let l:executeNext = call(a:cmd.nextStep, [a:out])
		if len(l:executeNext)
			call nvimhs#execute(a:directory, l:executeNext)
		endif
	endif
endfunction

" Executes a command with the given directory as the working directory.
"
" A command (cmd parameter) is an object with the fields cmd and nextStep
" (optional). The cmd field is an array of strings and is passed to the
" jobstart() function. The nextStep field is a funcref that is passed the
" stdout lines of the previous command and should either return a new
" command object or an empty command object if no further commands should be
" executed.
"
" The result of this function is the stdout ouput (list of lines) of the
" last executed command.
function! nvimhs#execute(directory, cmd)
	let l:out = []
	let l:err = []
	let l:Fout = funcref('s:appendToList', [l:out])
	let l:Ferr = funcref('s:appendToList', [l:err])
	let l:FonExit = funcref('s:onExit',
				\ [a:directory, a:cmd, l:out, l:err])
	if type(a:cmd) == type([])
		let l:cmd = a:cmd
	else
		let l:cmd = get(a:cmd, 'cmd', [])
	endif
	if len(l:cmd) == 0
		return []
	endif
	let l:job = jobstart(l:cmd, {
				\ 'on_stdout': l:Fout,
				\ 'stdout_buffered': 1,
				\ 'on_stderr': l:Ferr,
				\ 'stderr_buffered': 1,
				\ 'cwd': a:directory,
				\ 'on_exit': l:FonExit
				\ })
	call jobwait([l:job])
	return l:out
endfunction

" Basically the same as the synchronous variant, except that this one will
" not return the stdout ouput (list of lines) of the last command executed.
function! nvimhs#executeAsync(directory, cmd)
	let l:out = []
	let l:err = []
	let l:Fout = funcref('s:appendToList', [l:out])
	let l:Ferr = funcref('s:appendToList', [l:err])
	let l:FonExit = funcref('s:onExit',
				\ [a:directory, a:cmd, l:out, l:err])
	if type(a:cmd) == type([])
		let l:cmd = a:cmd
	else
		let l:cmd = a:cmd.cmd
	endif
	return jobstart(a:cmd.cmd, {
				\ 'on_stdout': l:Fout,
				\ 'stdout_buffered': 1,
				\ 'on_stderr': l:Ferr,
				\ 'stderr_buffered': 1,
				\ 'cwd': a:directory,
				\ 'on_exit': l:FonExit
				\ })

endfunction

" Starting {{{1
function! s:startAndUpdateCache(pluginHost, hash)
	let l:exe = call( a:pluginHost.pluginStarter.exePath
				\   , [ a:pluginHost.cwd, a:pluginHost.name ]
				\   )
	let l:cached = s:addBinPath(a:pluginHost.cwd, l:exe, a:hash)
	call s:saveCachedBinPaths()
	return jobstart([l:exe] + a:pluginHost.args
				\  , { 'cwd': a:pluginHost.cwd, 'rpc': v:true, }
				\  )

endfunction

function! s:ifHashDiffersBuildAndStart(pluginHost, cached, out)
	let l:currentHash = join(a:out, '')
	if l:currentHash == get(a:cached, 'hash', '') && len(l:currentHash)
		return {}
	else
		let l:buildCommand = call( a:pluginHost.pluginStarter.buildCommand
					\            , [a:pluginHost.name])
		call nvimhs#execute(
					\   a:pluginHost.cwd
					\ , l:buildCommand
					\ )
		return s:startAndUpdateCache(
					\   a:pluginHost
					\ , nvimhs#gitCommitHash(a:pluginHost.cwd)
					\ )
	endif
endfunction

function! s:buildStartAndRegister(pluginHost, host_info)
	" host_info is required by remote#host#register, but ignored here

	let l:cached = get(s:cached_bin_paths, a:pluginHost.cwd, {})
	let l:exe = get(l:cached, 'exe', '')
	if len(glob(l:exe))
		" XXX can probably be refactored to not repeat the git rev-parse
		" HEAD execution. This will become more important once other
		" hash functions are imlemented to detect changes.
		let l:IfHashDiffers = funcref( 's:ifHashDiffersBuildAndStart'
					\                , [a:pluginHost, l:cached]
					\                )

		let l:testAndBuild = { 'cmd': 'git rev-parse HEAD || echo no-commits-or-repository'
					\        , 'nextStep': l:IfHashDiffers
					\        }
		call nvimhs#executeAsync(a:pluginHost.cwd, l:testAndBuild)
		return jobstart( [l:cached.exe] + a:pluginHost.args
					\  , { 'cwd': a:pluginHost.cwd
					\    , 'rpc': v:true
					\    }
					\  )
	else
		echom 'Building nvim-hs plugin: ' . a:pluginHost.name
		call s:ifHashDiffersBuildAndStart(a:pluginHost, l:cached, [''])
	endif
endfunction

" Caching {{{1
let s:cache_dir = exists('$XDG_CACHE_HOME') ? $XDG_CACHE_HOME : $HOME . '/.cache'
let s:cached_bin_paths_file = expand(s:cache_dir) . '/nvim/nvim-hs-bin-paths'
let s:cached_start_params_by_name = {}
let s:cached_bin_paths = {}


function! s:addBinPath(absolute_plugin_dir, absolute_bin_file, buildId)
	let l:cached = { 'exe': a:absolute_bin_file
				\  , 'hash': a:buildId
				\  }
	let s:cached_bin_paths[a:absolute_plugin_dir] = l:cached
	return l:cached
endfunction

function! s:addStartParams(name, workingDirectory, args)
	let l:params = { 'cwd': a:workingDirectory, 'args': a:args }
	let s:cached_start_params_by_name[a:name] = l:params
	return l:params
endfunction

function! s:readCachedBinPaths()
	try
		let l:lines = readfile(s:cached_bin_paths_file)
	catch
		let l:lines = []
	endtry
	for l:line in l:lines
		let l:paths = split(l:line, '	', 0)
		if len(l:paths) != 3
			throw 'broken cached binary path file'
		endif
		call s:addBinPath(l:paths[0], l:paths[1], l:paths[2])
	endfor
	return s:cached_bin_paths
endfunction


function! s:saveCachedBinPaths()
	let l:entries_to_write = []
	for l:i in items(s:cached_bin_paths)
		call add(l:entries_to_write,
					\ join([l:i[0], l:i[1].exe, l:i[1].hash], '	'))
	endfor
	return writefile(l:entries_to_write, s:cached_bin_paths_file)
endfunction


" }}}1

