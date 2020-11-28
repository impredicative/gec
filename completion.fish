function __gec_needs_commands
  return ([ (count (commandline -opc)) -eq 1 ])
end

function __gec_needs_repos
  return ([ (count (commandline -opc)) -eq 2 ])
end

function __gec_needs_nothing
  return ([ (count (commandline -opc)) -ge 3 ])
end

complete -f -c gec -n "__gec_needs_commands" -a "(gec _list_commands)"
complete -f -c gec -n "__gec_needs_repos" -a "(gec _list_repos)"
complete -f -c gec -n "__gec_needs_nothing"

# References:
# https://fishshell.com/docs/current/index.html#writing-your-own-completions
# https://stackoverflow.com/questions/16657803/
# https://stackoverflow.com/questions/20838284/
