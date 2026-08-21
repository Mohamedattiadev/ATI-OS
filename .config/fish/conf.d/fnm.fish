
# fnm
set FNM_PATH "$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; and command -v fnm >/dev/null
  set PATH "$FNM_PATH" $PATH
  fnm env --shell fish | source
end
