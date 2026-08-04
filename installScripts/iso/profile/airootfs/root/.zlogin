# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# The welcome menu, but only for a HUMAN sitting at the machine.
#
# Guarded on `script=` because that is how archiso drives an unattended
# boot -- test-iso.sh uses it -- and an interactive menu there would block
# forever on a `read` that nobody is going to answer. Guarded on tty1 so it
# does not appear on a serial console or a second VT, and on the shell
# being interactive so it never runs under automation.
if [[ -o interactive ]] \
   && [[ "$(tty)" == /dev/tty1 ]] \
   && ! grep -qa 'script=' /proc/cmdline; then
    ati-os-welcome
fi
