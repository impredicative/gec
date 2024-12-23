#compdef gec

_gec_completion() {
  case $CURRENT in
    2)
      _values 'command' $(gec _list_commands)
      ;;
    3)
      _values 'repo' $(gec _list_repos)
      ;;
    *)
      ;;
  esac
}

compdef _gec_completion gec
