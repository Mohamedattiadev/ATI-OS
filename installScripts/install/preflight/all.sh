# install/preflight/all.sh — sources every preflight/NN-*.sh in order.
# Numbered so `ls` shows execution/definition order at a glance, matching
# Omarchy's install/<phase>/all.sh convention.
for _f in "$(dirname "${BASH_SOURCE[0]}")"/[0-9][0-9]-*.sh; do
  source "$_f"
done
unset _f
