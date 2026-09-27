if [[ -d "${KREW_ROOT:-$HOME/.krew}/bin" ]]; then
  typeset -U path
  path=("${KREW_ROOT:-$HOME/.krew}/bin" $path)
fi
