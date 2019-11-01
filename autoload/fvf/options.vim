
let s:is_win = has('win32') || has('win64')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:h:h:h').'/bin/'
let s:bin = {
\ 'preview': s:bin_dir.'preview.sh',
\ 'tags':    s:bin_dir.'tags.pl' }
let s:TYPE = {'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}
if s:is_win
  if has('nvim')
    let s:bin.preview = split(system('for %A in ("'.s:bin.preview.'") do @echo %~sA'), "\n")[0]
  else
    let s:bin.preview = fnamemodify(s:bin.preview, ':8')
  endif
  let s:bin.preview = 'bash '.escape(s:bin.preview, '\')
endif

"let g:fzf_preview_excluded = ['history']
let g:fvf_default_options = get(g:, 'fvf_default_options', {'_':      '--multi --reverse'})
let g:fvf_extract_pattern = get(g:, 'fvf_extract_pattern', {'_':      '^.git$'})
let g:fvf_preview_style   = get(g:, 'fvf_preview_style',   {'_':      'right:60%:wrap'})
let g:fvf_layout          = get(g:, 'fvf_layout',          {'window': 'right'})


function! fvf#options#_extend_opts(dict, eopts, prepend) abort
  if empty(a:eopts) | return | endif

  if has_key(a:dict, 'options')
    if type(a:dict.options) == s:TYPE.list && type(a:eopts) == s:TYPE.list
      if a:prepend
        let a:dict.options = extend(copy(a:eopts), a:dict.options)
      else
        call extend(a:dict.options, a:eopts)
      endif
    else
      let all_opts = a:prepend ? [a:eopts, a:dict.options] : [a:dict.options, a:eopts]
      let a:dict.options = join(map(all_opts, 'type(v:val) == s:TYPE.list ? join(map(copy(v:val), "fzf#shellescape(v:val)")) : v:val'))
    endif
  else
    let a:dict.options = a:eopts
  endif
endfunction

function! fvf#options#_merge_opts(dict, eopts) abort
  return fvf#options#_extend_opts(a:dict, a:eopts, 0)
endfunction

function! fvf#options#_prepend_opts(dict, eopts) abort
  return fvf#options#_extend_opts(a:dict, a:eopts, 1)
endfunction

" [[options to wrap], [preview window expression], [toggle-preview keys...]]
function! fvf#_preview(...) abort
  " Default options
  let options = {}
  let window = g:fvf_layout['_']

  let args = copy(a:000)

  " Options to wrap
  if len(args) && type(args[0]) == s:TYPE.dict
    let options = copy(args[0])
    call remove(args, 0)
  endif

  " Preview window
  if len(args) && type(args[0]) == s:TYPE.string
    if args[0] !~# '^\(up\|down\|left\|right\)'
      throw 'invalid preview window: '.args[0]
    endif
    let window = args[0]
    call remove(args, 0)
  endif

  let preview = ['--preview-window', window, '--preview', (s:is_win ? s:bin.preview : fzf#shellescape(s:bin.preview)).' {}']

  if len(args)
    call extend(preview, ['--bind', join(map(args, 'v:val.":toggle-preview"'), ',')])
  endif
  call fvf#options#_merge_opts(options, preview)
  return options
endfunction

function! fvf#options#_remove_layout(opts) abort
  for key in s:layout_keys
    if has_key(a:opts, key)
      call remove(a:opts, key)
    endif
  endfor
  return a:opts
endfunction

function! fvf#options#_wrap(name, opts, bang) abort
  " fzf#wrap does not append --expect if sink or sink* is found
  let opts = copy(a:opts)
  let options = ''
  if has_key(opts, 'options')
    let options = type(opts.options) == s:TYPE.list ? join(opts.options) : opts.options
  endif
  if options !~ '--expect' && has_key(opts, 'sink*')
    let Sink = remove(opts, 'sink*')
    let wrapped = fzf#wrap(a:name, opts, a:bang)
    let wrapped['sink*'] = Sink
  else
    let wrapped = fzf#wrap(a:name, opts, a:bang)
  endif
  return wrapped
endfunction

function! fvf#options#_strip(str) abort
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! fvf#options#_chomp(str) abort
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! fvf#options#_escape(path) abort
  let path = fnameescape(a:path)
  return s:is_win ? escape(path, '$') : path
endfunction

if v:version >= 704
  function! fvf#options#_function(name) abort
    return function(a:name)
  endfunction
else
  function! fvf#options#_function(name) abort
    " By Ingo Karkat
    return function(substitute(a:name, '^s:', matchstr(expand('<sfile>'), '<SNR>\d\+_\zefunction$'), ''))
  endfunction
endif

function! fvf#options#_get_color(attr, ...) abort
  let gui = has('termguicolors') && &termguicolors
  let fam = gui ? 'gui' : 'cterm'
  let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
  for group in a:000
    let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
    if code =~? pat
      return code
    endif
  endfor
  return ''
endfunction

let s:ansi = {'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36}

function! fvf#options#_csi(color, fg) abort
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] == '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! fvf#options#_ansi(str, group, default, ...) abort
  let fg = fvf#options#_get_color('fg', a:group)
  let bg = fvf#options#_get_color('bg', a:group)
  let color = (empty(fg) ? fvf#options#_ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.fvf#options#_csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
  execute "function! fvf#options#_".s:color_name."(str, ...)\n" abort
        \ "  return fvf#options#_ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
        \ "endfunction"
endfor

function! fvf#options#_buflisted() abort
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") != "qf"')
endfunction

function! fvf#options#_fzf(name, opts, extra) abort
  let [extra, bang] = [{}, 0]
  if len(a:extra) <= 1
    let first = get(a:extra, 0, 0)
    if type(first) == s:TYPE.dict
      let extra = first
    else
      let bang = first
    endif
  elseif len(a:extra) == 2
    let [extra, bang] = a:extra
  else
    throw 'invalid number of arguments'
  endif

  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  call fvf#options#_merge_opts(merged, eopts)
  return fzf#run(fvf#options#_wrap(a:name, merged, bang))
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! fvf#options#_action_for(key, ...) abort
  let default = a:0 ? a:1 : ''
  let Cmd = get(get(g:, 'fzf_action', s:default_action), a:key, default)
  return type(Cmd) == s:TYPE.string ? Cmd : default
endfunction

function! fvf#options#_open(cmd, target) abort
  if stridx('edit', a:cmd) == 0 && fnamemodify(a:target, ':p') ==# expand('%:p')
    return
  endif
  execute a:cmd fvf#options#_escape(a:target)
endfunction

function! fvf#options#_align_lists(lists) abort
  let maxes = {}
  for list in a:lists
    let i = 0
    while i < len(list)
      let maxes[i] = max([get(maxes, i, 0), len(list[i])])
      let i += 1
    endwhile
  endfor
  for list in a:lists
    call map(list, "printf('%-'.maxes[v:key].'s', v:val)")
  endfor
  return a:lists
endfunction

function! fvf#options#_warn(message) abort
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function! fvf#options#_fill_quickfix(list, ...) abort
  if len(a:list) > 1
    call setqflist(a:list)
    copen
    wincmd p
    if a:0
      execute a:1
    endif
  endif
endfunction

function! fzf#vim#_uniq(list) abort
  let visited = {}
  let ret = []
  for l in a:list
    if !empty(l) && !has_key(visited, l)
      call add(ret, l)
      let visited[l] = 1
    endif
  endfor
  return ret
endfunction

