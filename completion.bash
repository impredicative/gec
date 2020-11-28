_gec_completion()
{
  if [ $COMP_CWORD -eq 1 ]; then
    COMPREPLY=($(compgen -W "$(gec _list_commands)" "${COMP_WORDS[1]}"))
  elif [ $COMP_CWORD -eq 2 ]; then
    COMPREPLY=($(compgen -W "$(gec _list_repos)" "${COMP_WORDS[2]}"))
  fi
}

complete -F _gec_completion gec

# References:
# https://iridakos.com/programming/2018/03/01/bash-programmable-completion-tutorial
# https://www.gnu.org/software/bash/manual/bash.html#Programmable-Completion
# https://serverfault.com/questions/506612/
# https://askubuntu.com/questions/68175/
# https://stackoverflow.com/questions/39624071/
