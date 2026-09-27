export CONDA_AUTO_ACTIVATE_BASE=false
if [[ -z "${MAMBA_ROOT_PREFIX:-}" ]]; then
  _dev_setup_mamba=$(whence -p mamba 2>/dev/null)
  _dev_setup_candidate="${_dev_setup_mamba:h:h}"
  for _dev_setup_prefix in "$HOME/miniforge3" "$HOME/mambaforge" /opt/homebrew/Caskroom/miniforge/base "$_dev_setup_candidate"; do
    if [[ -x "$_dev_setup_prefix/bin/mamba" ]]; then
      export MAMBA_ROOT_PREFIX="$_dev_setup_prefix"
      break
    fi
  done
  unset _dev_setup_prefix _dev_setup_mamba _dev_setup_candidate
fi
if [[ -x "$MAMBA_ROOT_PREFIX/bin/conda" ]]; then
  eval "$("$MAMBA_ROOT_PREFIX/bin/conda" shell.zsh hook)"
fi
if [[ -x "$MAMBA_ROOT_PREFIX/bin/mamba" ]]; then
  export MAMBA_EXE="$MAMBA_ROOT_PREFIX/bin/mamba"
  eval "$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX")"
fi
