if [[ -d "$HOME/.local/bin" ]]; then
  typeset -U path
  path=("$HOME/.local/bin" $path)
fi
