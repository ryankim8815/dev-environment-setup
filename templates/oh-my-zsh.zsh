if [[ -f "${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh" ]] && [[ -z "${ZSH_VERSION_LOADED_BY_DEV_SETUP:-}" ]]; then
  export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
  # Respect an Oh My Zsh configuration loaded earlier in the user's file.
  if (( ! $+functions[omz] )); then
    ZSH_THEME="${ZSH_THEME-robbyrussell}"
    (( ${#plugins[@]} )) || plugins=(git)
    zstyle ':omz:update' mode disabled
    source "$ZSH/oh-my-zsh.sh"
  fi
  ZSH_VERSION_LOADED_BY_DEV_SETUP=1
fi
