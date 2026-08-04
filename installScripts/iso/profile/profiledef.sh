#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# ATI-OS — archiso profile.
#
# Forked from /usr/share/archiso/configs/releng. Kept deliberately close to
# it: every line that differs from upstream is a line that has to be
# re-reconciled each time archiso changes, so the diff is branding, the
# local package repository, and the installer -- nothing else.

iso_name="ati-os"

# The volume label is what a file manager shows when the stick is plugged
# in, so it is the most visible piece of branding in the whole build. It
# must stay within ISO-9660's limits: uppercase A-Z, 0-9 and underscore,
# 32 characters or fewer. "ATI_OS_202608" fits with room to spare.
#
# SOURCE_DATE_EPOCH is honoured for the same reason upstream honours it:
# it is what makes a rebuild from the same inputs produce the same image.
iso_label="ATI_OS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ATI-OS <https://github.com/Mohamedattiadev/Newdotfile->"
iso_application="ATI-OS Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"

# install_dir stays "arch", NOT "ati-os". It names the directory on the ISO
# holding the kernel and squashfs, and it is substituted into the boot
# entries as %INSTALL_DIR%. Renaming it is cosmetic, invisible to the user,
# and silently breaks any boot path that was written by hand rather than
# templated. It also must be 8 characters or fewer.
install_dir="arch"

buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"

# Upstream's xz settings, unchanged. zstd would build faster, but this ISO
# carries roughly 2 GB of prebuilt AUR packages on top of the usual live
# environment, and xz is worth the extra build minutes to keep the image
# inside what a small USB stick can hold.
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  # The installer. 0755 and root-owned: it partitions disks, so it must not
  # be writable by anything the live session runs as.
  ["/usr/local/bin/ati-os-install"]="0:0:755"
  # The welcome menu. Root-owned and 0755 for the same reason: it is the
  # thing that launches the installer.
  ["/usr/local/bin/ati-os-welcome"]="0:0:755"
)
