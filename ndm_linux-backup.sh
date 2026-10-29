#!/usr/bin/env bash
# ---------------------------------------------------------------- APP INFO ----
# Edit these lines to rename the tool or publish a new release.
APP_NAME="NDM Linux Backup"
APP_DESCRIPTION="System backup and disaster recovery for Debian/GNU Linux: saves the \
parts of a machine most backup tools leave out (hardware, boot, partitions, LUKS, LVM, \
packages, databases, containers)."
APP_AUTHOR="Nicola Davide Mannarelli (@nidamanx)"
APP_VERSION="3.0.1"
APP_RELEASE_DATE="2026-10-29"
APP_COPYRIGHT="Copyright (C) 2020-2026 Nicola Davide Mannarelli (@nidamanx)"
APP_LICENSE="AGPL-3.0-or-later"
# ------------------------------------------------------------------------------
#
# Copyright (C) 2020-2026  Nicola Davide Mannarelli (@nidamanx)
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# The full license text is in the LICENSE file distributed with this script.
#
# DISCLAIMER
# This software is provided "as is", without warranty of any kind, express or
# implied. In no event shall the author be liable for any claim, damages or other
# liability, including loss of data, backups that are incomplete or cannot be
# restored, and systems that no longer boot after a restore, arising from the use
# or misuse of this software. You alone are responsible for how you use it, for
# keeping and protecting the archives it creates, and for checking that they can
# be restored.
# ------------------------------------------------------------------------------

# HELP-BEGIN
# Usage:   sudo ./ndm_linux-backup.sh --start [-n] [-q [-k]] [--secrets]   back up
#          sudo ./ndm_linux-backup.sh --analyze [--secrets]    show what a run would
#                                                              back up, then exit
#          ./ndm_linux-backup.sh --requirements                show the needed tools
#
#          Saves the parts of a Debian/GNU Linux machine needed to rebuild or diagnose
#          it (hardware, boot, partitions, LUKS, LVM, packages, modified /etc files,
#          crontabs, database schemas, containers, chosen directories) into a settings
#          archive; optionally a data archive and a secrets archive. Needs root.
#
# Options: -s, --start           run the backup
#          -a, --analyze         report what a run would back up, skip or fail with the
#                                current settings, then exit: nothing is written and no
#                                backup command runs; wins over --start
#          -n, --dry-run         with --start: run every step reading for real, but
#                                write nothing anywhere
#          -q, --quiet           with --start: ask nothing and show no progress (for
#                                cron); the log file is still complete
#          -k, --keep            with --quiet: keep the working directory afterwards
#              --secrets         also make the secrets archive for this run, even if
#                                v_enable_secrets_backup=false (never turns it off)
#
#              --requirements    show the needed tools and how to install them (no root)
#          -u, --usage           show a short usage line
#          -v, --version         show name, version, author, license and disclaimer
#          -h, --help            show this help
#
# Settings: in the CONFIGURE section below, or in ndm_linux-backup.conf next to this
#   script (start from ndm_linux-backup.conf.example), which wins over the script. The
#   file is only read, never executed: one KEY=value per line, lists as
#   KEY=( "a" "b" ), no $variables or $(commands). Every setting is described in the
#   CONFIGURE section and in the README.
#
# Output:  in v_dest (default: backup/ next to this script, its real location):
#            <name>_<host>_<YYYYMMDD>-<HHMMSS>.tar.xz[.gpg]      settings archive
#            <name>_DATA_<host>_<YYYYMMDD>-<HHMMSS>.tar.xz[.gpg] data archive (opt-in)
#            <name>_SECRETS_<host>_<YYYYMMDD>-<HHMMSS>.tar.xz[.gpg] secrets (opt-in)
#            <archive>.sha256 next to each archive, <name>_<host>_<...>.log per run
#          <name> is v_backup_name (default ndm_linux-backup), <host> the hostname.
#
# Examples:
#          sudo ./ndm_linux-backup.sh --analyze
#          sudo ./ndm_linux-backup.sh --start --dry-run
#          sudo ./ndm_linux-backup.sh --start
#          sudo ./ndm_linux-backup.sh --start --quiet          (cron)
#          sudo ./ndm_linux-backup.sh --start --secrets
#
# Needs:   Debian GNU/Linux (tested on Debian 13), bash, root privileges, and the
#          tools of the backup modules switched on (always tar, fdisk, sha256sum).
#          Missing ones are listed at every run, with an offer to install them;
#          --requirements shows them without root.
#
# Exit codes:
#   0    backup completed; also --analyze, --requirements, --help, --usage,
#        --version, no arguments, and a prompt answered No or Cancel
#   1    an error: not root, missing required tool, missing database credentials or
#        GPG key, unsafe working directory, failed archive or encryption step
#   2    invalid command-line usage (unknown option, unexpected argument) or an
#        invalid setting in ndm_linux-backup.conf
#   130  interrupted (Ctrl-C); 143 terminated (SIGTERM): collected files are kept
# HELP-END

# No -e: backup steps are best-effort, a missing optional tool must not
# abort the whole run (see K_SOFT_COMMANDS). pipefail backstops any pipe
# that skips the f_check_pipe convention used elsewhere.
set -uo pipefail
readonly APP_NAME APP_DESCRIPTION APP_AUTHOR APP_VERSION APP_RELEASE_DATE APP_COPYRIGHT APP_LICENSE


##################################################################
# START EDITING BELOW THIS LINE                                  #
##################################################################

# Prefer not to edit this file in place? Every setting below can instead
# be overridden from ndm_linux-backup.conf, next to this script: copy
# ndm_linux-backup.conf.example to get started, or create it by hand with
# just the lines you want to change, e.g.:
#   v_enable_mysql=true
#   v_enable_secrets_backup=true
#   v_retention_days=30
# The file is only read, never executed (see f_load_config further down).
# Keeps a future script update from clobbering your per-machine settings.


########################
# CONFIGURE
########################

# Everything below is a plain variable/array declaration, safe to edit --
# except the "EXTERNAL SETTINGS FILE" and "DERIVED DEFAULTS" blocks
# near the end of this section: those are code, leave them alone.

# Hostname to use as backup name suffix. ${HOSTNAME} is bash's own builtin
# (set via gethostname() at shell startup, not an external command), so no
# subprocess is spawned just to read it.
# Example: v_hostname="${HOSTNAME}"
# Example: v_hostname="my-custom-name"
v_hostname="${HOSTNAME}"

# Username used to store the backup
# Example: v_username="${SUDO_USER:-$(logname 2>/dev/null || id -un)}"
v_username="${SUDO_USER:-$(logname 2>/dev/null || id -un)}"

# Backup name
# Example: v_backup_name='ndm_linux-backup'
v_backup_name='ndm_linux-backup'

# Where to backup. Defaults next to the script itself, so a normal run
# never writes outside of it and v_tempdir (see Safety in README).
# Example: v_dest="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/backup"
# Example: v_dest="/home/${v_username}/backup"
v_dest="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/backup"

# Working directory to save files before tar. Not /tmp: a predictable path
# under a world-writable directory is a symlink-attack target (see
# f_secure_dir). Defaults under /home/ndm_linux-backup rather than /root since it
# needs room for the uncompressed data-pass staging tree. Must also stay
# outside every a_source_extra default entry (/root, /etc, the script's own
# dir): nesting it there would either duplicate its content in the archive
# or, if excluded, drop it from its own direct tar inclusion too.
# Example: v_tempdir="/home/ndm_linux-backup/${v_backup_name}"
# Example: v_tempdir="/root/${v_backup_name}_tmp"
# Example: v_tempdir="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/${v_backup_name}_tmp"
# Example: v_tempdir="/tmp/${v_backup_name}"
# Left empty here on purpose: its real default (derived from v_backup_name)
# is computed in "DERIVED DEFAULTS" below, after ndm_linux-backup.conf is read --
# so overriding v_backup_name without also setting v_tempdir still produces
# the right path instead of silently keeping the pre-override default.
v_tempdir=""

# List of storages. Set to ( "auto" ) to auto-detect every physical disk
# on the system instead of listing them by hand.
# Example: a_storage=( "auto" )
# Example: a_storage=( "sda" "sdb" )
a_storage=( "auto" )

# List of encrypted LUKS partitions. Set to ( "auto" ) to auto-detect every
# LUKS partition on the system instead of listing them by hand.
# Example: a_luks=( "auto" )
# Example: a_luks=( "sda3" "sdb3" )
a_luks=( "auto" )

# ===== SETTINGS MODULES =====
# Enable/disable individual backup steps for the settings archive. Set
# any to false to skip that step entirely: it is not attempted, and
# nothing related is read.
# Example: v_enable_hardware=false
v_enable_hardware=true        # lshw hardware list
v_enable_devices=true         # lspci + lsusb device lists
v_enable_lsblk=true           # lsblk block device list
v_enable_blkid=true           # blkid device IDs
v_enable_inxi=true            # inxi full system report
v_enable_efi=true             # EFI boot entries + /boot/efi (UEFI systems only)
v_enable_mbr=true             # raw MBR sector dump (BIOS/MBR disks only)
v_enable_luks=false           # LUKS header/UUID dump (only if a_luks is non-empty)
v_enable_lvm=false            # LVM pv/vg/lv display + lvmdump
v_enable_os_release=true      # lsb_release output
v_enable_kernel=true          # uname output
v_enable_partitions=true      # fdisk/sfdisk + fstab
v_enable_grub=true            # /boot/grub + /etc/default/grub
v_enable_packages=true        # dpkg/apt-mark installed package lists
v_enable_flatpak=false        # flatpak installed app list
v_enable_appimages=false      # AppImage files found on the system (size + path list, not copied)
v_enable_modified_files=true  # files whose content differs from what their package shipped (dpkg -V), copied as-is
v_enable_unpackaged_files=true # /etc files owned by no package at all (dpkg -S blind spot), copied as-is
v_enable_cron=true            # root's crontab
v_enable_mysql=false          # MySQL/MariaDB: schema always here; actual row data too if v_enable_data_backup=true
v_enable_postgresql=false     # PostgreSQL: schema always here; actual row data too if v_enable_data_backup=true
v_enable_docker=false         # Docker images/containers/volumes/networks info
v_enable_docker_compose=false # Compose files found on the system: Docker Compose / podman-compose (copied as-is)
v_enable_podman=false         # Podman images/containers/volumes/networks info + config/Quadlet files
v_enable_source_extra=true    # a_source_extra (extra directories, see further down)

# ===== DATA MODULES (require v_enable_data_backup=true below) =====
# Enable a second, separate pass and archive for actual data (not just
# setup/metadata): MySQL/PostgreSQL row data, real Docker/Podman volume
# contents, and any directories in a_data_source_extra. Default false:
# this script is meant to complement your existing data backup solution,
# not replace it. Volume copies are read via Mountpoint (docker/podman
# volume inspect, "local" driver only); a volume actively written by a
# running container can end up copied inconsistently -- for database
# volumes prefer the MySQL/PostgreSQL data dumps instead.
# Example: v_enable_data_backup=false
v_enable_data_backup=false          # master switch for the whole data pass/archive
v_enable_docker_volumes_data=false  # actual content of Docker volumes (not just the list)
v_enable_podman_volumes_data=false  # actual content of Podman volumes (not just the list)
v_enable_data_source_extra=false    # a_data_source_extra (extra directories, see further down)

# ===== SECRETS MODULE (separate archive, opt-in) =====
# A third, separate pass and archive for sensitive credential/key
# material (SSH host keys, TLS private keys, /etc/shadow, network and
# cloud credentials, this script's own .my.cnf/.pgpass -- see
# a_secrets_source). The settings and data archives never include this
# material regardless of this switch. Off by default; protect the
# resulting archive at least as well as /root and /etc themselves.
# Example: v_enable_secrets_backup=false
v_enable_secrets_backup=false       # master switch for the whole secrets pass/archive

# Not a settings/data archive step: applies after both are built.
# v_dest_rsync is empty by default, so this switch alone does nothing
# until a real destination is set below (see f_module_enabled).
# Example: v_enable_rsync=false
v_enable_rsync=false          # rsync v_dest to v_dest_rsync once the backup is done

# Not backup steps either: run your own command before/after everything
# else. Off by default even once v_pre_command/v_post_command below are
# set, so a hook can be prepared without immediately going live.
# Example: v_enable_pre_command=true
v_enable_pre_command=false     # run v_pre_command before the backup starts
v_enable_post_command=false    # run v_post_command after the backup ends
v_enable_on_failure_command=false  # run v_on_failure_command if the run fails (see below)

# Change settings/data archive ownership to current user after creation
# (they hold no secret material by default, so there's no reason to make
# them root-only). Does NOT cover the secrets archive -- see
# v_tar_owner_secrets below, deliberately separate.
# Example: v_tar_owner=false
# Example: v_tar_owner=true
v_tar_owner=true

# Same, for the secrets archive specifically -- deliberately does NOT
# mirror v_tar_owner above (unlike v_enable_gpg_data/_secrets): defaults
# to false regardless of the switch above, so turning on the convenience
# default for settings/data never also hands the secrets archive
# (/etc/shadow, SSH host keys...) to a non-root user without a separate,
# deliberate choice to do so.
# Example: v_tar_owner_secrets=true
v_tar_owner_secrets=false

# Pre and post command (enabled via v_enable_pre_command/v_enable_post_command above)
# Optionally add here your own command (e.g. stop/start services, send a
# notification...). ${NDM_HOSTNAME}/${NDM_ARCHIVE_PREFIX}/${NDM_LOG_PATH}/
# ${NDM_USER} are exported for both to use. v_post_command additionally
# gets ${NDM_EXIT_CODE} (always 0: a failed run never reaches
# v_post_command, see v_on_failure_command instead) and, for each archive
# actually produced, its path and size: ${NDM_SETTINGS_ARCHIVE}/
# ${NDM_SETTINGS_ARCHIVE_SIZE}, ${NDM_DATA_ARCHIVE}/${NDM_DATA_ARCHIVE_SIZE},
# ${NDM_SECRETS_ARCHIVE}/${NDM_SECRETS_ARCHIVE_SIZE} -- empty for a pass
# that did not run this session.
# Single quotes below on purpose: these variables are set later, when the
# command actually runs, not when this line is read. In
# ndm_linux-backup.conf the value is kept as written, quotes or not.
# An unreserved ntfy.sh topic is public: anyone who knows or guesses its
# name can read it. Pick a long, random topic name, or self-host.
# Example: v_pre_command='curl -fsS -H "Title: NDM Linux Backup" -d "$(date "+%F %T") - Starting backup ${NDM_USER}@${NDM_HOSTNAME}" https://ntfy.sh/REPLACE_WITH_YOUR_OWN_RANDOM_TOPIC'
# Example: v_post_command='curl -fsS -H "Title: NDM Linux Backup" -d "$(date "+%F %T") - Backup done ${NDM_USER}@${NDM_HOSTNAME}: settings ${NDM_SETTINGS_ARCHIVE_SIZE}${NDM_DATA_ARCHIVE:+, data ${NDM_DATA_ARCHIVE_SIZE}}${NDM_SECRETS_ARCHIVE:+, secrets ${NDM_SECRETS_ARCHIVE_SIZE}}" https://ntfy.sh/REPLACE_WITH_YOUR_OWN_RANDOM_TOPIC'
v_pre_command=""
v_post_command=""

# Run your own command if the backup run fails (enabled via
# v_enable_on_failure_command above) -- e.g. send an email, hit a webhook,
# page someone. Fires via a single EXIT trap set at the top of main(), so
# it covers every hard-exit from that point on, plus Ctrl-C (exit 130) and
# SIGTERM (exit 143). Does NOT cover failures before main() starts (invalid
# setting in ndm_linux-backup.conf, invalid CLI flag): those are setup-time problems, not
# what this hook is for. ${NDM_EXIT_CODE}, ${NDM_LOG_PATH}, ${NDM_ARCHIVE_PREFIX},
# ${NDM_HOSTNAME}, ${NDM_USER} are exported for it to use.
# Single quotes below on purpose, same reasoning as v_pre_command/
# v_post_command above.
# Example: v_on_failure_command='curl -fsS -d "NDM Linux Backup failed on ${NDM_USER}@${NDM_HOSTNAME} (exit ${NDM_EXIT_CODE})" https://example.invalid/notify'
v_on_failure_command=""

# Optionally, rsync between $dest and a local or remote directory
# (enabled via v_enable_rsync above)
# Example: v_dest_rsync="/mnt/device/backup"
v_dest_rsync=""

# Retention: delete old archives (settings/data/secrets counted
# separately) once there are more than v_retention_min_keep of that type
# AND the one being considered is older than v_retention_days.
# v_retention_min_keep is a floor, not a target: always keeps at least
# that many of the newest regardless of age, so a machine left off for a
# while never wakes up to zero backups. Off by default. Runs right after
# each archive is created, before rsync (so --delete mirrors the pruned
# state), matching only this script's own filename pattern -- see
# f_prune_old_archives.
# Example: v_retention_days=30
# Example: v_retention_min_keep=3
v_retention_days=0
v_retention_min_keep=1

# Encrypt each archive with GPG right after it's created, deleting the
# plaintext once the encrypted copy exists. Off by default.
# v_enable_gpg_data/_secrets default to this same switch but can be
# overridden independently -- e.g. set only v_enable_gpg_secrets=true to
# encrypt just the secrets archive. A missing recipient file hard-exits
# before any backup work starts (see f_check_gpg_keys(), README
# "Encryption"); a failed encryption also hard-exits, never leaving a
# plaintext archive behind when encryption was requested.
# Example: v_enable_gpg_settings=true
v_enable_gpg_settings=false
# Left empty here on purpose: default is this same switch, computed in
# "DERIVED DEFAULTS" below (after ndm_linux-backup.conf is read) so it picks up
# an override of v_enable_gpg_settings above.
v_enable_gpg_data=""
v_enable_gpg_secrets=""

# Points to an ASCII-armored public key file, used directly via
# --recipient-file: no keyring import, no trust-model prompts. The
# matching private key is only ever needed on the restore machine, never
# on this one. v_gpg_recipient_file_data/_secrets default to the same key
# but can be overridden independently, e.g. different keys per archive.
# Example: v_gpg_recipient_file="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/pubkey.asc"
v_gpg_recipient_file="${HOME}/pubkey.asc"
# Left empty here on purpose, same reasoning as v_enable_gpg_data/_secrets
# above: default computed in "DERIVED DEFAULTS" below.
v_gpg_recipient_file_data=""
v_gpg_recipient_file_secrets=""

# Optionally, add extra sources to include in the settings archive
# (enabled via v_enable_source_extra above). /opt, /srv, /usr/local/etc
# are typical config/data locations for third-party software;
# /var/spool/cron/crontabs holds non-root crontabs (root's own is
# covered by v_enable_cron); the script's own directory captures how
# this deployment is set up. No per-user home directory here besides
# /root: that needs a case-by-case decision, and blanket-including
# ~/.ssh private keys is a bad idea.
# Example: a_source_extra=( "/root" "/etc" "/usr/local/bin" )
a_source_extra=( "/root" "/etc" "/usr/local/bin" "/opt" "/srv" "/usr/local/etc" \
  "/var/spool/cron/crontabs" "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" )

# Extra directories to search for AppImages, in addition to the built-in
# defaults (/home, /root, /opt, /usr/local/bin)
# Example: a_appimages_extra_paths=( "/srv/apps" "/mnt/data/AppImages" )
a_appimages_extra_paths=( )

# Extra directories to search for Compose files (Docker Compose /
# podman-compose, same file naming convention), in addition to the
# built-in defaults (/home, /root, /opt, /srv). There is no fixed
# convention for where compose files live, so add your own project
# directories here if they are outside the defaults.
# Example: a_docker_compose_extra_paths=( "/data/stacks" "/mnt/nas/docker" )
a_docker_compose_extra_paths=( )

# Language for datetime suffix
# Example (no locale): export LC_TIME=C
# Example (locale German): export LC_TIME="de_DE.UTF-8"
# Example (locale UK English): export LC_TIME="en_GB.UTF-8"
# Example (locale Spanish): export LC_TIME="es_ES.UTF-8"
# Example (locale French): export LC_TIME="fr_FR.UTF-8"
# Example (locale Italian): export LC_TIME="it_IT.UTF-8"
export LC_TIME=C

# Date and time at the end of the archive names: a date(1) format, local
# time (default YYYYMMDD-HHMMSS). Only letters, digits, ".", "_" and "-"
# may come out of it.
# Example default: v_datetime_format='%Y%m%d-%H%M%S'
# Example ISO with separators: v_datetime_format='%Y-%m-%d_%H-%M-%S'
# Example WeekDay only (one archive per weekday, overwritten weekly): v_datetime_format='%A'
# Example WeekDay + date: v_datetime_format='%w-%a_%Y%m%d-%H%M%S'
v_datetime_format='%Y%m%d-%H%M%S'

# MySQL/MariaDB
# Backup all in one single file
# Example: v_mysql_single_dump=false
v_mysql_single_dump=false
# Get user and pass from .my.cnf file. Defaults to the same path the mysql/
# mysqldump client tools themselves read automatically -- see
# f_check_db_credentials() for what happens if it is missing.
# Example: v_mysql_cnf_path="${HOME}/.my.cnf"
# Example: v_mysql_cnf_path="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.my.cnf"
# Example: v_mysql_cnf_path="your_custom_path/.my.cnf"
v_mysql_cnf_path="${HOME}/.my.cnf"

# PostgreSQL
# Backup all in one single file
# Example: v_postgresql_single_dump=false
v_postgresql_single_dump=false
# User to connect as (password is looked up from .pgpass by host/port/database/user)
# Example: v_postgresql_user="postgres"
v_postgresql_user="postgres"
# Get password from .pgpass file (format: hostname:port:database:username:password)
# Must be chmod 600 or PostgreSQL client tools silently refuse to read it.
# If missing, NDM Linux Backup also tries local peer/ident auth over the Unix
# socket before giving up (see README "PostgreSQL backup") -- if that
# works, .pgpass is never required at all. See f_check_db_credentials().
# Example: v_postgresql_pgpass_path="${HOME}/.pgpass"
# Example: v_postgresql_pgpass_path="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.pgpass"
v_postgresql_pgpass_path="${HOME}/.pgpass"

# Podman
# Podman is normally used rootless, per-user: running it as root only
# shows root's own state, not another user's containers/images. Set to
# the user whose rootless Podman instance to inspect (defaults to
# v_username above); set to "root" to use root's own Podman instead. A
# non-root user needs `loginctl enable-linger <user>` (one-time, as root)
# so their runtime directory exists without an active login session.
# Example: v_podman_user="${v_username}"
# Example: v_podman_user="root"
# Left empty here on purpose: default (mirroring v_username) is computed
# in "DERIVED DEFAULTS" below, after ndm_linux-backup.conf is read.
v_podman_user=""

# Secrets (enabled via v_enable_secrets_backup above)
# Raw LUKS header backup (cryptsetup luksHeaderBackup), in addition to
# the human-readable luksDump/luksUUID text already in the settings
# archive: this one can restore a corrupted header byte-for-byte, since
# it contains the real keyslots. Off by default even with secrets on:
# unlike everything else in a_secrets_source, having this backup defeats
# crypto-shredding (destroying only the on-disk header to make a LUKS
# volume permanently unrecoverable) for anyone who gets hold of it -- turn
# it on only if you want header-corruption recovery and accept that
# trade-off. Only ever written into the secrets archive.
# Example: v_enable_luks_header_backup=false
v_enable_luks_header_backup=false   # raw cryptsetup luksHeaderBackup per a_luks entry (secrets archive only)

# Built-in paths always swept into the secrets archive when the module
# is on. Includes this script's own MySQL/PostgreSQL credential files:
# unlike the settings and data archives, which always exclude them, this
# is where they belong. A missing path is skipped with a notice, not an
# error -- not every machine has all of these. Override this array
# entirely in ndm_linux-backup.conf to trim or extend it.
# Example: a_secrets_source=( "/etc/shadow" "/root/.ssh" )
a_secrets_source=(
  "/etc/shadow" "/etc/gshadow" "/etc/shadow-" "/etc/gshadow-"
  "/etc/ssh/ssh_host_rsa_key" "/etc/ssh/ssh_host_ecdsa_key" "/etc/ssh/ssh_host_ed25519_key"
  "/etc/ssl/private"
  "/etc/letsencrypt/live" "/etc/letsencrypt/archive"
  "/etc/mysql/debian.cnf"
  "/etc/NetworkManager/system-connections"
  "/etc/wpa_supplicant"
  "/etc/wireguard"
  "/etc/exim4/passwd.client" "/etc/postfix/sasl_passwd" "/etc/postfix/sasl_passwd.db"
  "/etc/ppp/chap-secrets" "/etc/ppp/pap-secrets"
  "/root/.ssh"
  "/root/.docker/config.json"
  "/root/.aws" "/root/.config/gcloud" "/root/.kube" "/root/.azure"
  "/root/.netrc"
  "/root/.gnupg"
  "/root/.bash_history"
  "${v_mysql_cnf_path}" "${v_postgresql_pgpass_path}"
)

# Extra paths to sweep into the secrets archive, in addition to
# a_secrets_source above.
# Example: a_secrets_source_extra=( "/etc/openvpn/client/secret.key" )
a_secrets_source_extra=( )

# Where the secrets archive is written and its own working directory.
# Default next to the settings ones.
# Example: v_dest_secrets="${v_dest}"
# Example: v_tempdir_secrets="${v_tempdir}_secrets"
# Left empty here on purpose: default (mirroring v_dest/v_tempdir) is
# computed in "DERIVED DEFAULTS" below, after ndm_linux-backup.conf is read.
v_dest_secrets=""
v_tempdir_secrets=""

# Extra directories with real data to include in the data archive (e.g.
# personal documents, media, self-hosted app data not in a container).
# Enabled via v_enable_data_source_extra above.
# Example: a_data_source_extra=( "/home/user/Documents" "/srv/nextcloud/data" )
a_data_source_extra=( )

# Where the data archive is written and its own working directory.
# Default next to the settings ones.
# Example: v_dest_data="${v_dest}"
# Example: v_tempdir_data="${v_tempdir}_data"
# Left empty here on purpose: default (mirroring v_dest/v_tempdir) is
# computed in "DERIVED DEFAULTS" below, after ndm_linux-backup.conf is read.
v_dest_data=""
v_tempdir_data=""

# ===== EXTERNAL SETTINGS FILE (code, leave it alone) =====
# ndm_linux-backup.conf next to this script (its real location), optional.
# Read as KEY=value lines, never executed: this script runs as root, so the
# file must not be able to run anything. Only the settings above are
# accepted; values are literal (no $variables, no $(commands)), each one is
# checked against its type, and lists are written as KEY=( "a" "b" ),
# possibly over several lines. The environment is not read: sudo resets it
# anyway, and a stray exported variable must never change what is backed up.
# A problem is reported (exit 2) only once the command line has been read,
# so --help and --version still work with a broken file.
v_config_path="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ndm_linux-backup.conf"
v_config_error=""

# Type of every setting the file may change. bool: true/false; int: whole
# number; name: letters, digits, "." "_" "-"; path: absolute path; text: any
# literal value not starting with "-"; cmd: a command run later by the hooks (only these may
# contain "$"); format: a date(1) format; devs/paths: lists of device names
# or absolute paths. A setting whose built-in default is empty may be empty.
declare -A K_CONFIG_KEYS=(
  [v_hostname]=name [v_username]=name [v_backup_name]=name
  [v_dest]=path [v_tempdir]=path
  [v_dest_data]=path [v_tempdir_data]=path
  [v_dest_secrets]=path [v_tempdir_secrets]=path
  [a_storage]=devs [a_luks]=devs
  [v_enable_hardware]=bool [v_enable_devices]=bool [v_enable_lsblk]=bool
  [v_enable_blkid]=bool [v_enable_inxi]=bool [v_enable_efi]=bool [v_enable_mbr]=bool
  [v_enable_luks]=bool [v_enable_lvm]=bool [v_enable_os_release]=bool
  [v_enable_kernel]=bool [v_enable_partitions]=bool [v_enable_grub]=bool
  [v_enable_packages]=bool [v_enable_flatpak]=bool [v_enable_appimages]=bool
  [v_enable_modified_files]=bool [v_enable_unpackaged_files]=bool [v_enable_cron]=bool
  [v_enable_mysql]=bool [v_enable_postgresql]=bool [v_enable_docker]=bool
  [v_enable_docker_compose]=bool [v_enable_podman]=bool [v_enable_source_extra]=bool
  [v_enable_data_backup]=bool [v_enable_docker_volumes_data]=bool
  [v_enable_podman_volumes_data]=bool [v_enable_data_source_extra]=bool
  [v_enable_secrets_backup]=bool [v_enable_luks_header_backup]=bool
  [v_enable_rsync]=bool [v_enable_pre_command]=bool [v_enable_post_command]=bool
  [v_enable_on_failure_command]=bool
  [v_tar_owner]=bool [v_tar_owner_secrets]=bool
  [v_pre_command]=cmd [v_post_command]=cmd [v_on_failure_command]=cmd
  [v_dest_rsync]=text
  [v_retention_days]=int [v_retention_min_keep]=int
  [v_enable_gpg_settings]=bool [v_enable_gpg_data]=bool [v_enable_gpg_secrets]=bool
  [v_gpg_recipient_file]=path [v_gpg_recipient_file_data]=path
  [v_gpg_recipient_file_secrets]=path
  [a_source_extra]=paths [a_appimages_extra_paths]=paths
  [a_docker_compose_extra_paths]=paths
  [v_datetime_format]=format
  [v_mysql_single_dump]=bool [v_mysql_cnf_path]=path
  [v_postgresql_single_dump]=bool [v_postgresql_user]=name [v_postgresql_pgpass_path]=path
  [v_podman_user]=name
  [a_secrets_source]=paths [a_secrets_source_extra]=paths [a_data_source_extra]=paths
)
readonly K_CONFIG_KEYS

# Split ${1} into words like the shell would, without expanding anything:
# "..." (with \" \\ \$ \` escapes), '...', \x, and # comments to the end of
# the line. One unquoted "(" before the first word and one ")" after the
# last mark a list. Result in a_config_words and v_config_list (none, open,
# closed). Returns 1 on a syntax error (unclosed quote, misplaced paren).
function f_config_words() {
  local v_text="${1}" v_char v_quote="" v_word="" v_in_word=false i
  a_config_words=()
  v_config_list=none
  for ((i = 0; i < ${#v_text}; i++)); do
    v_char="${v_text:i:1}"
    if [[ -n "${v_quote}" ]]; then
      if [[ "${v_char}" == "${v_quote}" ]]; then
        v_quote=""
      elif [[ "${v_quote}" == '"' ]] && [[ "${v_char}" == "\\" ]] && [[ "${v_text:i+1:1}" == [\"\\\$\`] ]]; then
        v_word+="${v_text:i+1:1}"
        i=$((i + 1))
      else
        v_word+="${v_char}"
      fi
      continue
    fi
    [[ "${v_config_list}" != closed ]] || [[ "${v_char}" == [[:space:]] ]] || [[ "${v_char}" == '#' ]] \
      || return 1
    case "${v_char}" in
      [[:space:]])
        if [[ "${v_in_word}" == true ]]; then
          a_config_words+=("${v_word}")
          v_word=""
          v_in_word=false
        fi
        ;;
      '#')
        if [[ "${v_in_word}" == true ]]; then
          v_word+="${v_char}"
        else
          while ((i + 1 < ${#v_text})) && [[ "${v_text:i+1:1}" != $'\n' ]]; do
            i=$((i + 1))
          done
        fi
        ;;
      '"'|"'")
        v_quote="${v_char}"
        v_in_word=true
        ;;
      "\\")
        i=$((i + 1))
        v_word+="${v_text:i:1}"
        v_in_word=true
        ;;
      '(')
        [[ "${v_config_list}" == none ]] && [[ "${v_in_word}" == false ]] \
          && ((${#a_config_words[@]} == 0)) || return 1
        v_config_list=open
        ;;
      ')')
        [[ "${v_config_list}" == open ]] || return 1
        if [[ "${v_in_word}" == true ]]; then
          a_config_words+=("${v_word}")
          v_word=""
          v_in_word=false
        fi
        v_config_list=closed
        ;;
      *)
        v_word+="${v_char}"
        v_in_word=true
        ;;
    esac
  done
  [[ -z "${v_quote}" ]] || return 1
  if [[ "${v_in_word}" == true ]]; then
    a_config_words+=("${v_word}")
  fi
  return 0
}

# Check value(s) ${3}... of setting ${1} (type ${2}); print the reason if invalid.
function f_config_check() {
  local v_key="${1}" v_type="${2}" v_value v_out
  shift 2
  for v_value in "${@}"; do
    if [[ "${v_type}" != cmd ]] && [[ "${v_value}" == *[\$\`]* ]]; then
      printf '%s: "$" and "`" are not expanded here, write the value itself' "${v_key}"
      return 1
    fi
    if [[ -z "${v_value}" ]]; then
      case "${v_type}" in
        devs|paths) printf '%s: empty item in the list' "${v_key}"; return 1 ;;
        cmd|text) ;;
        *)
          [[ -z "${!v_key}" ]] || { printf '%s: empty value' "${v_key}"; return 1; }
          ;;
      esac
      continue
    fi
    case "${v_type}" in
      bool)
        [[ "${v_value}" =~ ^(true|false)$ ]] \
          || { printf '%s=%s (true or false)' "${v_key}" "${v_value}"; return 1; }
        ;;
      int)
        # No leading zero: bash would read "08" as a wrong octal number
        [[ "${v_value}" =~ ^(0|[1-9][0-9]{0,5})$ ]] \
          || { printf '%s=%s (a whole number, 0 or more)' "${v_key}" "${v_value}"; return 1; }
        ;;
      name)
        [[ "${v_value}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] \
          || { printf '%s=%s (only letters, digits, ".", "_" and "-", not first)' "${v_key}" "${v_value}"; return 1; }
        ;;
      text)
        # Passed to other commands as an argument: never as one of their options
        [[ "${v_value}" != -* ]] \
          || { printf '%s=%s (must not start with "-")' "${v_key}" "${v_value}"; return 1; }
        ;;
      path|paths)
        if [[ "${v_value}" != /* ]] || [[ "${v_value}" == *$'\n'* ]]; then
          printf '%s: %s is not an absolute path' "${v_key}" "${v_value}"
          return 1
        fi
        ;;
      devs)
        # A name under /dev, such as sda or nvme0n1p3: it also becomes part of
        # file names in the working directory, so no "/" and no leading "."
        [[ "${v_value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
          || { printf '%s: %s is not a device name (e.g. sda, nvme0n1p3)' "${v_key}" "${v_value}"; return 1; }
        ;;
      format)
        v_out="$(LC_TIME=C date "+${v_value}" 2>/dev/null)"
        [[ "${v_out}" =~ ^[A-Za-z0-9._-]+$ ]] \
          || { printf '%s=%s (a date format giving only letters, digits, ".", "_" and "-")' "${v_key}" "${v_value}"; return 1; }
        ;;
    esac
  done
}

function f_load_config() {
  local v_line v_key v_raw v_type v_more v_lineno=0 v_first v_why
  [[ -e "${v_config_path}" ]] || return 0
  if [[ ! -f "${v_config_path}" ]] || [[ ! -r "${v_config_path}" ]]; then
    v_config_error="not a readable file"
    return
  fi
  while IFS= read -r v_line || [[ -n "${v_line}" ]]; do
    v_lineno=$((v_lineno + 1))
    v_line="${v_line%$'\r'}"
    [[ "${v_line}" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if ! [[ "${v_line}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      v_config_error="line ${v_lineno}: not a KEY=value line"
      return
    fi
    v_key="${BASH_REMATCH[1]}"
    v_raw="${BASH_REMATCH[2]}"
    v_type="${K_CONFIG_KEYS[${v_key}]:-}"
    if [[ -z "${v_type}" ]]; then
      if [[ "${v_key}" == v_datetime_suffix ]]; then
        v_config_error="line ${v_lineno}: v_datetime_suffix is now v_datetime_format, a date format such as '%Y%m%d-%H%M%S'"
      else
        v_config_error="line ${v_lineno}: unknown setting ${v_key}"
      fi
      return
    fi
    v_first="${v_lineno}"
    while true; do
      if ! f_config_words "${v_raw}"; then
        v_config_error="line ${v_first}: ${v_key}: unclosed quote or misplaced parenthesis"
        return
      fi
      [[ "${v_config_list}" == open ]] || break
      if ! IFS= read -r v_more; then
        v_config_error="line ${v_first}: ${v_key}: the list is not closed with \")\""
        return
      fi
      v_lineno=$((v_lineno + 1))
      v_raw+=$'\n'"${v_more%$'\r'}"
    done
    case "${v_type}" in
      devs|paths)
        if [[ "${v_config_list}" != closed ]]; then
          v_config_error="line ${v_first}: ${v_key} is a list, write it as ${v_key}=( \"...\" \"...\" )"
          return
        fi
        if ! v_why="$(f_config_check "${v_key}" "${v_type}" "${a_config_words[@]}")"; then
          v_config_error="line ${v_first}: ${v_why}"
          return
        fi
        local -n v_list_ref="${v_key}"
        # shellcheck disable=SC2034 # nameref: assigns the list named by v_key
        v_list_ref=("${a_config_words[@]}")
        unset -n v_list_ref
        ;;
      *)
        if [[ "${v_config_list}" != none ]] || ((${#a_config_words[@]} > 1)); then
          v_config_error="line ${v_first}: ${v_key} takes one value (quote it if it contains spaces)"
          return
        fi
        if ! v_why="$(f_config_check "${v_key}" "${v_type}" "${a_config_words[0]:-}")"; then
          v_config_error="line ${v_first}: ${v_why}"
          return
        fi
        printf -v "${v_key}" '%s' "${a_config_words[0]:-}"
        ;;
    esac
  done < "${v_config_path}"
}
f_load_config

# ===== DERIVED DEFAULTS =====
# Each variable below defaults to another CONFIGURE variable's value (see
# that variable's own comment further up). Computed here, after
# ndm_linux-backup.conf is read, so overriding the "parent" via
# ndm_linux-backup.conf is correctly picked up: computing these earlier would
# freeze the child at the built-in default even when the parent got
# overridden. ":-" still honors an explicit override of the child itself.
v_tempdir="${v_tempdir:-/home/ndm_linux-backup/${v_backup_name}}"
v_enable_gpg_data="${v_enable_gpg_data:-${v_enable_gpg_settings}}"
v_enable_gpg_secrets="${v_enable_gpg_secrets:-${v_enable_gpg_settings}}"
v_gpg_recipient_file_data="${v_gpg_recipient_file_data:-${v_gpg_recipient_file}}"
v_gpg_recipient_file_secrets="${v_gpg_recipient_file_secrets:-${v_gpg_recipient_file}}"
v_podman_user="${v_podman_user:-${v_username}}"
v_dest_secrets="${v_dest_secrets:-${v_dest}}"
v_tempdir_secrets="${v_tempdir_secrets:-${v_tempdir}_secrets}"
v_dest_data="${v_dest_data:-${v_dest}}"
v_tempdir_data="${v_tempdir_data:-${v_tempdir}_data}"
v_datetime_suffix="$(date "+${v_datetime_format}")"

##################################################################
# DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING #
##################################################################


# Resolve a_storage=( "auto" ) into the actual list of physical disks
# (lsblk TYPE=disk, which already excludes partitions/loop/rom devices),
# so the rest of the script only ever deals with concrete device names.
if [[ "${#a_storage[@]}" -eq 1 ]] && [[ "${a_storage[0]}" == 'auto' ]]; then
  if command -v lsblk >/dev/null 2>&1; then
    mapfile -t a_storage < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}')
  else
    printf "\na_storage is set to \"auto\" but lsblk is not installed; cannot detect disks.\n\n" >&2
    exit 1
  fi
fi

# Resolve a_luks=( "auto" ) into the actual list of LUKS partitions
# (lsblk FSTYPE=crypto_LUKS), so the rest of the script only ever deals
# with concrete device names.
if [[ "${#a_luks[@]}" -eq 1 ]] && [[ "${a_luks[0]}" == 'auto' ]]; then
  if command -v lsblk >/dev/null 2>&1; then
    mapfile -t a_luks < <(lsblk -rno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1}')
  else
    printf "\na_luks is set to \"auto\" but lsblk is not installed; cannot detect LUKS partitions.\n\n" >&2
    exit 1
  fi
fi

# Set vars and arrays as readonly to be safe
readonly v_hostname
readonly v_username
readonly v_backup_name
readonly v_dest
readonly v_tempdir
readonly a_storage
readonly a_luks
readonly v_enable_hardware
readonly v_enable_devices
readonly v_enable_lsblk
readonly v_enable_blkid
readonly v_enable_inxi
readonly v_enable_efi
readonly v_enable_mbr
readonly v_enable_luks
readonly v_enable_lvm
readonly v_enable_os_release
readonly v_enable_kernel
readonly v_enable_partitions
readonly v_enable_grub
readonly v_enable_packages
readonly v_enable_flatpak
readonly v_enable_appimages
readonly v_enable_modified_files
readonly v_enable_unpackaged_files
readonly v_enable_cron
readonly v_enable_mysql
readonly v_enable_postgresql
readonly v_enable_docker
readonly v_enable_docker_compose
readonly v_enable_podman
readonly v_tar_owner
readonly v_tar_owner_secrets
readonly v_pre_command
readonly v_post_command
readonly v_on_failure_command
readonly v_dest_rsync
readonly v_retention_days
readonly v_retention_min_keep
readonly v_enable_gpg_settings
readonly v_enable_gpg_data
readonly v_enable_gpg_secrets
readonly v_gpg_recipient_file
readonly v_gpg_recipient_file_data
readonly v_gpg_recipient_file_secrets
readonly v_enable_source_extra
# shellcheck disable=SC2034 # passed by name to f_filter_existing_sources's `local -n`, not referenced directly
readonly a_source_extra
readonly a_appimages_extra_paths
readonly a_docker_compose_extra_paths
readonly v_datetime_format
readonly v_datetime_suffix
readonly v_mysql_single_dump
readonly v_mysql_cnf_path
readonly v_postgresql_single_dump
readonly v_postgresql_user
readonly v_postgresql_pgpass_path
readonly v_podman_user
readonly v_enable_data_backup
readonly v_enable_docker_volumes_data
readonly v_enable_podman_volumes_data
readonly v_enable_data_source_extra
readonly v_enable_secrets_backup
readonly v_enable_luks_header_backup
readonly a_secrets_source
readonly a_secrets_source_extra
readonly v_dest_secrets
readonly v_tempdir_secrets
readonly v_enable_rsync
readonly v_enable_pre_command
readonly v_enable_post_command
readonly v_enable_on_failure_command
# shellcheck disable=SC2034 # passed by name to f_filter_existing_sources's `local -n`, not referenced directly
readonly a_data_source_extra
readonly v_dest_data
readonly v_tempdir_data
readonly v_config_path
readonly v_config_error

# Every directory this script may write into or delete from outside
# a_source_extra/a_secrets_source. Checked by f_assert_within_whitelist().
readonly a_write_whitelist=( "${v_dest}" "${v_dest_data}" "${v_dest_secrets}" "${v_tempdir}" "${v_tempdir_data}" "${v_tempdir_secrets}" )


# For debug purpose
readonly K_DEBUG=false

# Terminal colors for the dependency report (OK/MISSING/OPTIONAL). Left
# empty when stdout isn't a terminal or NO_COLOR is set (see
# https://no-color.org), so redirected output and log files stay free of
# escape sequences.
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  readonly K_COLOR_GREEN=$'\033[32m'
  readonly K_COLOR_RED=$'\033[31m'
  readonly K_COLOR_YELLOW=$'\033[33m'
  readonly K_COLOR_RESET=$'\033[0m'
else
  readonly K_COLOR_GREEN=''
  readonly K_COLOR_RED=''
  readonly K_COLOR_YELLOW=''
  readonly K_COLOR_RESET=''
fi

# Every external command the script relies on, mapped to the Debian
# package that provides it. Used by f_check_dependencies() to report
# what is missing and, if approved, install it via apt.
declare -A K_PACKAGE_FOR_COMMAND=(
  ["fdisk"]="fdisk"
  ["sfdisk"]="fdisk"
  ["lshw"]="lshw"
  ["lsblk"]="util-linux"
  ["blkid"]="util-linux"
  ["inxi"]="inxi"
  ["lspci"]="pciutils"
  ["lsusb"]="usbutils"
  ["efibootmgr"]="efibootmgr"
  ["dd"]="coreutils"
  ["cryptsetup"]="cryptsetup"
  ["lvmdump"]="lvm2"
  ["pvdisplay"]="lvm2"
  ["vgdisplay"]="lvm2"
  ["lvdisplay"]="lvm2"
  ["lsb_release"]="lsb-release"
  ["uname"]="coreutils"
  ["tar"]="tar"
  ["dpkg"]="dpkg"
  ["apt-mark"]="apt"
  ["crontab"]="cron"
  ["chown"]="coreutils"
  ["sha256sum"]="coreutils"
  ["gpg"]="gnupg"
  ["mysql"]="default-mysql-client"
  ["mysqldump"]="default-mysql-client"
  ["rsync"]="rsync"
  ["flatpak"]="flatpak"
  ["psql"]="postgresql-client"
  ["pg_dump"]="postgresql-client"
  ["pg_dumpall"]="postgresql-client"
  ["docker"]="docker.io"
  ["podman"]="podman"
  ["sudo"]="sudo"
)
readonly K_PACKAGE_FOR_COMMAND
readonly K_ALL_COMMANDS=( "${!K_PACKAGE_FOR_COMMAND[@]}" )

# Which backup-module switch (v_enable_*) each command belongs to. Lets
# f_check_dependencies() tell "needed by your enabled modules" apart from
# "everything the script could ever use". v_enable_grub has no entry: it
# only uses f_copy, no external command to track.
declare -A K_COMMANDS_FOR_MODULE=(
  ["v_enable_hardware"]="lshw"
  ["v_enable_devices"]="lspci lsusb"
  ["v_enable_lsblk"]="lsblk"
  ["v_enable_blkid"]="blkid"
  ["v_enable_inxi"]="inxi"
  ["v_enable_efi"]="efibootmgr"
  ["v_enable_mbr"]="dd"
  ["v_enable_luks"]="cryptsetup"
  ["v_enable_lvm"]="lvmdump pvdisplay vgdisplay lvdisplay"
  ["v_enable_os_release"]="lsb_release"
  ["v_enable_kernel"]="uname"
  ["v_enable_partitions"]="sfdisk"
  ["v_enable_packages"]="dpkg apt-mark"
  ["v_enable_flatpak"]="flatpak"
  ["v_enable_modified_files"]="dpkg"
  ["v_enable_cron"]="crontab"
  ["v_enable_mysql"]="mysql mysqldump"
  ["v_enable_postgresql"]="psql pg_dump pg_dumpall"
  ["v_enable_docker"]="docker"
  # sudo is NOT listed here even though f_podman may use it: it's only
  # needed when v_podman_user != root, so f_commands_for_enabled_modules()
  # adds it conditionally instead -- keeps sudo-less servers from being
  # flagged for it when v_podman_user=root.
  ["v_enable_podman"]="podman"
  ["v_enable_docker_volumes_data"]="docker"
  ["v_enable_podman_volumes_data"]="podman"
  ["v_enable_rsync"]="rsync"
  ["v_enable_luks_header_backup"]="cryptsetup"
)
readonly K_COMMANDS_FOR_MODULE

# Commands needed no matter which backup modules are enabled: fdisk
# classifies every configured disk as GPT/MBR, tar builds the final
# archive, sha256sum writes its checksum sidecar. chown/gpg are NOT here
# (not always needed, see v_tar_owner/v_enable_gpg_* in
# f_commands_for_enabled_modules() instead).
readonly K_ALWAYS_NEEDED_COMMANDS=( "fdisk" "tar" "sha256sum" )

# Patterns (grep -E, matched against the full path from `find /etc -type
# f`) excluded by default from v_enable_unpackaged_files: auto-generated
# state (adjtime...), tool/editor backup copies (the `-`/`~` suffixed
# variants, .pwd.lock...), compiled caches (ld.so.cache), and
# PAM/resolvconf fragments meant to be edited through their own tooling,
# not by hand -- none of these is something an admin plausibly
# customized directly, so they'd just be noise every run. fstab is
# excluded only because it already has a dedicated, unconditional
# capture elsewhere (partitions/fstab.txt, see v_enable_partitions), not
# because it's noise -- unlike fstab, crypttab is deliberately NOT
# excluded here even though it also has a dedicated capture
# (luks/crypttab.txt): that one only runs if v_enable_luks=true and
# a_luks is non-empty, so leaving crypttab unfiltered here is the
# fallback that keeps it from silently missing entirely when that
# switch is off; the tiny duplication when both do run is immaterial.
# Anchored to each file's exact canonical path rather than a bare
# filename: an unanchored pattern would also match a genuinely
# unpackaged custom file sharing that basename elsewhere under /etc.
# Also excludes private key material under /etc (SSH host keys, TLS
# certs, Let's Encrypt...): that lives in the opt-in secrets archive
# instead (see a_secrets_source). Deliberately does NOT exclude files an
# admin plausibly edited by hand (motd, hosts, network/interfaces,
# environment, nsswitch.conf, locale.gen, hostname, machine-id): those
# are meant to actually surface here.
readonly a_unpackaged_files_ignore_regex=(
  '^/etc/adjtime$'
  '^/etc/fstab$'
  '^/etc/passwd-?$' '^/etc/group-?$' '^/etc/shadow-?$' '^/etc/gshadow-?$'
  '^/etc/subuid-?$' '^/etc/subgid-?$'
  '^/etc/networks$' '^/etc/shells$' '^/etc/modules$'
  '^/etc/inputrc$'
  '^/etc/kernel-img\.conf$' '^/etc/ld\.so\.cache$' '^/etc/locale\.conf$'
  '^/etc/security/opasswd$' '^/etc/\.pwd\.lock$' '^/etc/\.updated$'
  '^/etc/apt/sources\.list~$' '^/etc/default/keyboard$' '^/etc/default/console-setup$'
  '^/etc/console-setup/cached_' '^/etc/pam\.d/common-' '^/etc/resolvconf/resolv\.conf\.d/'
  '^/etc/ssh/ssh_host_(rsa|ecdsa|ed25519)_key$' '^/etc/ssl/private/'
  '^/etc/letsencrypt/(live|archive)/' '^/etc/mysql/debian\.cnf$'
  '^/etc/NetworkManager/system-connections/' '^/etc/wpa_supplicant/' '^/etc/wireguard/'
  '^/etc/exim4/passwd\.client$' '^/etc/postfix/sasl_passwd' '^/etc/ppp/(chap|pap)-secrets$'
)

# Commands whose own backup step already skips itself gracefully via a
# `command -v` guard when missing (Flatpak, MySQL, PostgreSQL, Docker,
# Podman in main()), or whose module is conditional on real hardware
# presence via f_module_enabled() (EFI, LUKS, LVM). Excluded from the
# fail-fast pre-flight check even when enabled; still reported/offered by
# f_check_dependencies whenever the module applies to this machine.
readonly K_SOFT_COMMANDS=(
  "lvmdump" "pvdisplay" "vgdisplay" "lvdisplay" "mysql" "mysqldump" "flatpak"
  "psql" "pg_dump" "pg_dumpall" "docker" "podman" "efibootmgr"
)

# Every backup-module switch, in the same order as CONFIGURE. Used by
# f_check_dependencies() to report which modules are enabled/disabled.
# Some entries have no K_COMMANDS_FOR_MODULE counterpart because they use
# only f_copy/find (grub, appimages, docker_compose, source_extra) or are
# just outer gates (data_backup, secrets_backup, see f_module_enabled()).
readonly K_ALL_MODULES=(
  "v_enable_hardware" "v_enable_devices" "v_enable_lsblk" "v_enable_blkid" "v_enable_inxi"
  "v_enable_efi" "v_enable_mbr" "v_enable_luks" "v_enable_lvm" "v_enable_os_release"
  "v_enable_kernel" "v_enable_partitions" "v_enable_grub" "v_enable_packages" "v_enable_flatpak"
  "v_enable_appimages" "v_enable_modified_files" "v_enable_unpackaged_files" "v_enable_cron" "v_enable_mysql" "v_enable_postgresql"
  "v_enable_docker" "v_enable_docker_compose" "v_enable_podman" "v_enable_source_extra"
  "v_enable_data_backup" "v_enable_docker_volumes_data" "v_enable_podman_volumes_data"
  "v_enable_data_source_extra" "v_enable_secrets_backup" "v_enable_luks_header_backup" \
    "v_enable_rsync" "v_enable_pre_command" "v_enable_post_command" "v_enable_on_failure_command"
)

# The same modules as K_ALL_MODULES, split by which archive they belong
# to, for f_analyze_report()'s per-archive grouping. K_OTHER_MODULES is
# cross-cutting (not archive-specific). Every K_ALL_MODULES entry appears
# in exactly one of these four -- kept in sync by hand, same as
# K_ALL_MODULES itself.
readonly K_SETTINGS_MODULES=(
  "v_enable_hardware" "v_enable_devices" "v_enable_lsblk" "v_enable_blkid" "v_enable_inxi"
  "v_enable_efi" "v_enable_mbr" "v_enable_luks" "v_enable_lvm" "v_enable_os_release"
  "v_enable_kernel" "v_enable_partitions" "v_enable_grub" "v_enable_packages" "v_enable_flatpak"
  "v_enable_appimages" "v_enable_modified_files" "v_enable_unpackaged_files" "v_enable_cron" "v_enable_mysql" "v_enable_postgresql"
  "v_enable_docker" "v_enable_docker_compose" "v_enable_podman" "v_enable_source_extra"
)
readonly K_DATA_MODULES=(
  "v_enable_data_backup" "v_enable_docker_volumes_data" "v_enable_podman_volumes_data" "v_enable_data_source_extra"
)
readonly K_SECRETS_MODULES=( "v_enable_secrets_backup" "v_enable_luks_header_backup" )
readonly K_OTHER_MODULES=( "v_enable_rsync" "v_enable_pre_command" "v_enable_post_command" "v_enable_on_failure_command" )

########################
# FUNCTIONS
########################


# Name, version, release date, description and author (used by --version and --help).
function f_version() {
  printf '%s %s (released %s)\n' "${APP_NAME}" "${APP_VERSION}" "${APP_RELEASE_DATE}"
  printf '%s\n' "${APP_DESCRIPTION}" | fold -s -w 88 | sed 's/ *$//'
  printf 'Author: %s\n' "${APP_AUTHOR}"
  echo
  printf '%s\n' "${APP_COPYRIGHT}"
  printf 'License %s: GNU AGPL version 3 or later <https://www.gnu.org/licenses/agpl-3.0.html>\n' \
    "${APP_LICENSE}"
  echo 'This is free software: you are free to change and redistribute it.'
  echo 'Provided "as is", WITHOUT ANY WARRANTY: the author is not liable for any damage'
  echo 'arising from its use. See the LICENSE file and the header of this script.'
}

function f_usage() {
  printf 'Usage: sudo %s --start [-n] [-q [-k]] [--secrets] | --analyze [--secrets]\n' "${0##*/}"
  printf '       %s --requirements | -h | -u | -v\n' "${0##*/}"
}

function f_help() {
  f_version
  echo
  # The help text is the comment block between the HELP-BEGIN and HELP-END markers.
  awk '/^# HELP-BEGIN/ {f = 1; next} /^# HELP-END/ {exit} f {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"
}

# Invalid command-line usage: message on stderr, exit code 2
function f_bad_usage() {
  printf '%s (see --help)\n' "${1}" >&2
  exit 2
}

# --requirements: the tools of the modules switched on in the settings (script and
# ndm_linux-backup.conf), which are missing, and the apt-get command to install them.
# Needs no root: the hardware-dependent checks (UEFI, MBR, LUKS) are left to
# --analyze, so a module switched on counts here even if this machine lacks it.
function f_requirements() {
  local -a a_needed=() a_missing=() a_other_missing=()
  local -A a_is_needed=() a_pkg_seen=()
  local v_module v_cmd v_pkg
  local -a a_missing_pkgs=() a_other_pkgs=()
  # Run without root, the sbin directories are often not in PATH: root's are
  local PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin"

  for v_cmd in "${K_ALWAYS_NEEDED_COMMANDS[@]}"; do
    a_is_needed["${v_cmd}"]=1
  done
  for v_module in "${!K_COMMANDS_FOR_MODULE[@]}"; do
    [[ "${!v_module}" == true ]] || continue
    case "${v_module}" in
      v_enable_docker_volumes_data|v_enable_podman_volumes_data)
        [[ "${v_enable_data_backup}" == true ]] || continue ;;
      v_enable_luks_header_backup)
        [[ "${v_enable_secrets_backup}" == true ]] || continue ;;
    esac
    for v_cmd in ${K_COMMANDS_FOR_MODULE[${v_module}]}; do
      a_is_needed["${v_cmd}"]=1
    done
  done
  if [[ "${v_enable_gpg_settings}" == true ]] || [[ "${v_enable_gpg_data}" == true ]] \
    || [[ "${v_enable_gpg_secrets}" == true ]]; then
    a_is_needed["gpg"]=1
  fi
  mapfile -t a_needed < <(printf '%s\n' "${!a_is_needed[@]}" | sort)

  local -A a_is_soft=()
  local -a a_soft_missing=()
  for v_cmd in "${K_SOFT_COMMANDS[@]}"; do
    a_is_soft["${v_cmd}"]=1
  done
  for v_cmd in "${a_needed[@]}"; do
    command -v "${v_cmd}" >/dev/null 2>&1 && continue
    if [[ -n "${a_is_soft[${v_cmd}]:-}" ]]; then
      a_soft_missing+=("${v_cmd}")
    else
      a_missing+=("${v_cmd}")
    fi
    v_pkg="${K_PACKAGE_FOR_COMMAND[${v_cmd}]}"
    [[ -n "${a_pkg_seen[${v_pkg}]:-}" ]] || { a_pkg_seen["${v_pkg}"]=1; a_missing_pkgs+=("${v_pkg}"); }
  done
  while IFS= read -r v_cmd; do
    [[ -n "${a_is_needed[${v_cmd}]:-}" ]] && continue
    command -v "${v_cmd}" >/dev/null 2>&1 && continue
    a_other_missing+=("${v_cmd}")
    v_pkg="${K_PACKAGE_FOR_COMMAND[${v_cmd}]}"
    [[ -n "${a_pkg_seen[${v_pkg}]:-}" ]] || { a_pkg_seen["${v_pkg}"]=1; a_other_pkgs+=("${v_pkg}"); }
  done < <(printf '%s\n' "${K_ALL_COMMANDS[@]}" | sort)

  echo "Requirements"
  echo "  system:   Debian GNU/Linux (tested on Debian 13), bash, root privileges"
  printf '  needed:   %s\n' "${a_needed[*]}" | fold -s -w 88 | sed -e 's/ *$//' -e '2,$s/^/            /'
  echo "            (always tar, fdisk, sha256sum; the rest for the modules switched on)"
  echo
  if ((${#a_missing[@]} + ${#a_soft_missing[@]} == 0)); then
    echo "Everything needed by your settings is installed."
  else
    ((${#a_missing[@]} == 0)) || printf '  MISSING:  %s\n' "${a_missing[*]}"
    ((${#a_soft_missing[@]} == 0)) \
      || printf '  missing, optional (only their own piece is skipped): %s\n' "${a_soft_missing[*]}"
    echo
    echo "Install them (Debian):"
    printf '  sudo apt-get install %s\n' "${a_missing_pkgs[*]}"
  fi
  if ((${#a_other_missing[@]})); then
    echo
    printf 'Not installed, used only by modules switched off: %s\n' "${a_other_missing[*]}" \
      | fold -s -w 88 | sed 's/ *$//'
    printf '  (packages: %s)\n' "${a_other_pkgs[*]}" | fold -s -w 88 | sed 's/ *$//'
  fi
}

# Hard-exit if command ${1} is not installed.
function f_check_command() {
  command -v "${1}" >/dev/null 2>&1 || {
    printf "\nCommand '%s' is required but not installed.\n\n" "${1}" >&2
    exit 1
  }
}

# Whether a v_enable_* module actually runs. Normally just its own switch;
# a few modules also need a runtime precondition true (real hardware
# present, a companion path/command set) since the switch alone doesn't
# guarantee that -- see each case arm below. Keeps the dependency report
# and the enabled/disabled modules list reflecting what will actually run,
# not just which switches are on. MySQL/PostgreSQL are not special-cased:
# their schema dump always runs on their own switch alone (see main());
# only the row-data dump checks v_enable_data_backup, inline there.
function f_module_enabled() {
  local v_module="${1}"
  case "${v_module}" in
    v_enable_docker_volumes_data|v_enable_podman_volumes_data|v_enable_data_source_extra)
      [[ "${v_enable_data_backup}" == true ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_efi)
      [[ "${v_uefi_bios}" == 'uefi' ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_mbr)
      [[ "${#a_mbr[@]}" != 0 ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_luks)
      [[ "${#a_luks[@]}" != 0 ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_luks_header_backup)
      [[ "${#a_luks[@]}" != 0 ]] && [[ "${v_secrets_active}" == true ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_lvm)
      [[ "${v_lvm_present}" == true ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_rsync)
      [[ -n "${v_dest_rsync}" ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_secrets_backup)
      # OR, not AND: --secrets (v_secrets_override, set in f_parse_arguments)
      # forces this on for the run even if CONFIGURE left it false; it
      # never turns it off if CONFIGURE already set it true.
      [[ "${!v_module}" == true ]] || [[ "${v_secrets_override}" == true ]]
      ;;
    v_enable_pre_command)
      [[ -n "${v_pre_command}" ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_post_command)
      [[ -n "${v_post_command}" ]] && [[ "${!v_module}" == true ]]
      ;;
    v_enable_on_failure_command)
      [[ -n "${v_on_failure_command}" ]] && [[ "${!v_module}" == true ]]
      ;;
    *)
      [[ "${!v_module}" == true ]]
      ;;
  esac
}

# All commands used by the currently enabled backup modules (v_enable_*),
# plus the always-needed core commands, one per line, sorted. Includes
# commands whose step can gracefully skip itself when missing (see
# K_SOFT_COMMANDS) - from the user's point of view they are still needed
# to actually get that module's data.
function f_commands_for_enabled_modules() {
  local -A a_seen=()
  local v_module v_cmd
  for v_cmd in "${K_ALWAYS_NEEDED_COMMANDS[@]}"; do
    a_seen["${v_cmd}"]=1
  done
  for v_module in "${!K_COMMANDS_FOR_MODULE[@]}"; do
    if f_module_enabled "${v_module}"; then
      for v_cmd in ${K_COMMANDS_FOR_MODULE[${v_module}]}; do
        a_seen["${v_cmd}"]=1
      done
    fi
  done
  # sudo is only needed by f_podman's own `sudo -u` user-switch, when
  # v_podman_user != root -- never to run NDM Linux Backup itself (already root).
  if [[ "${v_podman_user}" != 'root' ]] \
    && { f_module_enabled "v_enable_podman" || f_module_enabled "v_enable_podman_volumes_data"; }; then
    a_seen["sudo"]=1
  fi
  # chown: needed if v_tar_owner=true (settings/data ENDING ownership
  # change), or if v_tar_owner_secrets=true and the secrets pass actually
  # runs this session (same AND as docker_volumes_data/luks_header_backup
  # above). Not a v_enable_* module, so K_COMMANDS_FOR_MODULE can't
  # express it.
  if [[ "${v_tar_owner}" == true ]] \
    || { [[ "${v_tar_owner_secrets}" == true ]] && [[ "${v_secrets_active}" == true ]]; }; then
    a_seen["chown"]=1
  fi
  # gpg: needed if any archive that actually runs this session gets
  # encrypted -- settings always runs; data/secrets only count if that
  # pass itself runs (same AND as docker_volumes_data/luks_header_backup
  # in f_module_enabled()).
  if [[ "${v_enable_gpg_settings}" == true ]] \
    || { [[ "${v_enable_gpg_data}" == true ]] && [[ "${v_enable_data_backup}" == true ]]; } \
    || { [[ "${v_enable_gpg_secrets}" == true ]] && [[ "${v_secrets_active}" == true ]]; }; then
    a_seen["gpg"]=1
  fi
  printf '%s\n' "${!a_seen[@]}" | sort
}

# Same set as above, minus K_SOFT_COMMANDS. This is the strict set used
# for the fail-fast pre-flight check in main(): a step that already
# tolerates its own tool being missing must not be forced to hard-exit.
function f_hard_required_commands() {
  local -A a_soft=()
  local v_cmd
  for v_cmd in "${K_SOFT_COMMANDS[@]}"; do
    a_soft["${v_cmd}"]=1
  done
  while IFS= read -r v_cmd; do
    [[ -n "${a_soft[${v_cmd}]:-}" ]] && continue
    printf '%s\n' "${v_cmd}"
  done < <(f_commands_for_enabled_modules)
}

# Prints (and logs, if a log file is open) whether each archive actually
# produced this session ends up GPG-encrypted or stays plain. Shared
# between f_check_dependencies() and f_analyze_report() so both show the
# same thing. data/secrets are only reported if that pass actually runs.
function f_print_encryption_status() {
  local -a a_gpg_encrypted=() a_gpg_plain=()
  [[ "${v_enable_gpg_settings}" == true ]] && a_gpg_encrypted+=("settings") || a_gpg_plain+=("settings")
  if [[ "${v_enable_data_backup}" == true ]]; then
    [[ "${v_enable_gpg_data}" == true ]] && a_gpg_encrypted+=("data") || a_gpg_plain+=("data")
  fi
  if [[ "${v_secrets_active}" == true ]]; then
    [[ "${v_enable_gpg_secrets}" == true ]] && a_gpg_encrypted+=("secrets") || a_gpg_plain+=("secrets")
  fi
  if [[ "${#a_gpg_encrypted[@]}" -gt 0 ]]; then
    printf "\nEncryption: ENABLED for: %s -- the plaintext .tar.xz is deleted once the GPG-encrypted copy exists.\n" "${a_gpg_encrypted[*]}" >&2
    f_log_msg "Encryption: ENABLED for: ${a_gpg_encrypted[*]} -- the plaintext .tar.xz is deleted once the GPG-encrypted copy exists"
  fi
  if [[ "${#a_gpg_plain[@]}" -gt 0 ]]; then
    printf 'Encryption: disabled for: %s -- %s %s\n' "${a_gpg_plain[*]}" \
      "those archives stay plain, unencrypted .tar.xz. Set v_enable_gpg_settings/_data/_secrets=true" \
      "in CONFIGURE or ndm_linux-backup.conf to enable (see Encryption in README)." >&2
    f_log_msg "Encryption: disabled for: ${a_gpg_plain[*]} -- those archives stay plain, unencrypted .tar.xz"
  fi
}

# List every external command the script can use, report which ones are
# missing, and offer to install the corresponding packages via apt -
# either only those needed by the currently enabled backup modules
# (default), or every dependency the script could ever use. Never
# installs anything in --quiet or --dry-run mode: it only reports.
function f_check_dependencies() {
  local -a a_sorted_commands a_needed_now
  local -a a_missing_all=() a_missing_needed=()
  local -a a_missing_all_packages=() a_missing_needed_packages=()
  local -A a_seen_all_packages=() a_seen_needed_packages=() a_is_needed=()
  local i v_package

  mapfile -t a_sorted_commands < <(printf '%s\n' "${K_ALL_COMMANDS[@]}" | sort)
  mapfile -t a_needed_now < <(f_commands_for_enabled_modules)
  for i in "${a_needed_now[@]}"; do
    a_is_needed["${i}"]=1
  done

  local -a a_enabled_modules=() a_disabled_modules=()
  local v_module
  for v_module in "${K_ALL_MODULES[@]}"; do
    if f_module_enabled "${v_module}"; then
      a_enabled_modules+=("${v_module#v_enable_}")
    else
      a_disabled_modules+=("${v_module#v_enable_}")
    fi
  done
  f_print_msg "$(printf '\nEnabled backup modules: %s' "${a_enabled_modules[*]:-(none)}")"
  f_print_msg "Disabled backup modules: ${a_disabled_modules[*]:-(none)}"

  # Unconditional, unlike the missing-packages notice below: whether
  # secrets end up in this run's output is safety-critical, never to be
  # silently skipped in --quiet/cron runs.
  if [[ "${v_secrets_active}" == true ]]; then
    if [[ "${v_enable_secrets_backup}" == true ]]; then
      v_secrets_reason="v_enable_secrets_backup=true in the settings"
    else
      v_secrets_reason="the --secrets override for this run (v_enable_secrets_backup is false in the settings)"
    fi
    printf '\nSecrets backup: ENABLED (%s) -- %s %s\n' "${v_secrets_reason}" \
      "this run's secrets archive WILL contain cleartext private keys (SSH host, TLS) and password" \
      "hashes (/etc/shadow); protect it at least as well as /root and /etc/shadow themselves." >&2
    f_log_msg "Secrets backup: ENABLED (${v_secrets_reason}) --" \
      "this run's secrets archive WILL contain cleartext private keys (SSH host, TLS) and password" \
      "hashes (/etc/shadow)"
  else
    printf '\n%s %s %s\n' \
      "Secrets backup: disabled -- no SSH/TLS private keys, /etc/shadow, or other credentials will" \
      "be included in this run. Set v_enable_secrets_backup=true in CONFIGURE or ndm_linux-backup.conf," \
      "or pass --secrets for this run only, to include them." >&2
    f_log_msg "Secrets backup: disabled -- no SSH/TLS private keys, /etc/shadow, or other credentials were included in this run"
  fi

  # Unconditional for the same reason: a separate, materially different
  # risk (defeats crypto-shredding on every disk in a_luks), worth its
  # own run-time reminder.
  if f_module_enabled "v_enable_luks_header_backup"; then
    printf '\n%s %s\n' \
      "LUKS header backup: ENABLED -- this run's secrets archive WILL contain a raw, restorable copy" \
      "of every LUKS header in a_luks, which defeats crypto-shredding for anyone who also gets hold of it." >&2
    f_log_msg "LUKS header backup: ENABLED -- this run's secrets archive contains a raw, restorable copy of every LUKS header in a_luks"
  fi

  # Unconditional for the same reason: retention deletes old archives.
  if [[ "${v_retention_days}" -gt 0 ]]; then
    printf '\n%s %s\n' \
      "Retention: ENABLED -- archives older than ${v_retention_days} day(s) will be deleted" \
      "(keeping at least ${v_retention_min_keep} of each type regardless of age)." >&2
    f_log_msg "Retention: ENABLED -- archives older than ${v_retention_days} day(s) deleted" \
      "(keeping at least ${v_retention_min_keep} of each type regardless of age)"
  fi

  # Unconditional for the same reason: encryption status is safety-relevant.
  f_print_encryption_status

  # A custom recipient key without any v_enable_gpg_* switch on most likely
  # means encryption was expected (older settings turned it on by setting
  # the key path alone): say so instead of silently writing plaintext.
  # Flagged only when the path was actually customized.
  if [[ "${v_gpg_recipient_file}" != "${HOME}/pubkey.asc" ]] \
    && [[ "${v_enable_gpg_settings}" != true ]] && [[ "${v_enable_gpg_data}" != true ]] \
    && [[ "${v_enable_gpg_secrets}" != true ]]; then
    printf 'NOTICE: v_gpg_recipient_file is set to a custom path (%s) %s %s %s\n' "${v_gpg_recipient_file}" \
      "but no v_enable_gpg_settings/_data/_secrets switch is on, so nothing is actually being encrypted" \
      "-- setting the recipient-file path alone does not turn encryption on." \
      "Set the matching v_enable_gpg_* switch(es) to true." >&2
    f_log_msg "NOTICE: v_gpg_recipient_file is set to a custom path (${v_gpg_recipient_file})" \
      "but no v_enable_gpg_settings/_data/_secrets switch is on, so nothing is actually being encrypted"
  fi

  # Pad the tags to a fixed width before adding color codes: printf's
  # %-10s counts the invisible ANSI escape bytes too, so padding after
  # colorizing would throw off the column alignment.
  local v_tag_ok v_tag_missing v_tag_optional
  v_tag_ok="$(printf '%-10s' '[OK]')"
  v_tag_missing="$(printf '%-10s' '[MISSING]')"
  v_tag_optional="$(printf '%-10s' '[OPTIONAL]')"

  f_print_msg $'\nChecking required software'
  local v_installed
  for i in "${a_sorted_commands[@]}"; do
    v_package="${K_PACKAGE_FOR_COMMAND[${i}]}"
    v_installed=false
    command -v "${i}" >/dev/null 2>&1 && v_installed=true

    if [[ -z "${a_is_needed[${i}]:-}" ]]; then
      # Not needed by any enabled module: OPTIONAL regardless of whether
      # it happens to be installed, since your current config doesn't
      # care either way.
      f_print_msg "  ${K_COLOR_YELLOW}${v_tag_optional}${K_COLOR_RESET} ${i} (package: ${v_package})"
      if [[ "${v_installed}" == false ]]; then
        a_missing_all+=("${i}")
        if [[ -z "${a_seen_all_packages[${v_package}]:-}" ]]; then
          a_seen_all_packages["${v_package}"]=1
          a_missing_all_packages+=("${v_package}")
        fi
      fi
      continue
    fi

    if [[ "${v_installed}" == true ]]; then
      f_print_msg "  ${K_COLOR_GREEN}${v_tag_ok}${K_COLOR_RESET} ${i}"
    else
      f_print_msg "  ${K_COLOR_RED}${v_tag_missing}${K_COLOR_RESET} ${i} (package: ${v_package})"
      a_missing_all+=("${i}")
      a_missing_needed+=("${i}")
      if [[ -z "${a_seen_all_packages[${v_package}]:-}" ]]; then
        a_seen_all_packages["${v_package}"]=1
        a_missing_all_packages+=("${v_package}")
      fi
      if [[ -z "${a_seen_needed_packages[${v_package}]:-}" ]]; then
        a_seen_needed_packages["${v_package}"]=1
        a_missing_needed_packages+=("${v_package}")
      fi
    fi
  done

  if [[ "${#a_missing_all[@]}" == 0 ]]; then
    f_print_msg "All required software is installed."
    return
  fi

  if [[ "${v_dry_run}" == true ]] || [[ "${v_quiet}" == true ]]; then
    printf '\nMissing packages: %s %s %s\n' "${a_missing_all_packages[*]}" \
      "(dependency check skipped in --dry-run/--quiet: a normal run always asks before installing" \
      "anything, never installs on its own)" >&2
    f_log_msg "Missing packages: ${a_missing_all_packages[*]}" \
      "(dependency check skipped in --dry-run/--quiet: a normal run always asks before installing" \
      "anything, never installs on its own)"
    return
  fi

  f_check_command "apt-get"

  printf "\nAll of NDM Linux Backup's dependencies that are missing: %s\n" "${a_missing_all_packages[*]}"
  printf "Missing dependencies needed by your enabled backup modules: %s\n" "${a_missing_needed_packages[*]:-(none)}"
  printf "\nTo use NDM Linux Backup, some dependencies need to be downloaded.\n"
  printf "Do you want to install all of NDM Linux Backup's dependencies, or only the ones needed by the backup modules you selected?\n"

  local v_choice
  while true; do
    printf "\n[N]eeded only (default) / [A]ll / [M]anual / [S]kip / [C]ancel? "
    read -r v_choice
    case "${v_choice}" in
      ''|N|n )
        if [[ "${#a_missing_needed_packages[@]}" == 0 ]]; then
          printf "Nothing needed by your enabled backup modules is missing.\n"
          return
        fi
        printf "\nWill run:\n  apt-get update\n  apt-get install -y %s\n\n" "${a_missing_needed_packages[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${a_missing_needed_packages[@]}"
        return
        ;;
      A|a )
        printf "\nWill run:\n  apt-get update\n  apt-get install -y %s\n\n" "${a_missing_all_packages[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${a_missing_all_packages[@]}"
        return
        ;;
      M|m )
        if [[ "${#a_missing_needed_packages[@]}" == 0 ]]; then
          printf "Nothing needed by your enabled backup modules is missing.\n"
          return
        fi
        printf "\nTo install manually, run:\n  apt-get update\n  apt-get install -y %s\n" "${a_missing_needed_packages[*]}"
        printf "Exiting so you can install it yourself; re-run NDM Linux Backup once done.\n\n"
        exit 0
        ;;
      S|s )
        printf "\nContinuing without installing; steps needing the missing software will be skipped or fail.\n\n" >&2
        return
        ;;
      C|c )
        printf "Script aborted\n\n"
        exit 0
        ;;
      * )
        printf "Invalid answer (choose N, A, M, S or C)\n" >&2
        ;;
    esac
  done
}

# Hard requirement, checked once per enabled+applicable DB module: the
# credentials file must exist before any backup work starts. Never
# creates, copies, or edits it -- too risky to automate, only reports and
# exits (see README). Both modules are checked together in a single exit
# so a machine missing both isn't told about one, fixed, then the other.
function f_check_db_credentials() {
  local v_script_dir
  v_script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

  local -a a_missing=()

  if [[ "${v_enable_mysql}" == true ]] && [[ "$(command -v mysqldump)" ]] \
    && [[ ! -f "${v_mysql_cnf_path}" ]] && [[ "${v_mysql_socket_auth}" != true ]]; then
    a_missing+=("$(cat <<EOF
MySQL/MariaDB: credentials file not found at ${v_mysql_cnf_path}, and root@localhost socket auth is not available either
  1. Copy the template: sudo cp -n "${v_script_dir}/my.cnf.example" "${v_mysql_cnf_path}"
  2. Edit it: sudo nano "${v_mysql_cnf_path}"
     Fill in the [client] section with your real user/password
  3. Save, then fix permissions: sudo chmod 600 "${v_mysql_cnf_path}"
  Or, to avoid a password file entirely, verify root@localhost uses the unix_socket/auth_socket plugin instead --
  see README "MySQL/MariaDB backup"
EOF
)")
  fi

  if [[ "${v_enable_postgresql}" == true ]] && [[ "$(command -v pg_dump)" ]] \
    && [[ ! -f "${v_postgresql_pgpass_path}" ]] && [[ "${v_postgresql_peer_auth}" != true ]]; then
    a_missing+=("$(cat <<EOF
PostgreSQL: credentials file not found at ${v_postgresql_pgpass_path}, and local peer/ident auth is not available either
  1. Copy the template: sudo cp -n "${v_script_dir}/pgpass.example" "${v_postgresql_pgpass_path}"
  2. Edit it: sudo nano "${v_postgresql_pgpass_path}"
     Fill in hostname:port:database:username:password, e.g. localhost:5432:*:postgres:secret
  3. Save, then fix permissions: sudo chmod 600 "${v_postgresql_pgpass_path}"
  Or, to avoid a password file entirely, configure PostgreSQL peer/ident auth instead -- see README "PostgreSQL backup"
EOF
)")
  fi

  if [[ "${#a_missing[@]}" -gt 0 ]]; then
    local v_msg
    printf "\nDatabase backup enabled, but the following credentials are missing:\n" >&2
    f_log_msg "Database backup enabled, but the following credentials are missing:"
    for v_msg in "${a_missing[@]}"; do
      printf "\n%s\n" "${v_msg}" >&2
      f_log_msg "${v_msg}"
    done
    printf "\nFix the above, then re-run NDM Linux Backup.\n\n" >&2
    exit 1
  fi

  # Advisory, not a hard-exit: a group/other-readable credentials file is
  # a confidentiality problem, not blocking otherwise. PostgreSQL's own
  # tools already refuse a non-600 .pgpass; MySQL's --defaults-file has
  # no such self-protection, so this is the only thing that catches it.
  local v_cred_mode
  if [[ "${v_enable_mysql}" == true ]] && [[ "$(command -v mysqldump)" ]] && [[ -f "${v_mysql_cnf_path}" ]]; then
    v_cred_mode="$(stat -c '%a' "${v_mysql_cnf_path}")"
    if (( (10#${v_cred_mode: -2:1} & 4) != 0 )) || (( (10#${v_cred_mode: -1} & 4) != 0 )); then
      printf '\nWARNING: %s is readable by group/other (mode %s) -- %s\n' \
        "${v_mysql_cnf_path}" "${v_cred_mode}" \
        "it contains a plaintext MySQL/MariaDB password. chmod 600 it." >&2
      f_log_msg "WARNING: ${v_mysql_cnf_path} is readable by group/other (mode ${v_cred_mode}) -- it contains a plaintext MySQL/MariaDB password"
    fi
  fi
  if [[ "${v_enable_postgresql}" == true ]] && [[ "$(command -v pg_dump)" ]] && [[ -f "${v_postgresql_pgpass_path}" ]]; then
    v_cred_mode="$(stat -c '%a' "${v_postgresql_pgpass_path}")"
    if (( (10#${v_cred_mode: -2:1} & 4) != 0 )) || (( (10#${v_cred_mode: -1} & 4) != 0 )); then
      printf '\nWARNING: %s is readable by group/other (mode %s) -- %s\n' \
        "${v_postgresql_pgpass_path}" "${v_cred_mode}" \
        "it contains a plaintext PostgreSQL password. chmod 600 it." >&2
      f_log_msg "WARNING: ${v_postgresql_pgpass_path} is readable by group/other (mode ${v_cred_mode}) -- it contains a plaintext PostgreSQL password"
    fi
  fi
}

# Advisory (never blocks): warn if ${1} (a tar source directory passed
# directly to the settings/data tar command, e.g. v_tempdir) resolves
# under, or itself contains, any entry of ${3} (a source-extra array by
# name, e.g. a_source_extra). Both end up as separate source arguments on
# the same tar command line, so an overlap either duplicates that content
# in the archive or, if the overlapping entry gets excluded instead,
# drops it from ${1}'s own direct inclusion too -- see the v_tempdir
# comment in CONFIGURE. Symlinks/missing paths resolve to empty and are
# skipped: this is a hygiene check, not a security boundary (that's
# f_assert_within_whitelist).
function f_check_source_overlap() {
  local v_dir_path="${1}" v_dir_label="${2}" v_extra_label="${4}"
  local -n v_ref_extra="${3}"
  local v_real_dir v_real_extra i

  # readlink -f requires every component but the last to already exist,
  # which v_tempdir/v_tempdir_data never do this early (they're only
  # created later, by f_prepare_tempdir) -- fall back to the literal
  # configured path instead of silently skipping the check. Symlinks
  # along an as-yet-uncreated path can't be resolved anyway.
  v_real_dir="$(readlink -f "${v_dir_path}" 2>/dev/null)"
  [[ -n "${v_real_dir}" ]] || v_real_dir="${v_dir_path}"

  for i in "${v_ref_extra[@]}"; do
    v_real_extra="$(readlink -f "${i}" 2>/dev/null)"
    [[ -n "${v_real_extra}" ]] || v_real_extra="${i}"
    if [[ "${v_real_dir}" == "${v_real_extra}" ]] \
      || [[ "${v_real_dir}" == "${v_real_extra}"/* ]] \
      || [[ "${v_real_extra}" == "${v_real_dir}"/* ]]; then
      printf '\nWARNING: %s (%s) overlaps with %s entry %s -- %s %s %s\n' \
        "${v_dir_label}" "${v_real_dir}" "${v_extra_label}" "${i}" \
        "its content will be duplicated in the archive (or dropped from its own direct inclusion," \
        "if you exclude the overlap instead)." \
        "Move ${v_dir_label} outside every ${v_extra_label} path." >&2
      f_log_msg "WARNING: ${v_dir_label} (${v_real_dir}) overlaps with ${v_extra_label} entry ${i}" \
        "-- its content will be duplicated in the archive"
    fi
  done
}

# Hard requirement (unlike f_check_source_overlap above): ${1} (a v_tempdir*)
# must never equal, or sit under, ${2} (its own v_dest*). The ENDING tar step
# always excludes ${2} from ${1}'s archive (--exclude="${v_dest}") so v_dest
# does not end up inside its own archive when it falls under a_source_extra
# -- but GNU tar's --exclude also matches an ancestor directory of a path
# being archived, not just entries found while walking it. If v_tempdir sits
# at or under v_dest, that same exclude silently drops the entire tempdir
# source too: every backup step still runs and reports "Done", but the
# archive comes out empty (exit 0, "All done"). Checked once per archive
# that actually runs this session, before any backup step starts.
function f_check_dest_overlap() {
  local v_tempdir_path="${1}" v_dest_path="${2}" v_label="${3}"
  local v_real_tempdir v_real_dest

  # Same readlink -f / fallback-to-literal reasoning as f_check_source_overlap
  # above: v_tempdir does not exist yet this early in main().
  v_real_tempdir="$(readlink -f "${v_tempdir_path}" 2>/dev/null)"
  [[ -n "${v_real_tempdir}" ]] || v_real_tempdir="${v_tempdir_path}"
  v_real_dest="$(readlink -f "${v_dest_path}" 2>/dev/null)"
  [[ -n "${v_real_dest}" ]] || v_real_dest="${v_dest_path}"

  if [[ "${v_real_tempdir}" == "${v_real_dest}" ]] || [[ "${v_real_tempdir}" == "${v_real_dest}"/* ]]; then
    printf '\n%s: v_tempdir (%s) is the same as, or nested under, its own v_dest (%s). %s %s %s\n\n' \
        "${v_label}" "${v_tempdir_path}" "${v_dest_path}" \
        "The ENDING tar step excludes v_dest from the archive so it doesn't swallow itself --" \
        "since v_tempdir sits inside that excluded tree, the archive would be produced empty, silently" \
        "(exit 0, \"All done\"). Move v_tempdir outside v_dest and re-run." >&2
    f_log_msg "SECURITY: ${v_label}: v_tempdir (${v_tempdir_path}) is the same as, or nested under," \
      "its own v_dest (${v_dest_path}) -- refusing to run, the archive would come out silently empty"
    exit 1
  fi
}

# Hard requirement, checked once per enabled GPG switch: the matching
# recipient public-key file must exist before any backup work starts.
# Never generates a keypair itself -- too risky to automate -- only
# reports and exits (see README "Encryption"). v_enable_gpg_data/_secrets
# are only enforced when that pass actually runs this session.
function f_check_gpg_keys() {
  local -a a_missing=()

  if [[ "${v_enable_gpg_settings}" == true ]] && { [[ -z "${v_gpg_recipient_file}" ]] || [[ ! -f "${v_gpg_recipient_file}" ]]; }; then
    a_missing+=("$(cat <<EOF
GPG encryption (settings archive): recipient public key not found${v_gpg_recipient_file:+ at ${v_gpg_recipient_file}}
  No GPG keypair yet? Create one: gpg --full-generate-key
  Then export the public key to where NDM Linux Backup expects it:
    gpg --armor --export <key-id-or-email> > "${v_gpg_recipient_file:-${HOME}/pubkey.asc}"
  Already have a public key (e.g. from whoever will restore this backup)? Copy it there instead:
    cp /path/to/their/pubkey.asc "${v_gpg_recipient_file:-${HOME}/pubkey.asc}"
  Or point v_gpg_recipient_file at wherever it already lives.
EOF
)")
  fi

  if [[ "${v_enable_gpg_data}" == true ]] && [[ "${v_enable_data_backup}" == true ]] \
    && { [[ -z "${v_gpg_recipient_file_data}" ]] || [[ ! -f "${v_gpg_recipient_file_data}" ]]; }; then
    a_missing+=("$(cat <<EOF
GPG encryption (data archive): recipient public key not found${v_gpg_recipient_file_data:+ at ${v_gpg_recipient_file_data}}
  No GPG keypair yet? Create one: gpg --full-generate-key
  Then export the public key to where NDM Linux Backup expects it:
    gpg --armor --export <key-id-or-email> > "${v_gpg_recipient_file_data:-${HOME}/pubkey.asc}"
  Already have a public key (e.g. from whoever will restore this backup)? Copy it there instead:
    cp /path/to/their/pubkey.asc "${v_gpg_recipient_file_data:-${HOME}/pubkey.asc}"
  Or point v_gpg_recipient_file_data at wherever it already lives.
EOF
)")
  fi

  if [[ "${v_enable_gpg_secrets}" == true ]] && [[ "${v_secrets_active}" == true ]] \
    && { [[ -z "${v_gpg_recipient_file_secrets}" ]] || [[ ! -f "${v_gpg_recipient_file_secrets}" ]]; }; then
    a_missing+=("$(cat <<EOF
GPG encryption (secrets archive): recipient public key not found${v_gpg_recipient_file_secrets:+ at ${v_gpg_recipient_file_secrets}}
  No GPG keypair yet? Create one: gpg --full-generate-key
  Then export the public key to where NDM Linux Backup expects it:
    gpg --armor --export <key-id-or-email> > "${v_gpg_recipient_file_secrets:-${HOME}/pubkey.asc}"
  Already have a public key (e.g. from whoever will restore this backup)? Copy it there instead:
    cp /path/to/their/pubkey.asc "${v_gpg_recipient_file_secrets:-${HOME}/pubkey.asc}"
  Or point v_gpg_recipient_file_secrets at wherever it already lives.
EOF
)")
  fi

  if [[ "${#a_missing[@]}" -gt 0 ]]; then
    local v_msg
    printf "\nGPG encryption enabled, but the following recipient public keys are missing:\n" >&2
    f_log_msg "GPG encryption enabled, but the following recipient public keys are missing:"
    for v_msg in "${a_missing[@]}"; do
      printf "\n%s\n" "${v_msg}" >&2
      f_log_msg "${v_msg}"
    done
    printf "\nFix the above, then re-run NDM Linux Backup.\n\n" >&2
    exit 1
  fi
}

# Read-only companion to f_module_enabled(): for a module whose switch is
# already true, explain in one line why it would NOT actually run, or
# print nothing if it would. Mirrors f_module_enabled()'s own
# preconditions by hand, plus K_SOFT_COMMANDS presence and the DB
# credentials/podman sudo checks. Never decides whether a module runs --
# only explains a "true" switch that f_module_enabled() would reject.
function f_analyze_reason() {
  local v_module="${1}" v_cmd

  case "${v_module}" in
    v_enable_docker_volumes_data|v_enable_podman_volumes_data|v_enable_data_source_extra)
      [[ "${v_enable_data_backup}" == true ]] || { printf 'v_enable_data_backup=false -- the whole data archive is off, turn it on first'; return; }
      ;;
    v_enable_efi)
      [[ "${v_uefi_bios}" == 'uefi' ]] || { printf 'not a UEFI system'; return; }
      ;;
    v_enable_mbr)
      [[ "${#a_mbr[@]}" != 0 ]] || { printf 'no MBR-partitioned disks found'; return; }
      ;;
    v_enable_luks)
      [[ "${#a_luks[@]}" != 0 ]] || { printf 'no LUKS partitions found'; return; }
      ;;
    v_enable_luks_header_backup)
      [[ "${#a_luks[@]}" != 0 ]] || { printf 'no LUKS partitions found'; return; }
      [[ "${v_secrets_active}" == true ]] || {
        printf '%s %s' "v_enable_secrets_backup=false and no --secrets --" \
          "the whole secrets archive is off, turn it on first (or pass --secrets)"
        return
      }
      ;;
    v_enable_lvm)
      [[ "${v_lvm_present}" == true ]] || { printf 'no LVM volumes detected'; return; }
      ;;
    v_enable_rsync)
      [[ -n "${v_dest_rsync}" ]] || { printf 'v_dest_rsync is not set'; return; }
      ;;
    v_enable_pre_command)
      [[ -n "${v_pre_command}" ]] || { printf 'v_pre_command is not set'; return; }
      ;;
    v_enable_post_command)
      [[ -n "${v_post_command}" ]] || { printf 'v_post_command is not set'; return; }
      ;;
    v_enable_on_failure_command)
      [[ -n "${v_on_failure_command}" ]] || { printf 'v_on_failure_command is not set'; return; }
      ;;
  esac

  for v_cmd in ${K_COMMANDS_FOR_MODULE[${v_module}]:-}; do
    if [[ " ${K_SOFT_COMMANDS[*]} " == *" ${v_cmd} "* ]] && ! command -v "${v_cmd}" >/dev/null 2>&1; then
      printf '%s not installed' "${v_cmd}"
      return
    fi
  done

  case "${v_module}" in
    v_enable_mysql)
      [[ -f "${v_mysql_cnf_path}" ]] || [[ "${v_mysql_socket_auth}" == true ]] || {
        printf 'credentials file not found at %s -- %s %s' "${v_mysql_cnf_path}" \
          "root@localhost socket auth not probed by --analyze (read-only, no live connection attempted)," \
          "a real run may still succeed via it, see README"
        return
      }
      ;;
    v_enable_postgresql)
      [[ -f "${v_postgresql_pgpass_path}" ]] || [[ "${v_postgresql_peer_auth}" == true ]] || {
        printf 'credentials file not found at %s -- %s %s' "${v_postgresql_pgpass_path}" \
          "peer/ident auth not probed by --analyze (read-only, no live connection attempted)," \
          "a real run may still succeed via it, see README"
        return
      }
      ;;
    v_enable_podman|v_enable_podman_volumes_data)
      if [[ "${v_podman_user}" != 'root' ]] && ! command -v sudo >/dev/null 2>&1; then
        printf 'sudo not installed (needed to run podman as %s)' "${v_podman_user}"
        return
      fi
      ;;
  esac
}

# Companion to f_analyze_reason(), for a module whose switch is OFF: true
# only if turning it on would still be blocked by hardware/firmware this
# machine doesn't have, not by a missing config value/credential/tool --
# those stay "could be turned on in CONFIGURE". Mirrors the same UEFI/
# MBR/LUKS/LVM checks in f_analyze_reason(), kept in sync by hand for the
# same reason that function is.
function f_analyze_hardware_reason() {
  local v_module="${1}"
  case "${v_module}" in
    v_enable_efi)
      [[ "${v_uefi_bios}" == 'uefi' ]] || printf 'not a UEFI system'
      ;;
    v_enable_mbr)
      [[ "${#a_mbr[@]}" != 0 ]] || printf 'no MBR-partitioned disks found'
      ;;
    v_enable_luks|v_enable_luks_header_backup)
      [[ "${#a_luks[@]}" != 0 ]] || printf 'no LUKS partitions found'
      ;;
    v_enable_lvm)
      [[ "${v_lvm_present}" == true ]] || printf 'no LVM volumes detected'
      ;;
  esac
}

# Classify one module (${1}) into exactly one of the four nameref arrays
# (${2}-${5}: will-run/blocked/disabled/not-applicable), same logic
# f_analyze_report() used inline before it started grouping by archive.
function f_analyze_classify() {
  local v_module="${1}"
  # shellcheck disable=SC2178 # local -n aliases the caller's array, not a string
  local -n v_ref_run="${2}" v_ref_blocked="${3}" v_ref_disabled="${4}" v_ref_na="${5}"
  local v_short="${v_module#v_enable_}" v_switch_on v_reason v_hw_reason

  # v_enable_secrets_backup is the one module OR'd with --secrets (see
  # f_module_enabled()): the raw CONFIGURE value alone isn't authoritative.
  if [[ "${v_module}" == 'v_enable_secrets_backup' ]]; then
    v_switch_on=false
    { [[ "${v_enable_secrets_backup}" == true ]] || [[ "${v_secrets_override}" == true ]]; } && v_switch_on=true
  else
    v_switch_on="${!v_module}"
  fi

  if [[ "${v_switch_on}" != true ]]; then
    v_hw_reason="$(f_analyze_hardware_reason "${v_module}")"
    if [[ -n "${v_hw_reason}" ]]; then
      v_ref_na+=("$(printf '  %-20s -- %s' "${v_short}" "${v_hw_reason}")")
    else
      v_ref_disabled+=("${v_short}")
    fi
    return
  fi

  v_reason="$(f_analyze_reason "${v_module}")"
  if [[ -z "${v_reason}" ]]; then
    v_ref_run+=("${v_short}")
  else
    v_ref_blocked+=("$(printf '  %-20s -- %s' "${v_short}" "${v_reason}")")
  fi
}

# Print the enabled/blocked/disabled/not-applicable lines for one group
# of already-classified modules (${1}-${4}, the same nameref arrays
# f_analyze_classify() filled). No section header or master-switch line
# -- the caller prints those, since DATA/SECRETS also show their own
# archive-level switch before this, which isn't itself in these lists
# (see f_analyze_report()).
function f_analyze_print_modules() {
  # shellcheck disable=SC2178 # local -n aliases the caller's array, not a string
  local -n v_ref_run="${1}" v_ref_blocked="${2}" v_ref_disabled="${3}" v_ref_na="${4}"
  local v_joined

  if [[ "${#v_ref_run[@]}" -gt 0 ]]; then
    v_joined="$(printf '%s, ' "${v_ref_run[@]}")"
    printf "Enabled: %s\n" "${v_joined%, }"
  else
    printf "Enabled: (none)\n"
  fi
  if [[ "${#v_ref_blocked[@]}" -gt 0 ]]; then
    printf "Enabled but blocked:\n"
    printf '%s\n' "${v_ref_blocked[@]}"
  fi
  if [[ "${#v_ref_disabled[@]}" -gt 0 ]]; then
    v_joined="$(printf '%s, ' "${v_ref_disabled[@]}")"
    printf "Disabled (could enable in the settings): %s\n" "${v_joined%, }"
  fi
  if [[ "${#v_ref_na[@]}" -gt 0 ]]; then
    printf "Not applicable to this machine:\n"
    printf '%s\n' "${v_ref_na[@]}"
  fi
}

# Report, grouped by archive (settings/data/secrets, plus a cross-cutting
# section for rsync/hooks), without running a single backup command:
# which enabled modules will actually produce something, which are
# blocked (see f_analyze_reason()), which are disabled but would work if
# enabled, and which are disabled and hardware-blocked regardless (see
# f_analyze_hardware_reason()). Triggered by -a/--analyze: main() calls
# this right after UEFI/LVM detection and exits, before anything else
# runs -- purely read-only.
function f_analyze_report() {
  # shellcheck disable=SC2034 # passed by name to f_analyze_classify's/f_analyze_print_section's `local -n`, not referenced directly
  local -a a_settings_run=() a_settings_blocked=() a_settings_disabled=() a_settings_na=()
  # shellcheck disable=SC2034 # passed by name to f_analyze_classify's/f_analyze_print_section's `local -n`, not referenced directly
  local -a a_data_run=() a_data_blocked=() a_data_disabled=() a_data_na=()
  # shellcheck disable=SC2034 # passed by name to f_analyze_classify's/f_analyze_print_section's `local -n`, not referenced directly
  local -a a_secrets_run=() a_secrets_blocked=() a_secrets_disabled=() a_secrets_na=()
  # shellcheck disable=SC2034 # passed by name to f_analyze_classify's/f_analyze_print_section's `local -n`, not referenced directly
  local -a a_other_run=() a_other_blocked=() a_other_disabled=() a_other_na=()
  local v_module

  for v_module in "${K_SETTINGS_MODULES[@]}"; do
    f_analyze_classify "${v_module}" a_settings_run a_settings_blocked a_settings_disabled a_settings_na
  done
  # v_enable_data_backup/v_enable_secrets_backup are each their own
  # archive's master switch, not a sibling of the modules they gate --
  # skipped here and shown as their own line below instead, so they
  # don't read as just another item in the same Enabled/Disabled list.
  for v_module in "${K_DATA_MODULES[@]}"; do
    [[ "${v_module}" == 'v_enable_data_backup' ]] && continue
    f_analyze_classify "${v_module}" a_data_run a_data_blocked a_data_disabled a_data_na
  done
  for v_module in "${K_SECRETS_MODULES[@]}"; do
    [[ "${v_module}" == 'v_enable_secrets_backup' ]] && continue
    f_analyze_classify "${v_module}" a_secrets_run a_secrets_blocked a_secrets_disabled a_secrets_na
  done
  for v_module in "${K_OTHER_MODULES[@]}"; do
    f_analyze_classify "${v_module}" a_other_run a_other_blocked a_other_disabled a_other_na
  done

  printf "\n%s %s -- analysis for %s@%s (run --start to actually back up)\n" "${APP_NAME}" "${APP_VERSION}" "${USER}" "${v_hostname}"

  printf "\n=== SETTINGS ARCHIVE (always produced) ===\n"
  printf "Working directory (src): %s\n" "${v_tempdir}"
  printf "Destination (dest): %s\n" "${v_dest}"
  f_analyze_print_modules a_settings_run a_settings_blocked a_settings_disabled a_settings_na

  printf "\n=== DATA ARCHIVE (opt-in) ===\n"
  printf "Working directory (src): %s\n" "${v_tempdir_data}"
  printf "Destination (dest): %s\n" "${v_dest_data}"
  if [[ "${v_enable_data_backup}" == true ]]; then
    printf "Master switch (v_enable_data_backup): enabled\n"
  else
    printf "Master switch (v_enable_data_backup): disabled\n"
  fi
  f_analyze_print_modules a_data_run a_data_blocked a_data_disabled a_data_na

  printf "\n=== SECRETS ARCHIVE (opt-in) ===\n"
  printf "Working directory (src): %s\n" "${v_tempdir_secrets}"
  printf "Destination (dest): %s\n" "${v_dest_secrets}"
  if [[ "${v_enable_secrets_backup}" == true ]]; then
    printf "Master switch (v_enable_secrets_backup): enabled\n"
  elif [[ "${v_secrets_override}" == true ]]; then
    printf "Master switch (v_enable_secrets_backup): enabled (--secrets override for this run)\n"
  else
    printf "Master switch (v_enable_secrets_backup): disabled (pass --secrets to include it for this run)\n"
  fi
  f_analyze_print_modules a_secrets_run a_secrets_blocked a_secrets_disabled a_secrets_na

  f_print_encryption_status

  printf "\n=== OTHER (cross-cutting) ===\n"
  f_analyze_print_modules a_other_run a_other_blocked a_other_disabled a_other_na
  printf "\n"
}

# Run a podman command as v_podman_user, with that user's rootless
# runtime directory set up, so a rootless user's containers/images are
# visible even when this script itself runs as root. When v_podman_user
# is "root", runs podman directly (root's own, usually rootful, state).
# Called indirectly as "${v_runtime}" from f_container_metadata/f_container_volumes_data.
# shellcheck disable=SC2317,SC2329 # no literal call site
function f_podman() {
  if [[ "${v_podman_user}" == 'root' ]]; then
    podman "${@}"
  else
    sudo -u "${v_podman_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${v_podman_user}")" podman "${@}"
  fi
}

# Metadata collection shared by the Docker and Podman info steps: images/
# containers/volumes/networks lists plus daemon info. ${1} is the runtime
# command to run (`docker` or `f_podman`), ${2} the destination directory.
function f_container_metadata() {
  # v_out_dir, NOT v_dest: v_dest is already a readonly global (the
  # backup destination) by the time this runs -- `local v_dest=...` here
  # would silently fail to shadow it (bash refuses and just warns), and
  # every write below would go to v_dest instead of the caller's actual
  # ${2} (v_temp_path).
  local v_runtime="${1}" v_out_dir="${2}"
  "${v_runtime}" images | f_out "${v_out_dir}"/images.txt
  f_check_pipe "${v_runtime} images" "${v_out_dir}/images.txt"
  "${v_runtime}" ps -a | f_out "${v_out_dir}"/containers.txt
  f_check_pipe "${v_runtime} ps -a" "${v_out_dir}/containers.txt"
  "${v_runtime}" volume ls | f_out "${v_out_dir}"/volumes.txt
  f_check_pipe "${v_runtime} volume ls" "${v_out_dir}/volumes.txt"
  "${v_runtime}" network ls | f_out "${v_out_dir}"/networks.txt
  f_check_pipe "${v_runtime} network ls" "${v_out_dir}/networks.txt"
  "${v_runtime}" info | f_out "${v_out_dir}"/info.txt
  f_check_pipe "${v_runtime} info" "${v_out_dir}/info.txt"
}

# Volume content copy shared by the Docker and Podman data-pass steps:
# reads each volume's real Mountpoint (works only for the default
# "local" driver). ${1} is the runtime command (`docker` or `f_podman`),
# ${2} the destination directory.
function f_container_volumes_data() {
  # v_out_dir, NOT v_dest -- same readonly-shadowing reason as
  # f_container_metadata() above.
  local v_runtime="${1}" v_out_dir="${2}"
  local v_vol v_mountpoint
  while IFS= read -r v_vol; do
    v_mountpoint="$("${v_runtime}" volume inspect --format '{{ .Mountpoint }}' "${v_vol}" 2>/dev/null)"
    if [[ -n "${v_mountpoint}" ]] && [[ -d "${v_mountpoint}" ]]; then
      f_copy "${v_mountpoint}" "${v_out_dir}/${v_vol}"
    fi
  done < <("${v_runtime}" volume ls -q)
}

# Filter a_source_extra/a_data_source_extra (by nameref, ${1}) down to
# entries that exist on disk into ${2} (also by nameref), printing a skip
# notice (labeled ${3}) for missing ones. Shared by the settings and data
# archive ENDING blocks below.
function f_filter_existing_sources() {
  local -n v_ref_src="${1}"
  local -n v_ref_dst="${2}"
  local v_label="${3}" i
  v_ref_dst=()
  for i in "${v_ref_src[@]}"; do
    if [[ -e "${i}" ]]; then
      v_ref_dst+=("${i}")
    else
      f_print_msg "${v_label}: ${i} does not exist, skipping it"
    fi
  done
}

# Refuse to (re)use a path as a staging directory unless it is either
# absent or a real directory owned by the current euid. Defends against a
# symlink pre-planted under a predictable, world-writable path (e.g. the
# default /tmp tempdirs) that would otherwise make mkdir -p silently write
# through it into attacker-controlled storage. Must be called before any
# f_mkdir on a tempdir path; hard-exits instead of prompting, since a
# compromised path must never be offered as a normal "reuse?" choice.
function f_secure_dir() {
  local v_path="${1}"
  if [[ -L "${v_path}" ]]; then
    printf "\n%s is a symlink, refusing to use it as a working directory (possible symlink attack). Remove it and re-run.\n\n" "${v_path}" >&2
    exit 1
  fi
  if [[ -e "${v_path}" ]]; then
    if [[ ! -d "${v_path}" ]]; then
      printf "\n%s exists but is not a directory. Remove it and re-run.\n\n" "${v_path}" >&2
      exit 1
    fi
    if [[ "$(stat -c '%u' "${v_path}")" != "${EUID}" ]]; then
      printf "\n%s exists but is not owned by the current user (euid %s). Remove it and re-run.\n\n" "${v_path}" "${EUID}" >&2
      exit 1
    fi
  fi
}

# Hard-exit unless ${1} resolves under one of a_write_whitelist's roots.
# Defense-in-depth against a corrupted/empty variable pointing tar/chmod/
# chown/sha256sum/gpg/rm somewhere unintended. readlink -f only requires
# every component but the last to exist, so an about-to-be-created
# archive path still resolves correctly.
function f_assert_within_whitelist() {
  local v_path="${1}" v_real_path v_root v_real_root
  v_real_path="$(readlink -f "${v_path}" 2>/dev/null)"
  if [[ -z "${v_real_path}" ]]; then
    printf "\nSECURITY: refusing to operate on %s: cannot resolve path.\n\n" "${v_path}" >&2
    exit 1
  fi
  for v_root in "${a_write_whitelist[@]}"; do
    v_real_root="$(readlink -f "${v_root}" 2>/dev/null)"
    [[ -n "${v_real_root}" ]] || continue
    if [[ "${v_real_path}" == "${v_real_root}" ]] || [[ "${v_real_path}" == "${v_real_root}"/* ]]; then
      return 0
    fi
  done
  printf "\nSECURITY: refusing to operate on %s: outside the write whitelist (%s).\n\n" "${v_path}" "${a_write_whitelist[*]}" >&2
  exit 1
}

# Create a directory, unless in dry-run mode. An optional mode (${2}) is
# chmod'd onto it afterwards -- used for staging directories that must stay
# restricted regardless of umask or of already existing from a run predating
# this hardening.
function f_mkdir() {
  local v_path="${1}" v_mode="${2:-}"
  if [[ "${v_dry_run}" == true ]]; then
    f_print_msg "[DRY-RUN] would create directory: ${v_path}"
  else
    mkdir -p "${v_path}"
    if [[ -n "${v_mode}" ]]; then
      chmod "${v_mode}" "${v_path}"
    fi
  fi
}

# Validate and, if needed, create a staging directory (${1}, one of
# v_tempdir/v_tempdir_data/v_tempdir_secrets) AND its immediate parent
# (the shared container directory, e.g. /home/tmp) at mode 700, via
# f_secure_dir/f_mkdir. The parent is only chmod'd if it doesn't already
# exist (an existing shared system directory is never retroactively
# touched); the leaf is always re-chmod'd to 700, even on reuse.
function f_prepare_tempdir() {
  local v_path="${1}" v_parent
  v_parent="$(dirname "${v_path}")"
  f_secure_dir "${v_parent}"
  if [[ ! -d "${v_parent}" ]]; then
    f_mkdir "${v_parent}" 700
  fi
  f_secure_dir "${v_path}"
  f_mkdir "${v_path}" 700
}

# Delete old archives of one type (${1}: destination directory, ${2}:
# exact filename prefix, e.g. "${v_backup_name}_${v_hostname}" for
# settings), plus their .sha256 sidecar and, for the settings prefix
# only, the run's shared .log. No-op unless v_retention_days > 0. Always
# keeps the newest v_retention_min_keep regardless of age (see
# CONFIGURE), deletes the rest once strictly older than v_retention_days.
# Matches only ${2}_*.tar.xz, never a blanket sweep of ${1}.
function f_prune_old_archives() {
  local v_dir="${1}" v_prefix="${2}"
  local -a a_candidates=()
  local i v_count=0 v_base

  [[ "${v_retention_days}" -gt 0 ]] || return 0

  f_assert_within_whitelist "${v_dir}"

  # Newest first, so min-keep protects the most recent archives. Two
  # -name clauses (plain + .gpg) so a mixed pre/post-encryption history
  # is still counted correctly, and the .sha256 sidecar is never
  # mistaken for an archive of its own.
  mapfile -t a_candidates < <(find "${v_dir}" -maxdepth 1 \( -name "${v_prefix}_*.tar.xz" -o \
    -name "${v_prefix}_*.tar.xz.gpg" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

  for i in "${a_candidates[@]}"; do
    v_count=$((v_count + 1))
    [[ "${v_count}" -le "${v_retention_min_keep}" ]] && continue
    [[ -z "$(find "${i}" -maxdepth 0 -mtime "+${v_retention_days}" 2>/dev/null)" ]] && continue
    if [[ "${i}" == *.tar.xz.gpg ]]; then
      v_base="${i%.tar.xz.gpg}"
    else
      v_base="${i%.tar.xz}"
    fi
    if [[ "${v_dry_run}" == true ]]; then
      f_print_msg "[DRY-RUN] would delete old archive: ${i}"
    else
      f_print_msg "Deleting old archive: ${i}"
      rm -f "${i}" "${i}.sha256" "${v_base}.log"
    fi
  done
}

# Encrypt an archive (${2}/${1}'s current value, e.g. v_filename) with
# GPG, if its type is enabled (${4}, e.g. v_enable_gpg_settings) -- writes
# ${2}/${1}.gpg via --recipient-file ${3}, deletes the plaintext once the
# encrypted copy exists, and updates the caller's filename variable
# (${1}, by name) to the new .gpg name so every downstream step operates
# on the real final artifact. No-op if ${4} is false. ${3} missing while
# ${4} is true is already caught by f_check_gpg_keys() before this runs.
# Unlike a checksum failure, a failed encryption hard-exits the run.
function f_encrypt_archive() {
  local -n v_ref_filename="${1}"
  local v_dir="${2}" v_recipient_file="${3}" v_enabled="${4}" v_gpg_err

  [[ "${v_enabled}" == true ]] || return 0

  if [[ "${v_dry_run}" == true ]]; then
    f_print_msg "[DRY-RUN] would encrypt: ${v_ref_filename} -> ${v_ref_filename}.gpg"
    v_ref_filename="${v_ref_filename}.gpg"
    return 0
  fi

  f_check_command "gpg"
  f_assert_within_whitelist "${v_dir}/${v_ref_filename}.gpg"
  if v_gpg_err=$(gpg --batch --yes --output "${v_dir}/${v_ref_filename}.gpg" --encrypt \
    --recipient-file "${v_recipient_file}" "${v_dir}/${v_ref_filename}" 2>&1 >/dev/null); then
    f_assert_within_whitelist "${v_dir}/${v_ref_filename}"
    rm -f "${v_dir}/${v_ref_filename}"
    v_ref_filename="${v_ref_filename}.gpg"
    f_print_msg "Archive encrypted: ${v_ref_filename}"
  else
    printf '\nFailed to encrypt archive %s:\n%s\n\n%s %s -- %s\n\n' "${v_ref_filename}" "${v_gpg_err}" \
      "The plaintext archive was NOT deleted and still exists, unencrypted, at" \
      "${v_dir}/${v_ref_filename}" "secure or remove it manually." >&2
    f_log_msg "Failed to encrypt archive ${v_ref_filename}: ${v_gpg_err} --" \
      "plaintext archive left in place, unencrypted, at ${v_dir}/${v_ref_filename}"
    exit 1
  fi
}

# Write stdin to a file, unless in dry-run mode (the producing command
# upstream still runs for real, its stdout just gets discarded). Cannot
# see whether that upstream command failed -- see f_check_pipe, called
# as the very next statement after every `cmd | f_out ...` pipe.
function f_out() {
  if [[ "${v_dry_run}" == true ]]; then
    cat > /dev/null
    f_print_msg "[DRY-RUN] would write: ${1}"
  else
    cat > "${1}"
  fi
}

# Warn (without aborting) if the command feeding the f_out pipe above
# this call failed, so a failure doesn't silently produce an empty file
# later treated as "already collected" by the resumable-skip check. Must
# be the literal next statement after the pipe: PIPESTATUS survives only
# until bash runs another pipeline, and anything with its own `|` in
# between would clobber it first.
function f_check_pipe() {
  local v_rc="${PIPESTATUS[0]}"
  if [[ "${v_rc}" -ne 0 ]]; then
    f_print_msg "WARNING: ${1} failed (exit ${v_rc}), ${2} may be empty or incomplete"
  fi
}

# Copy a file or directory tree, unless in dry-run mode
function f_copy() {
  if [[ "${v_dry_run}" == true ]]; then
    f_print_msg "[DRY-RUN] would copy ${1} to ${2}"
  else
    cp -a "${1}" "${2}"
  fi
}

# Read raw bytes from a block device, unless in dry-run mode. In dry-run
# the same read is performed against /dev/null, proving read access to
# the source device without writing anything.
function f_dd() {
  local v_src="${1}" v_dst="${2}"
  shift 2
  if [[ "${v_dry_run}" == true ]]; then
    if dd if="${v_src}" of=/dev/null "${@}" >/dev/null 2>&1; then
      f_print_msg "[DRY-RUN] would write ${v_dst} (read of ${v_src} OK)"
    else
      f_print_msg "[DRY-RUN] WARNING: cannot read ${v_src}"
    fi
  else
    if ! dd if="${v_src}" of="${v_dst}" "${@}" >/dev/null 2>&1; then
      f_print_msg "WARNING: reading ${v_src} failed, ${v_dst} may be empty or incomplete"
    fi
  fi
}

# Check confirmations
# ${2} action: "start" | "reuse" | "delete" (omitted defaults to "start" behavior)
function f_ask_confirmation() {
  local v_action="${2:-}"
  while true; do
    printf "\n%s" "${1}"
    if ! read -r v_choice; then
      printf "\nNo input available (stdin closed) -- cannot confirm interactively. Use --quiet for unattended runs.\n\n" >&2
      exit 1
    fi
    case "${v_choice}" in
      Y|y|Yes|yes )
        if [[ "${v_action}" == 'delete' ]]; then
          printf "Deleting directory %s\n" "${v_tempdir}"
          f_assert_within_whitelist "${v_tempdir}"
          rm -rf "${v_tempdir}"
          if [[ "${v_enable_data_backup}" == true ]]; then
            printf "Deleting directory %s\n" "${v_tempdir_data}"
            f_assert_within_whitelist "${v_tempdir_data}"
            rm -rf "${v_tempdir_data}"
          fi
          if [[ "${v_secrets_active}" == true ]]; then
            printf "Deleting directory %s\n" "${v_tempdir_secrets}"
            f_assert_within_whitelist "${v_tempdir_secrets}"
            rm -rf "${v_tempdir_secrets}"
          fi
          printf "Done\n"
        else
          printf "OK, preparing...\n\n"
        fi
        break
        ;;
      N|n|No|no )
        printf "Nothing is done\n"
        if [[ "${v_action}" == 'reuse' ]]; then
          printf "You need to move %s in another location\n\n" "${v_tempdir}"
          exit 0
        elif [[ "${v_action}" != 'delete' ]]; then
          exit 0
        fi
        break
        ;;
      C|c|Cancel|cancel )
        printf "Script aborted\n\n"
        exit 0
        ;;
      * )
        printf "Invalid answer\n\n" >&2
        ;;
    esac
  done
}

# Write a line to the run's log file (v_log_path, set in main()), if
# logging is active (never in --dry-run). Independent of --quiet: the log
# is the complete record of a run regardless of terminal output, which
# matters most for unattended runs. Strips ANSI color codes. Opens,
# appends, and closes on every call instead of keeping a long-lived fd:
# a persistent fd gets inherited by every child process spawned
# afterward (mysqldump, docker, tar, lvm tools...), and some warn about it.
function f_log_msg() {
  if [[ -n "${v_log_path:-}" ]]; then
    printf '%s\n' "${*}" | sed -E 's/\x1b\[[0-9;]*m//g' >> "${v_log_path}"
  fi
}

function f_print_msg() {
  f_log_msg "${*}"
  if [[ "${v_quiet}" == false ]]; then
    printf "%s\n" "${*}"
  fi
}

# Run v_on_failure_command (${1}: the exit code that triggered it), if
# configured -- see CONFIGURE. Bound to an EXIT trap set at the top of
# main(), so it fires for whatever hard-exit produced ${1}, without a
# call at every exit site by hand. No-op for a clean exit (${1} == 0).
# Exports NDM_EXIT_CODE/NDM_LOG_PATH/NDM_ARCHIVE_PREFIX/NDM_HOSTNAME/NDM_USER,
# same eval-a-user-string mechanism as v_pre_command/v_post_command.
# shellcheck disable=SC2317,SC2329 # called indirectly via the EXIT trap set in main(), not by a literal call site
function f_run_on_failure_command() {
  local v_exit_code="${1}"
  if [[ "${v_exit_code}" -eq 0 ]] || [[ "${v_enable_on_failure_command}" != true ]] || [[ -z "${v_on_failure_command}" ]]; then
    return 0
  fi
  export NDM_EXIT_CODE="${v_exit_code}"
  export NDM_LOG_PATH="${v_log_path:-}"
  export NDM_ARCHIVE_PREFIX="${v_backup_name}"
  export NDM_HOSTNAME="${v_hostname}"
  export NDM_USER="${v_username}"
  if [[ "${v_dry_run}" == true ]]; then
    printf "[DRY-RUN] would execute on-failure command (exit %s): %s\n" "${v_exit_code}" "${v_on_failure_command}" >&2
  else
    eval "${v_on_failure_command}"
  fi
}

# Human-readable size (IEC units, e.g. "1.2G") of file ${1}, or empty if
# it does not exist -- used for NDM_*_ARCHIVE_SIZE in v_post_command.
# Empty rather than an error: in --dry-run, or for a pass that did not
# run this session, there is genuinely no file to size.
function f_human_size() {
  local v_path="${1}" v_bytes
  [[ -f "${v_path}" ]] || return 0
  v_bytes="$(stat -c%s "${v_path}" 2>/dev/null)" || return 0
  numfmt --to=iec --suffix=B --format='%.1f' "${v_bytes}" 2>/dev/null
}

function f_backup_done_msg() {
  local v_line
  if [[ "${v_dry_run}" == true ]]; then
    v_line="$(printf "%s\nSimulated (dry-run)" "${1}")"
  else
    v_line="$(printf "%s\nDone" "${1}")"
  fi
  f_log_msg "${v_line}"
  if [[ "${v_quiet}" == false ]]; then
    printf "%s\n" "${v_line}"
  fi
}

function f_backup_skipped_msg() {
  local v_line
  v_line="$(printf "%s already exists\nSkipped" "${1}")"
  f_log_msg "${v_line}"
  if [[ "${v_quiet}" == false ]]; then
    printf "%s\n" "${v_line}"
  fi
}

# Parse CLI options into the v_start/v_quiet/v_keep_tempdir/v_dry_run/
# v_secrets_override/v_analyze/v_requirements globals that the entry point
# reads. --help/--usage/--version print and return with neither v_start nor
# v_analyze set; invalid usage exits 2 (f_bad_usage).
function f_parse_arguments() {
  local v_arguments v_error
  local -r v_short='huvsqkna'
  local -r v_long='help,usage,version,requirements,start,quiet,keep,dry-run,secrets,analyze'

  # Always initialize before any early return, so callers never see these
  # unset (main() and the entry point read them as globals under set -u).
  v_start=false
  v_quiet=false
  v_keep_tempdir=false
  v_dry_run=false
  v_secrets_override=false
  v_analyze=false
  v_requirements=false

  if [[ "${#}" -lt 1 ]]; then
    f_help
    return
  fi

  if ! v_arguments=$(getopt -q -n "${0##*/}" -o "${v_short}" -l "${v_long}" -- "${@}"); then
    # Run again only to get getopt's own message (e.g. unrecognized option '--x')
    v_error="$(getopt -n "${0##*/}" -o "${v_short}" -l "${v_long}" -- "${@}" 2>&1 >/dev/null)"
    f_bad_usage "${v_error%%$'\n'*}"
  fi

  eval set -- "${v_arguments}"
  while true; do
    case "${1}" in
      -h|--help) f_help; return ;;
      -u|--usage) f_usage; return ;;
      -v|--version) f_version; return ;;
      --requirements) v_requirements=true; return ;;
      -k|--keep) v_keep_tempdir=true ;;
      -n|--dry-run) v_dry_run=true ;;
      -q|--quiet) v_quiet=true ;;
      -s|--start) v_start=true ;;
      -a|--analyze) v_analyze=true ;;
      --secrets) v_secrets_override=true ;;
      --) shift; break ;;
    esac
    shift
  done
  [[ "${#}" -eq 0 ]] || f_bad_usage "Unexpected argument: ${1}"

  # Only modifiers (-n/-q/-k/--secrets) without -s/-a: a cron line that lost
  # -s must fail visibly instead of silently doing nothing.
  if [[ "${v_start}" != true ]] && [[ "${v_analyze}" != true ]]; then
    f_bad_usage "Options -n, -q, -k and --secrets need --start or --analyze"
  fi
}


########################
### MAIN             ###
########################

function main() {

  # Notify on interruption and actually stop (a trap that does not exit
  # suppresses the default terminate action, leaving Ctrl-C/SIGTERM with
  # no effect); already collected files are kept for the next run
  trap 'printf "\nInterrupted. Re-run the script to resume; already collected files in %s are kept.\n\n" "${v_tempdir}" >&2; exit 130' INT
  trap 'printf "\nTerminated. Re-run the script to resume; already collected files in %s are kept.\n\n" "${v_tempdir}" >&2; exit 143' TERM

  # Run v_on_failure_command for any hard-exit from here on, interruption
  # above included: an EXIT trap fires on every process exit regardless
  # of the cause. See f_run_on_failure_command/CONFIGURE.
  trap 'f_run_on_failure_command "${?}"' EXIT

  ### BASIC CHECKS ###

  # Check SuperUser: this script must be run as root -- see Safety/Usage
  # in README. Deliberately does NOT re-exec itself via sudo: the caller
  # decides explicitly whether to escalate (typing sudo themselves), the
  # script never does it on their behalf.
  if [[ "${USER}" != 'root' ]]; then
    printf "\nThis script must be run as root. Re-run it with: sudo %s %s\n\n" "${0}" "${*}" >&2
    exit 1
  fi

  if [[ "${v_dry_run}" == true ]]; then
    printf "\nDRY-RUN mode: reading system information is allowed, but nothing will be created, modified, or deleted anywhere.\n"
  fi

  # Plain-text, world-readable log of this run, alongside the settings
  # archive -- see f_log_msg. Skipped in --dry-run (nothing is created)
  # and in --analyze (a pure report, must never create v_dest). Created
  # here, earlier than "Directories creation" further down, so logging
  # can start before f_check_dependencies; that later step's own check
  # just finds v_dest already there.
  if [[ "${v_analyze}" == true ]]; then
    :
  elif [[ "${v_dry_run}" == true ]]; then
    f_print_msg "[DRY-RUN] would write a log file into ${v_dest}"
  else
    f_assert_within_whitelist "${v_dest}"
    mkdir -p "${v_dest}"
    v_log_path="${v_dest}/${v_backup_name}_${v_hostname}_${v_datetime_suffix}.log"
    f_assert_within_whitelist "${v_log_path}"
    touch "${v_log_path}"
    chmod 644 "${v_log_path}"
  fi

  # Get if UEFI or BIOS setup. Computed ahead of f_check_dependencies so
  # f_module_enabled() can tell whether v_enable_efi applies to this
  # machine's real firmware, not just whether the switch is on.
  if [[ -d /sys/firmware/efi/ ]]; then
    v_uefi_bios='uefi'
  else
    v_uefi_bios='bios'
  fi
  f_print_msg "Your system is based on: ${v_uefi_bios}"

  # Whether this machine has any LVM physical/logical volumes, detected
  # via lsblk (no lvm2 tools required). Same reasoning/spot as v_uefi_bios
  # above. TYPE=lvm catches active logical volumes, FSTYPE=LVM2_member
  # catches a physical volume not yet assembled into an LV.
  v_lvm_present=false
  if command -v lsblk >/dev/null 2>&1; then
    if lsblk -rno TYPE,FSTYPE 2>/dev/null | awk '$1=="lvm" || $2=="LVM2_member"{f=1} END{exit !f}'; then
      v_lvm_present=true
    fi
  fi

  # Partition table type (gpt or dos/mbr) per disk in a_storage -- same
  # reasoning/spot as v_uefi_bios/v_lvm_present above: computed ahead of
  # the --analyze branch so f_module_enabled() can tell whether
  # v_enable_mbr applies to this machine's real disks, not just whether
  # the switch is on. Read-only, safe in every mode. Explicit =() (not
  # just `declare -a`) so an array that ends up with zero elements is
  # still "set" under `set -u`, instead of crashing as unbound.
  declare -A a_disklabel_type
  declare -a a_gpt=()
  declare -a a_mbr=()
  for i in "${a_storage[@]}"; do
    a_disklabel_type["${i}"]="$(fdisk -l "/dev/${i}" | grep Disklabel | awk '{print $3}')"
    f_print_msg "Your partition type for /dev/${i} is: ${a_disklabel_type[${i}]}"
    if [[ "${a_disklabel_type[${i}]}" == 'dos' ]]; then
      a_mbr+=("${i}")
    elif [[ "${a_disklabel_type[${i}]}" == 'gpt' ]]; then
      a_gpt+=("${i}")
    fi
  done
  readonly a_gpt
  readonly a_mbr

  # Whether the secrets pass runs this run: v_enable_secrets_backup OR'd
  # with the --secrets CLI override (see f_module_enabled()). Used
  # everywhere else in main() instead of the readonly CONFIGURE variable,
  # which the CLI flag cannot change directly.
  v_secrets_active=false
  if f_module_enabled "v_enable_secrets_backup"; then
    v_secrets_active=true
  fi

  # Whether PostgreSQL can authenticate locally via peer/ident (Unix
  # socket, no password) instead of .pgpass -- initialized false here
  # (read by f_analyze_reason() even in --analyze, which never runs the
  # live probe) and possibly flipped true by the real probe further down.
  v_postgresql_peer_auth=false
  a_pg_host=(-h localhost)

  # Same idea as v_postgresql_peer_auth below, for MySQL/MariaDB's own
  # unix_socket/auth_socket plugin (see README "MySQL/MariaDB backup", on avoiding a
  # password entirely). a_mysql_defaults, read by every mysql/mysqldump
  # call below: --defaults-file normally, --no-defaults -u root when
  # socket auth is in use instead.
  v_mysql_socket_auth=false
  a_mysql_defaults=(--defaults-file="${v_mysql_cnf_path}")

  # -a/--analyze: print the report and exit here, before anything else in
  # main() runs. Reuses the UEFI/LVM detection above.
  if [[ "${v_analyze}" == true ]]; then
    f_analyze_report
    exit 0
  fi

  # Report every dependency the script can use and, if approved, install
  # what is missing before the hard requirement check below runs.
  f_check_dependencies

  # Hard requirement check: only what your enabled backup modules (plus
  # the always-needed core commands) actually use, regardless of what
  # f_check_dependencies above did (declined install, apt failure,
  # --quiet, --dry-run, ...).
  mapfile -t a_needed_commands < <(f_hard_required_commands)
  readonly a_needed_commands
  for i in "${a_needed_commands[@]}"; do
    f_check_command "${i}"
  done

  # Live probe for the peer-auth detection above, only when .pgpass is
  # actually missing. Read-only "SELECT 1", safe even in --dry-run, and
  # time-capped so an unreachable PostgreSQL can't hang an unattended
  # run. -d postgres is explicit: with no -d, psql implicitly targets a
  # database named after v_postgresql_user, which usually doesn't exist,
  # and the probe would misreport peer auth as unavailable.
  # -w/--no-password (here and every psql/pg_dump/pg_dumpall call below)
  # forbids an interactive password prompt, so a credentials mismatch
  # fails immediately instead of blocking on stdin.
  # a_pg_host, read by every call below: emptied when peer auth is in
  # use, "-h localhost" otherwise so .pgpass auth applies as before.
  if [[ "${v_enable_postgresql}" == true ]] && [[ "$(command -v psql)" ]] && [[ ! -f "${v_postgresql_pgpass_path}" ]]; then
    if timeout 5 psql -U "${v_postgresql_user}" -w -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      v_postgresql_peer_auth=true
      a_pg_host=()
    fi
  fi

  # Same probe, for MySQL/MariaDB's unix_socket/auth_socket plugin
  # (root@localhost only -- see README). --no-defaults so no other
  # credentials file is picked up by accident during the probe itself.
  if [[ "${v_enable_mysql}" == true ]] && [[ "$(command -v mysql)" ]] && [[ ! -f "${v_mysql_cnf_path}" ]]; then
    if timeout 5 mysql --no-defaults -u root -e 'SELECT 1' >/dev/null 2>&1; then
      v_mysql_socket_auth=true
      a_mysql_defaults=(--no-defaults -u root)
    fi
  fi

  # Hard requirement check for MySQL/PostgreSQL credentials -- see
  # f_check_db_credentials(). Runs regardless of --dry-run/--quiet.
  f_check_db_credentials

  # Advisory: v_tempdir/v_tempdir_data nested under (or containing) an
  # a_source_extra/a_data_source_extra entry silently duplicates that
  # content in the archive -- see f_check_source_overlap(). Warns only,
  # never blocks: the default paths never overlap, this only fires on a
  # deliberate CONFIGURE override.
  if f_module_enabled "v_enable_source_extra"; then
    f_check_source_overlap "${v_tempdir}" "v_tempdir" a_source_extra "a_source_extra"
  fi
  if f_module_enabled "v_enable_data_source_extra"; then
    f_check_source_overlap "${v_tempdir_data}" "v_tempdir_data" a_data_source_extra "a_data_source_extra"
  fi

  # Hard requirement: v_tempdir must never equal or nest under its own
  # v_dest -- see f_check_dest_overlap(). Unlike the advisory overlap check
  # above, this one blocks: the failure mode is a silently empty archive,
  # not just duplicated content. Checked once per archive that actually
  # runs this session.
  f_check_dest_overlap "${v_tempdir}" "${v_dest}" "Settings archive"
  if [[ "${v_enable_data_backup}" == true ]]; then
    f_check_dest_overlap "${v_tempdir_data}" "${v_dest_data}" "Data archive"
  fi
  if [[ "${v_secrets_active}" == true ]]; then
    f_check_dest_overlap "${v_tempdir_secrets}" "${v_dest_secrets}" "Secrets archive"
  fi

  # Hard requirement check for GPG recipient keys -- see f_check_gpg_keys().
  f_check_gpg_keys

  # Ask for confirmation to use this script
  if [[ "${v_dry_run}" == false ]] && [[ "${v_quiet}" == false ]]; then
    v_msg="Do you really want to execute this script? ([Y]es/[N]o/[C]ancel, no default, type it out)? "
    f_ask_confirmation "${v_msg}" "start"
  fi

  # Ask for confirmation to use an existing temp directory. f_secure_dir
  # runs first and unconditionally exits on a symlink or wrong-owner
  # path, so a compromised directory is never offered as a "reuse?" choice.
  if [[ "${v_dry_run}" == false ]]; then
    f_secure_dir "${v_tempdir}"
    if [[ "${v_quiet}" == false ]] && [[ -d "${v_tempdir}" ]]; then
      printf "Directory '%s' already exists" "${v_tempdir}"
      v_msg="Do you really want to use it? ([Y]es/[N]o/[C]ancel, no default, type it out)? "
      f_ask_confirmation "${v_msg}" "reuse"
    fi
  fi

  # Unconditional printf, same reasoning as the final summary below: from
  # here on, real work starts and can take a while (lshw, inxi, dpkg -V
  # over the whole system...) with nothing else printed until it's done
  # in --quiet -- long enough to look hung without this.
  if [[ "${v_dry_run}" == true ]]; then
    printf "\n[DRY-RUN] Backup simulation started -- this can take a while.\n"
  else
    printf "\nBackup started -- this can take a while. Watch progress live: tail -f %s\n" "${v_log_path}"
    f_log_msg "Backup started"
  fi

  ### START BACKUP ###

  # Execute pre command (skipped in dry-run: arbitrary user command, not
  # guaranteed to be read-only)
  if [[ "${v_enable_pre_command}" != true ]]; then
    f_print_msg $'\nv_enable_pre_command: disabled, skipping'
  elif [[ -n "${v_pre_command}" ]]; then
    export NDM_HOSTNAME="${v_hostname}"
    export NDM_ARCHIVE_PREFIX="${v_backup_name}"
    export NDM_LOG_PATH="${v_log_path:-}"
    export NDM_USER="${v_username}"
    if [[ "${v_dry_run}" == true ]]; then
      f_print_msg $'\n[DRY-RUN] would execute pre command: '"${v_pre_command}"
    else
      f_print_msg $'\nExecuting pre command'
      eval "${v_pre_command}"
    fi
  fi

  # Directories creation. Staging trees (v_tempdir/v_tempdir_data/
  # v_tempdir_secrets, as opposed to the v_dest* destinations) go through
  # f_prepare_tempdir: a symlink/ownership check via f_secure_dir plus a
  # hard 700 mode via f_mkdir's mode argument, applied to both the leaf
  # and its shared container directory.
  # umask 077 covers every file/directory created from here on so staged
  # content stays owner-only even without an explicit mode on each call.
  umask 077
  if [[ ! -d "${v_dest}" ]]; then
    f_mkdir "${v_dest}"
  fi
  f_prepare_tempdir "${v_tempdir}"
  if [[ "${v_enable_rsync}" == true ]] && [[ -n "${v_dest_rsync}" ]] && [[ ! -d "${v_dest_rsync}" ]]; then
    f_mkdir "${v_dest_rsync}"
  fi
  if [[ "${v_enable_data_backup}" == true ]]; then
    if [[ ! -d "${v_dest_data}" ]]; then
      f_mkdir "${v_dest_data}"
    fi
    f_prepare_tempdir "${v_tempdir_data}"
  fi
  if [[ "${v_secrets_active}" == true ]]; then
    if [[ ! -d "${v_dest_secrets}" ]]; then
      f_mkdir "${v_dest_secrets}"
    fi
    f_prepare_tempdir "${v_tempdir_secrets}"
  fi

  # Hardware info
  if [[ "${v_enable_hardware}" == true ]]; then
    f_print_msg $'\nBacking up Hardware list with lshw'
    v_temp_path="${v_tempdir}"/lshw.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      lshw | f_out "${v_temp_path}"
      f_check_pipe "lshw" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Hardware list with lshw: disabled, skipping'
  fi

  # List PCI and USB Devices
  if [[ "${v_enable_devices}" == true ]]; then
    f_print_msg $'\nBacking up list of PCI and USB devices'
    v_temp_path="${v_tempdir}"/devices
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      lspci -nn | f_out "${v_temp_path}"/lspci.txt
      f_check_pipe "lspci -nn" "${v_temp_path}/lspci.txt"
      lsusb | f_out "${v_temp_path}"/lsusb.txt
      f_check_pipe "lsusb" "${v_temp_path}/lsusb.txt"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up list of PCI and USB devices: disabled, skipping'
  fi

  # List Block Devices
  if [[ "${v_enable_lsblk}" == true ]]; then
    f_print_msg $'\nBacking up lsblk'
    v_temp_path="${v_tempdir}"/lsblk.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      lsblk --all --fs | f_out "${v_temp_path}"
      f_check_pipe "lsblk --all --fs" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up lsblk: disabled, skipping'
  fi

  # List of all installed devices ID
  if [[ "${v_enable_blkid}" == true ]]; then
    f_print_msg $'\nBacking up installed devices ID list'
    v_temp_path="${v_tempdir}"/blkid.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      blkid | f_out "${v_temp_path}"
      f_check_pipe "blkid" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up installed devices ID list: disabled, skipping'
  fi

  # HW/SW info
  if [[ "${v_enable_inxi}" == true ]]; then
    f_print_msg $'\nBacking up infos with inxi'
    v_temp_path="${v_tempdir}"/inxi.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      inxi --full | f_out "${v_temp_path}"
      f_check_pipe "inxi --full" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up infos with inxi: disabled, skipping'
  fi

  # UEFI
  if [[ "${v_enable_efi}" == true ]]; then
    f_print_msg $'\nBacking up EFI'
    v_temp_path="${v_tempdir}"/efi
    # efibootmgr is a K_SOFT_COMMANDS entry (see there): missing it should
    # skip this one optional module, not hard-exit the whole run.
    if [[ "${v_uefi_bios}" == 'uefi' ]] && [[ "$(command -v efibootmgr)" ]] && [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      efibootmgr --verbose | f_out "${v_temp_path}"/efibootmgr.txt
      f_check_pipe "efibootmgr --verbose" "${v_temp_path}/efibootmgr.txt"
      # /boot/efi is the conventional Debian ESP mountpoint, not
      # guaranteed: could be mounted elsewhere or absent (rescue/live
      # environment). Checked for real even in --dry-run; without this,
      # f_copy's "cp -a" would fail raw while the step was still "done".
      if [[ -d /boot/efi ]]; then
        f_copy /boot/efi "${v_temp_path}"/boot_efi
      else
        printf "\nWARNING: /boot/efi not found -- EFI System Partition content not backed up, only the NVRAM boot entries above.\n" >&2
        f_log_msg "WARNING: /boot/efi not found -- EFI System Partition content not backed up, only the NVRAM boot entries above"
      fi
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No UEFI, no efibootmgr, or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up EFI: disabled, skipping'
  fi

  # MBR
  if [[ "${v_enable_mbr}" == true ]]; then
    f_print_msg $'\nBacking up MBR BIOS'
    v_temp_path="${v_tempdir}"/mbr
    if [[ "${#a_mbr[@]}" != 0 ]] && [[ ! -d "${v_temp_path}" ]]; then
      f_check_command "dd"
      f_mkdir "${v_temp_path}"
      for i in "${a_mbr[@]}"; do
        f_print_msg "Backing up MBR for /dev/${i}"
        # First 1MiB, not just the 512-byte boot sector: covers the GRUB
        # embedding gap between the MBR and the first partition (where
        # grub-pc/BIOS-GRUB stores its stage-1.5 code), needed for a full
        # boot sector restore.
        f_dd "/dev/$i" "${v_temp_path}/${i}_mbr.bin" bs=1M count=1
      done
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No BIOS or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up MBR BIOS: disabled, skipping'
  fi

  # LUKS
  if [[ "${v_enable_luks}" == true ]]; then
    f_print_msg $'\nBacking up LUKS info'
    v_temp_path="${v_tempdir}"/luks
    if [[ "${#a_luks[@]}" != 0 ]] && [[ ! -d "${v_temp_path}" ]]; then
      f_check_command "cryptsetup"
      f_mkdir "${v_temp_path}"
      for i in "${a_luks[@]}"; do
        cryptsetup luksDump "/dev/$i" | f_out "${v_temp_path}/luksDump_${i}.txt"
        f_check_pipe "cryptsetup luksDump /dev/$i" "${v_temp_path}/luksDump_${i}.txt"
        cryptsetup luksUUID "/dev/$i" | f_out "${v_temp_path}/luksUUID_${i}.txt"
        f_check_pipe "cryptsetup luksUUID /dev/$i" "${v_temp_path}/luksUUID_${i}.txt"
      done
      f_out "${v_temp_path}"/crypttab.txt < /etc/crypttab
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No LUKS or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up LUKS info: disabled, skipping'
  fi

  # LVM
  if [[ "${v_enable_lvm}" == true ]]; then
    f_print_msg $'\nBacking up LVM info'
    v_temp_path="${v_tempdir}"/lvm
    if [[ "$(command -v lvmdump)" ]] && [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      if [[ "${v_dry_run}" == true ]]; then
        f_print_msg "[DRY-RUN] would run lvmdump into ${v_temp_path}/lvmdump"
      else
        lvmdump -d "${v_temp_path}"/lvmdump >/dev/null 2>&1
      fi
      pvdisplay --verbose | f_out "${v_temp_path}"/pvdisplay.txt
      f_check_pipe "pvdisplay --verbose" "${v_temp_path}/pvdisplay.txt"
      vgdisplay --verbose | f_out "${v_temp_path}"/vgdisplay.txt
      f_check_pipe "vgdisplay --verbose" "${v_temp_path}/vgdisplay.txt"
      lvdisplay --verbose | f_out "${v_temp_path}"/lvdisplay.txt
      f_check_pipe "lvdisplay --verbose" "${v_temp_path}/lvdisplay.txt"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No LVM or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up LVM info: disabled, skipping'
  fi

  # OS Release
  if [[ "${v_enable_os_release}" == true ]]; then
    f_print_msg $'\nBacking up OS release'
    v_temp_path="${v_tempdir}"/lsb_release.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      lsb_release --all 2>/dev/null | grep -v "No LSB modules" | f_out "${v_temp_path}"
      f_check_pipe "lsb_release --all" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up OS release: disabled, skipping'
  fi

  # Kernel Release
  if [[ "${v_enable_kernel}" == true ]]; then
    f_print_msg $'\nBacking up Kernel release'
    v_temp_path="${v_tempdir}"/uname.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      uname --all | f_out "${v_temp_path}"
      f_check_pipe "uname --all" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Kernel release: disabled, skipping'
  fi

  # Partitions
  if [[ "${v_enable_partitions}" == true ]]; then
    f_print_msg $'\nBacking up Partition Table'
    v_temp_path="${v_tempdir}"/partitions
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      for i in "${a_storage[@]}"; do
        fdisk -l "/dev/${i}" | f_out "${v_temp_path}/fdisk_${i}.txt"
        f_check_pipe "fdisk -l /dev/${i}" "${v_temp_path}/fdisk_${i}.txt"
        sfdisk -d "/dev/${i}" | f_out "${v_temp_path}/sfdisk_${i}.txt"
        f_check_pipe "sfdisk -d /dev/${i}" "${v_temp_path}/sfdisk_${i}.txt"
      done
      f_copy /etc/fstab "${v_temp_path}"/fstab.txt
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Partition Table: disabled, skipping'
  fi

  # Grub
  if [[ "${v_enable_grub}" == true ]]; then
    f_print_msg $'\nBacking up Grub'
    v_temp_path="${v_tempdir}"/grub
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      f_copy /boot/grub "${v_temp_path}"/boot_grub
      f_copy /etc/default/grub "${v_temp_path}"/default_grub.txt
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Grub: disabled, skipping'
  fi

  # Installed packages
  if [[ "${v_enable_packages}" == true ]]; then
    f_print_msg $'\nBacking up installed software'
    v_temp_path="${v_tempdir}"/software
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      dpkg -l | grep '^ii' | f_out "${v_temp_path}"/dpkg_installed.txt
      f_check_pipe "dpkg -l" "${v_temp_path}/dpkg_installed.txt"
      apt-mark showmanual | f_out "${v_temp_path}"/apt_manual.txt
      f_check_pipe "apt-mark showmanual" "${v_temp_path}/apt_manual.txt"
      apt-mark showauto | f_out "${v_temp_path}"/apt_auto.txt
      f_check_pipe "apt-mark showauto" "${v_temp_path}/apt_auto.txt"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up installed software: disabled, skipping'
  fi

  # Flatpak
  if [[ "${v_enable_flatpak}" == true ]]; then
    f_print_msg $'\nBacking up Flatpak app list'
    v_temp_path="${v_tempdir}"/flatpak.txt
    if [[ "$(command -v flatpak)" ]] && [[ ! -f "${v_temp_path}" ]]; then
      flatpak list --app | f_out "${v_temp_path}"
      f_check_pipe "flatpak list --app" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No Flatpak or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Flatpak app list: disabled, skipping'
  fi

  # AppImages: no central registry for these (that is the point of the
  # format), so this only lists what is found (size + path); it does not
  # copy the files themselves (add the directory to a_source_extra for
  # that). Searches /home, /root, /opt, /usr/local/bin by default, plus
  # any extra paths configured in a_appimages_extra_paths.
  if [[ "${v_enable_appimages}" == true ]]; then
    f_print_msg $'\nBacking up AppImages list'
    v_temp_path="${v_tempdir}"/appimages.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      find /home /root /opt /usr/local/bin "${a_appimages_extra_paths[@]}" -maxdepth 6 \
        -iname '*.appimage' -type f -printf '%s\t%p\n' 2>/dev/null | f_out "${v_temp_path}"
      f_check_pipe "find (AppImages)" "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up AppImages list: disabled, skipping'
  fi

  # Modified system files: files whose content no longer matches what their
  # package originally installed (dpkg -V checksum mismatch), typically
  # manually-edited config files. Only catches files already tracked by a
  # package; brand new, unpackaged files are not detected. Copies the files
  # themselves (not just a list), preserving their original path under
  # modified_files/.
  if [[ "${v_enable_modified_files}" == true ]]; then
    f_print_msg $'\nBacking up manually modified system files'
    v_temp_path="${v_tempdir}"/modified_files
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      while IFS= read -r v_file; do
        [[ -f "${v_file}" ]] || continue
        f_mkdir "${v_temp_path}$(dirname "${v_file}")"
        f_copy "${v_file}" "${v_temp_path}${v_file}"
      done < <(dpkg -V 2>/dev/null | awk '{print $NF}')
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up manually modified system files: disabled, skipping'
  fi

  # Unpackaged /etc files: the complement of the step above -- files
  # under /etc no installed package's manifest lists at all (dpkg -V only
  # flags files it already knows about), a blind spot that misses e.g.
  # postgresql.conf, generated by postinst scripts rather than shipped.
  # a_unpackaged_files_ignore_regex filters out stock Debian install
  # artifacts that would otherwise be noise every run.
  if [[ "${v_enable_unpackaged_files}" == true ]]; then
    f_print_msg $'\nBacking up unpackaged /etc files'
    v_temp_path="${v_tempdir}"/unpackaged_files
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      v_ignore_regex="$(IFS='|'; echo "${a_unpackaged_files_ignore_regex[*]}")"
      while IFS= read -r v_file; do
        [[ -f "${v_file}" ]] || continue
        f_mkdir "${v_temp_path}$(dirname "${v_file}")"
        f_copy "${v_file}" "${v_temp_path}${v_file}"
      done < <(comm -23 <(find /etc -type f 2>/dev/null | sort) <(cat /var/lib/dpkg/info/*.list 2>/dev/null | sort -u) | grep -vE "${v_ignore_regex}")
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up unpackaged /etc files: disabled, skipping'
  fi

  # CRON
  if [[ "${v_enable_cron}" == true ]]; then
    f_print_msg $'\nBacking up root crons'
    v_temp_path="${v_tempdir}"/crontab.txt
    if [[ ! -f "${v_temp_path}" ]]; then
      # No f_check_pipe here on purpose: `crontab -l` exits 1 whenever
      # root simply has no crontab configured at all, which is a normal,
      # common state, not a failure -- an empty crontab.txt correctly
      # reflects it.
      crontab -l | f_out "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up root crons: disabled, skipping'
  fi

  # Declared here (even when unused this run) so the data-pass reuse
  # check further down is safe under `set -u` even when the schema pass
  # is itself skipped (e.g. resuming a run where *_schema/ already
  # existed).
  a_databases=()
  a_pg_databases=()

  # MySQL/MariaDB: table/view/routine structure only (no rows) -- this is
  # setup, not data, so it always lives in the settings archive whenever
  # v_enable_mysql is on. Actual row data is dumped separately in the DATA
  # BACKUP section below, only if v_enable_data_backup is also on.
  if [[ "${v_enable_mysql}" == true ]]; then
    f_print_msg $'\nBacking up MySQL/MariaDB schema'
    v_temp_path="${v_tempdir}"/mysql_schema
    if [[ "$(command -v mysqldump)" ]] && [[ ! -d "${v_temp_path}" ]] \
      && { [[ -f "${v_mysql_cnf_path}" ]] || [[ "${v_mysql_socket_auth}" == true ]]; }; then
      f_mkdir "${v_temp_path}"
      if [[ "${v_mysql_single_dump}" == false ]]; then
        # Database listing is read-only: run for real even in dry-run.
        # sys excluded too: diagnostic schema with no data of its own,
        # its views need near-root privileges to dump cleanly.
        mapfile -t a_databases < <(mysql "${a_mysql_defaults[@]}" -e "SHOW DATABASES;" \
          | grep -Ev '^(Database|information_schema|performance_schema|sys)$')
        for v_db in "${a_databases[@]}"; do
          if [[ "${v_dry_run}" == true ]]; then
            f_print_msg "[DRY-RUN] would dump schema of ${v_db} to ${v_temp_path}/schema_${v_db}.sql"
          else
            mysqldump "${a_mysql_defaults[@]}" --force --opt --no-data --databases "${v_db}" > "${v_temp_path}/schema_${v_db}.sql"
          fi
        done
      else
        if [[ "${v_dry_run}" == true ]]; then
          f_print_msg "[DRY-RUN] would dump all schemas to ${v_temp_path}/schema_all.sql"
        else
          mysqldump "${a_mysql_defaults[@]}" --force --opt --no-data --all-databases > "${v_temp_path}/schema_all.sql"
        fi
      fi
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No MySQL/MariaDB or missed ${v_mysql_cnf_path} (and no socket auth) or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up MySQL/MariaDB schema: disabled, skipping'
  fi

  # PostgreSQL: schema only, same reasoning as MySQL/MariaDB above. Actual
  # row data is dumped separately in the DATA BACKUP section below, only
  # if v_enable_data_backup is also on.
  if [[ "${v_enable_postgresql}" == true ]]; then
    f_print_msg $'\nBacking up PostgreSQL schema'
    v_temp_path="${v_tempdir}"/postgresql_schema
    if [[ "$(command -v pg_dump)" ]] && [[ ! -d "${v_temp_path}" ]] \
      && { [[ -f "${v_postgresql_pgpass_path}" ]] || [[ "${v_postgresql_peer_auth}" == true ]]; }; then
      f_mkdir "${v_temp_path}"
      if [[ "${v_postgresql_single_dump}" == false ]]; then
        # Database listing is read-only: run for real even in dry-run.
        # a_pg_host/-d postgres: same reasoning as the peer-auth probe in
        # main(). Exit status is checked and hard-exits on failure: an
        # empty a_pg_databases here would otherwise silently produce a
        # schema dump missing every database, reported as "done".
        if ! v_pg_databases_raw=$(PGPASSFILE="${v_postgresql_pgpass_path}" psql \
          -U "${v_postgresql_user}" -w -d postgres "${a_pg_host[@]}" \
          -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>&1); then
          printf "\nFailed to list PostgreSQL databases:\n%s\n\n" "${v_pg_databases_raw}" >&2
          f_log_msg "Failed to list PostgreSQL databases: ${v_pg_databases_raw}"
          exit 1
        fi
        # "<<<" always appends a newline, so mapfile-ing an empty string
        # directly would produce one empty-string element instead of a
        # genuinely empty array -- guarded here for a cluster with no
        # non-template databases.
        if [[ -n "${v_pg_databases_raw}" ]]; then
          mapfile -t a_pg_databases <<< "${v_pg_databases_raw}"
        else
          a_pg_databases=()
        fi
        for v_db in "${a_pg_databases[@]}"; do
          if [[ "${v_dry_run}" == true ]]; then
            f_print_msg "[DRY-RUN] would dump schema of ${v_db} to ${v_temp_path}/schema_${v_db}.sql"
          else
            # Not a hard-exit like the listing query above: one database
            # failing must not abort the others still queued, but is
            # still surfaced loudly instead of a silent "done". "2>&1
            # >file" captures only stderr into v_pg_dump_err, dump content
            # still goes straight to the file.
            if ! v_pg_dump_err=$(PGPASSFILE="${v_postgresql_pgpass_path}" pg_dump \
              -U "${v_postgresql_user}" -w "${a_pg_host[@]}" --schema-only "${v_db}" \
              2>&1 >"${v_temp_path}/schema_${v_db}.sql"); then
              printf "\nWARNING: pg_dump failed for database %s (schema):\n%s\n" "${v_db}" "${v_pg_dump_err}" >&2
              f_log_msg "WARNING: pg_dump failed for database ${v_db} (schema): ${v_pg_dump_err}"
            fi
          fi
        done
      else
        if [[ "${v_dry_run}" == true ]]; then
          f_print_msg "[DRY-RUN] would dump all schemas to ${v_temp_path}/schema_all.sql"
        else
          PGPASSFILE="${v_postgresql_pgpass_path}" pg_dumpall -U "${v_postgresql_user}" \
            -w "${a_pg_host[@]}" --schema-only > "${v_temp_path}/schema_all.sql"
        fi
      fi
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No PostgreSQL or missed ${v_postgresql_pgpass_path} or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up PostgreSQL schema: disabled, skipping'
  fi

  # Docker: metadata only (images/containers/volumes/networks lists and
  # daemon info), not the actual container/volume data
  if [[ "${v_enable_docker}" == true ]]; then
    f_print_msg $'\nBacking up Docker info'
    v_temp_path="${v_tempdir}"/docker
    if [[ "$(command -v docker)" ]] && [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      f_container_metadata docker "${v_temp_path}"
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No Docker or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Docker info: disabled, skipping'
  fi

  # Compose files: same file naming convention for Docker Compose and
  # podman-compose, so one search covers both. Unlike Podman's Quadlet
  # units below, Compose has no fixed location (every project keeps its
  # own), so this searches common locations and copies what it finds.
  if [[ "${v_enable_docker_compose}" == true ]]; then
    f_print_msg $'\nBacking up Compose files (Docker Compose / podman-compose)'
    v_temp_path="${v_tempdir}"/docker_compose_files
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      while IFS= read -r v_file; do
        f_mkdir "${v_temp_path}$(dirname "${v_file}")"
        f_copy "${v_file}" "${v_temp_path}${v_file}"
      done < <(find /home /root /opt /srv "${a_docker_compose_extra_paths[@]}" -maxdepth 6 \( \
        -iname 'docker-compose*.yml' -o -iname 'docker-compose*.yaml' -o -iname 'compose.yml' -o \
        -iname 'compose.yaml' \) -type f 2>/dev/null)
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Compose files (Docker Compose / podman-compose): disabled, skipping'
  fi

  # Podman: metadata plus config and Quadlet (systemd) unit files, which
  # unlike Docker Compose have fixed, well-known locations: /etc/containers
  # (system-wide) and ~/.config/containers for v_podman_user (rootless).
  # Runs metadata commands as v_podman_user to see that user's state.
  if [[ "${v_enable_podman}" == true ]]; then
    f_print_msg $'\nBacking up Podman info'
    v_temp_path="${v_tempdir}"/podman
    if [[ "$(command -v podman)" ]] && [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      f_container_metadata f_podman "${v_temp_path}"
      if [[ -d /etc/containers ]]; then
        f_copy /etc/containers "${v_temp_path}"/etc_containers
      fi
      v_podman_home="$(getent passwd "${v_podman_user}" | cut -d: -f6)"
      if [[ -n "${v_podman_home}" ]] && [[ -d "${v_podman_home}/.config/containers" ]]; then
        f_copy "${v_podman_home}/.config/containers" "${v_temp_path}/user_containers_config"
      fi
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "No Podman or ${v_temp_path}"
    fi
  else
    f_print_msg $'\nBacking up Podman info: disabled, skipping'
  fi

  ### DATA BACKUP ### (separate archive, opt-in: see v_enable_data_backup)

  if [[ "${v_enable_data_backup}" == true ]]; then

    # MySQL/MariaDB: actual row data. Schema is backed up separately
    # above into the settings archive whenever v_enable_mysql is on; this
    # needs v_enable_mysql on too, since there is no separate
    # "data-only" switch.
    if [[ "${v_enable_mysql}" == true ]]; then
      f_print_msg $'\nBacking up MySQL/MariaDB data'
      v_temp_path="${v_tempdir_data}"/mysql
      if [[ "$(command -v mysqldump)" ]] && [[ ! -d "${v_temp_path}" ]] \
        && { [[ -f "${v_mysql_cnf_path}" ]] || [[ "${v_mysql_socket_auth}" == true ]]; }; then
        f_mkdir "${v_temp_path}"
        if [[ "${v_mysql_single_dump}" == false ]]; then
          # Reuse the database list already fetched in the schema pass
          # above (same run); only re-query here if that step was itself
          # skipped this run (e.g. resuming where mysql_schema/ already
          # existed from a previous run).
          if [[ "${#a_databases[@]}" -eq 0 ]]; then
            mapfile -t a_databases < <(mysql "${a_mysql_defaults[@]}" -e "SHOW DATABASES;" \
              | grep -Ev '^(Database|information_schema|performance_schema|sys)$')
          fi
          for v_db in "${a_databases[@]}"; do
            if [[ "${v_dry_run}" == true ]]; then
              f_print_msg "[DRY-RUN] would dump data of ${v_db} to ${v_temp_path}/data_${v_db}.sql"
            else
              mysqldump "${a_mysql_defaults[@]}" --force --opt --no-create-info --databases "${v_db}" > "${v_temp_path}/data_${v_db}.sql"
            fi
          done
        else
          if [[ "${v_dry_run}" == true ]]; then
            f_print_msg "[DRY-RUN] would dump all data to ${v_temp_path}/data_all.sql"
          else
            mysqldump "${a_mysql_defaults[@]}" --force --opt --no-create-info --all-databases > "${v_temp_path}/data_all.sql"
          fi
        fi
        f_backup_done_msg "${v_temp_path}"
      else
        f_backup_skipped_msg "No MySQL/MariaDB or missed ${v_mysql_cnf_path} (and no socket auth) or ${v_temp_path}"
      fi
    else
      f_print_msg $'\nBacking up MySQL/MariaDB data: disabled, skipping'
    fi

    # PostgreSQL: actual row data, same reasoning as MySQL/MariaDB above.
    if [[ "${v_enable_postgresql}" == true ]]; then
      f_print_msg $'\nBacking up PostgreSQL data'
      v_temp_path="${v_tempdir_data}"/postgresql
      if [[ "$(command -v pg_dump)" ]] && [[ ! -d "${v_temp_path}" ]] \
        && { [[ -f "${v_postgresql_pgpass_path}" ]] || [[ "${v_postgresql_peer_auth}" == true ]]; }; then
        f_mkdir "${v_temp_path}"
        if [[ "${v_postgresql_single_dump}" == false ]]; then
          # Same reuse-if-already-fetched reasoning as the MySQL data
          # block above; same -d postgres / exit-status-checked / empty-
          # array handling as the schema pass above.
          if [[ "${#a_pg_databases[@]}" -eq 0 ]]; then
            if ! v_pg_databases_raw=$(PGPASSFILE="${v_postgresql_pgpass_path}" psql \
              -U "${v_postgresql_user}" -w -d postgres "${a_pg_host[@]}" \
              -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>&1); then
              printf "\nFailed to list PostgreSQL databases:\n%s\n\n" "${v_pg_databases_raw}" >&2
              f_log_msg "Failed to list PostgreSQL databases: ${v_pg_databases_raw}"
              exit 1
            fi
            if [[ -n "${v_pg_databases_raw}" ]]; then
              mapfile -t a_pg_databases <<< "${v_pg_databases_raw}"
            else
              a_pg_databases=()
            fi
          fi
          for v_db in "${a_pg_databases[@]}"; do
            if [[ "${v_dry_run}" == true ]]; then
              f_print_msg "[DRY-RUN] would dump data of ${v_db} to ${v_temp_path}/data_${v_db}.sql"
            else
              # Same reasoning as the schema pass above: one database's
              # failure is surfaced, not silently swallowed, without
              # aborting the rest of the loop.
              if ! v_pg_dump_err=$(PGPASSFILE="${v_postgresql_pgpass_path}" pg_dump \
                -U "${v_postgresql_user}" -w "${a_pg_host[@]}" --data-only "${v_db}" \
                2>&1 >"${v_temp_path}/data_${v_db}.sql"); then
                printf "\nWARNING: pg_dump failed for database %s (data):\n%s\n" "${v_db}" "${v_pg_dump_err}" >&2
                f_log_msg "WARNING: pg_dump failed for database ${v_db} (data): ${v_pg_dump_err}"
              fi
            fi
          done
        else
          if [[ "${v_dry_run}" == true ]]; then
            f_print_msg "[DRY-RUN] would dump all data to ${v_temp_path}/data_all.sql"
          else
            PGPASSFILE="${v_postgresql_pgpass_path}" pg_dumpall -U "${v_postgresql_user}" \
              -w "${a_pg_host[@]}" --data-only > "${v_temp_path}/data_all.sql"
          fi
        fi
        f_backup_done_msg "${v_temp_path}"
      else
        f_backup_skipped_msg "No PostgreSQL or missed ${v_postgresql_pgpass_path} or ${v_temp_path}"
      fi
    else
      f_print_msg $'\nBacking up PostgreSQL data: disabled, skipping'
    fi

    # Docker volumes: real content (not just docker volume ls from the
    # metadata step above), one folder per volume, read via each
    # volume's Mountpoint (works only for the default "local" driver).
    # Copying a volume actively written by a running container can
    # produce an inconsistent copy -- same caveat as copying a live
    # database data directory directly; for database volumes prefer the
    # MySQL/PostgreSQL data dumps above instead.
    if [[ "${v_enable_docker_volumes_data}" == true ]]; then
      f_print_msg $'\nBacking up Docker volumes data'
      v_temp_path="${v_tempdir_data}"/docker_volumes
      if [[ "$(command -v docker)" ]] && [[ ! -d "${v_temp_path}" ]]; then
        f_mkdir "${v_temp_path}"
        f_container_volumes_data docker "${v_temp_path}"
        f_backup_done_msg "${v_temp_path}"
      else
        f_backup_skipped_msg "No Docker or ${v_temp_path}"
      fi
    else
      f_print_msg $'\nBacking up Docker volumes data: disabled, skipping'
    fi

    # Podman volumes: same approach as Docker above, read as
    # v_podman_user via f_podman so rootless volumes are found too.
    if [[ "${v_enable_podman_volumes_data}" == true ]]; then
      f_print_msg $'\nBacking up Podman volumes data'
      v_temp_path="${v_tempdir_data}"/podman_volumes
      if [[ "$(command -v podman)" ]] && [[ ! -d "${v_temp_path}" ]]; then
        f_mkdir "${v_temp_path}"
        f_container_volumes_data f_podman "${v_temp_path}"
        f_backup_done_msg "${v_temp_path}"
      else
        f_backup_skipped_msg "No Podman or ${v_temp_path}"
      fi
    else
      f_print_msg $'\nBacking up Podman volumes data: disabled, skipping'
    fi

  else
    f_print_msg $'\nData backup: disabled, skipping'
  fi

  ### SECRETS BACKUP ### (separate archive, opt-in: see v_enable_secrets_backup / --secrets)

  if [[ "${v_secrets_active}" == true ]]; then
    f_print_msg $'\nBacking up secrets'
    # A subdirectory, not v_tempdir_secrets itself: "Directories creation"
    # earlier in main() already pre-creates v_tempdir_secrets
    # unconditionally, so checking it directly for "already done" would
    # always skip.
    v_temp_path="${v_tempdir_secrets}"/files
    if [[ ! -d "${v_temp_path}" ]]; then
      f_mkdir "${v_temp_path}"
      # shellcheck disable=SC2034 # passed by name to f_filter_existing_sources's `local -n`, not referenced directly
      a_secrets_all_source=( "${a_secrets_source[@]}" "${a_secrets_source_extra[@]}" )
      f_filter_existing_sources a_secrets_all_source a_secrets_existing "a_secrets_source"
      # shellcheck disable=SC2154 # assigned by f_filter_existing_sources's `local -n` output param, not directly here
      for i in "${a_secrets_existing[@]}"; do
        f_mkdir "${v_temp_path}$(dirname "${i}")"
        f_copy "${i}" "${v_temp_path}${i}"
      done
      f_backup_done_msg "${v_temp_path}"
    else
      f_backup_skipped_msg "${v_temp_path}"
    fi

    # Raw LUKS header backup: opt-in on top of the secrets pass itself
    # (see CONFIGURE). Unlike luks/luksDump_*.txt in the settings archive
    # (text only), this is a real restorable image with the keyslots
    # themselves, so it never belongs anywhere but here.
    if [[ "${v_enable_luks_header_backup}" == true ]]; then
      f_print_msg $'\nBacking up LUKS headers (raw, restorable)'
      v_temp_path="${v_tempdir_secrets}"/luks_headers
      if [[ "${#a_luks[@]}" != 0 ]] && [[ ! -d "${v_temp_path}" ]]; then
        f_check_command "cryptsetup"
        f_mkdir "${v_temp_path}"
        for i in "${a_luks[@]}"; do
          if [[ "${v_dry_run}" == true ]]; then
            f_print_msg "[DRY-RUN] would back up LUKS header of /dev/${i} into ${v_temp_path}/${i}_luksHeaderBackup.img"
          else
            cryptsetup luksHeaderBackup "/dev/${i}" --header-backup-file "${v_temp_path}/${i}_luksHeaderBackup.img"
          fi
        done
        f_backup_done_msg "${v_temp_path}"
      else
        f_backup_skipped_msg "No LUKS or ${v_temp_path}"
      fi
    else
      f_print_msg $'\nBacking up LUKS headers (raw, restorable): disabled, skipping'
    fi
  else
    f_print_msg $'\nSecrets backup: disabled, skipping'
  fi

  ### ENDING ###

  if [[ "${K_DEBUG}" != true ]]; then

    # Create tar archive
    v_filename="${v_backup_name}_${v_hostname}_${v_datetime_suffix}.tar.xz"
    a_tar_extra_sources=()
    if [[ "${v_enable_source_extra}" == true ]]; then
      f_filter_existing_sources a_source_extra a_tar_extra_sources "a_source_extra"
    else
      f_print_msg $'\na_source_extra: disabled, skipping'
    fi
    if [[ "${v_dry_run}" == true ]]; then
      f_print_msg "$(printf '\n[DRY-RUN] would create TAR archive %s in %s' "${v_filename}" "${v_dest}")"
      f_encrypt_archive v_filename "${v_dest}" "${v_gpg_recipient_file}" "${v_enable_gpg_settings}"
      if [[ "${v_tar_owner}" == true ]]; then
        f_print_msg "[DRY-RUN] would change tar archive ownership to user: ${v_username}"
      fi
      f_print_msg "[DRY-RUN] would write checksum: ${v_filename}.sha256"
      f_prune_old_archives "${v_dest}" "${v_backup_name}_${v_hostname}"
    else
      f_print_msg $'\nCreating TAR archive'
      # Exclude the MySQL/PostgreSQL credential files even if they fall
      # inside a_source_extra. Exclude .git too: already on the remote,
      # no need to duplicate it. Also exclude every a_secrets_source/
      # a_secrets_source_extra path regardless of v_enable_secrets_backup:
      # that material only ever belongs in the opt-in secrets archive.
      # Also exclude v_tempdir_secrets/v_dest_secrets themselves
      # unconditionally, in case either falls under a_source_extra.
      a_secrets_exclude_args=()
      for i in "${a_secrets_source[@]}" "${a_secrets_source_extra[@]}"; do
        a_secrets_exclude_args+=(--exclude="${i}")
      done
      # Captures tar's stderr instead of discarding it (2>&1 >/dev/null,
      # in that order, latches stderr onto the command-substitution pipe
      # before stdout is separately discarded): a failure otherwise gave
      # no indication at all of why (permission denied, disk full...).
      f_assert_within_whitelist "${v_dest}/${v_filename}"
      if v_tar_err=$(tar --acls --xattrs --transform="s,^,${v_filename%.tar.xz}/," \
        -cpJf "${v_dest}/${v_filename}" --exclude="${v_dest}" --exclude="${v_mysql_cnf_path}" \
        --exclude="${v_postgresql_pgpass_path}" --exclude="${v_tempdir_secrets}" \
        --exclude="${v_dest_secrets}" \
        --exclude='.git' "${a_secrets_exclude_args[@]}" "${v_tempdir}" "${a_tar_extra_sources[@]}" \
        2>&1 >/dev/null); then
        f_encrypt_archive v_filename "${v_dest}" "${v_gpg_recipient_file}" "${v_enable_gpg_settings}"
        f_assert_within_whitelist "${v_dest}/${v_filename}"
        chmod 600 "${v_dest}/${v_filename}"
        f_print_msg "TAR archive ${v_filename} created in ${v_dest}"
        # Change tar archive ownership to current user
        if [[ "${v_tar_owner}" == true ]]; then
          f_check_command "chown"
          f_print_msg "Changing tar archive ownership to user: ${v_username}"
          f_assert_within_whitelist "${v_dest}/${v_filename}"
          chown "${v_username}":"${v_username}" "${v_dest}/${v_filename}"
        fi
        # SHA-256 checksum sidecar, so integrity can be checked before a
        # real restore. Best-effort: a checksum failure only warns, same
        # philosophy as f_check_pipe. cd runs in the command substitution's
        # own subshell, so the checksum file records just the archive's
        # filename, keeping `sha256sum -c` usable straight from v_dest.
        f_assert_within_whitelist "${v_dest}/${v_filename}.sha256"
        if v_sum_err=$(cd "${v_dest}" && sha256sum "${v_filename}" 2>&1 > "${v_filename}.sha256"); then
          if [[ "${v_tar_owner}" == true ]]; then
            chown "${v_username}":"${v_username}" "${v_dest}/${v_filename}.sha256"
          fi
        else
          f_print_msg "WARNING: failed to write checksum for ${v_filename}: ${v_sum_err}"
        fi
        f_print_msg "Done"
        f_prune_old_archives "${v_dest}" "${v_backup_name}_${v_hostname}"
      else
        printf "\nFailed to create TAR archive %s:\n%s\n\n" "${v_filename}" "${v_tar_err}" >&2
        f_log_msg "Failed to create TAR archive ${v_filename}: ${v_tar_err}"
        exit 1
      fi
    fi

    # Create data TAR archive, if the data-backup pass is enabled
    if [[ "${v_enable_data_backup}" == true ]]; then
      v_filename_data="${v_backup_name}_DATA_${v_hostname}_${v_datetime_suffix}.tar.xz"
      a_tar_extra_data_sources=()
      if [[ "${v_enable_data_source_extra}" == true ]]; then
        f_filter_existing_sources a_data_source_extra a_tar_extra_data_sources "a_data_source_extra"
      else
        f_print_msg $'\na_data_source_extra: disabled, skipping'
      fi
      if [[ "${v_dry_run}" == true ]]; then
        f_print_msg "$(printf '\n[DRY-RUN] would create data TAR archive %s in %s' "${v_filename_data}" "${v_dest_data}")"
        f_encrypt_archive v_filename_data "${v_dest_data}" "${v_gpg_recipient_file_data}" "${v_enable_gpg_data}"
        if [[ "${v_tar_owner}" == true ]]; then
          f_print_msg "[DRY-RUN] would change data tar archive ownership to user: ${v_username}"
        fi
        f_print_msg "[DRY-RUN] would write checksum: ${v_filename_data}.sha256"
        f_prune_old_archives "${v_dest_data}" "${v_backup_name}_DATA_${v_hostname}"
      else
        f_print_msg $'\nCreating data TAR archive'
        # Same secrets exclusion reasoning as the settings archive above:
        # a_data_source_extra could in principle point at /etc or /root too.
        a_secrets_exclude_args=()
        for i in "${a_secrets_source[@]}" "${a_secrets_source_extra[@]}"; do
          a_secrets_exclude_args+=(--exclude="${i}")
        done
        f_assert_within_whitelist "${v_dest_data}/${v_filename_data}"
        if v_tar_err=$(tar --acls --xattrs --transform="s,^,${v_filename_data%.tar.xz}/," \
          -cpJf "${v_dest_data}/${v_filename_data}" --exclude="${v_dest_data}" \
          --exclude="${v_mysql_cnf_path}" --exclude="${v_postgresql_pgpass_path}" \
          --exclude="${v_tempdir_secrets}" \
          --exclude="${v_dest_secrets}" "${a_secrets_exclude_args[@]}" "${v_tempdir_data}" \
          "${a_tar_extra_data_sources[@]}" 2>&1 >/dev/null); then
          f_encrypt_archive v_filename_data "${v_dest_data}" "${v_gpg_recipient_file_data}" "${v_enable_gpg_data}"
          f_assert_within_whitelist "${v_dest_data}/${v_filename_data}"
          chmod 600 "${v_dest_data}/${v_filename_data}"
          f_print_msg "Data TAR archive ${v_filename_data} created in ${v_dest_data}"
          if [[ "${v_tar_owner}" == true ]]; then
            f_check_command "chown"
            f_print_msg "Changing data tar archive ownership to user: ${v_username}"
            f_assert_within_whitelist "${v_dest_data}/${v_filename_data}"
            chown "${v_username}":"${v_username}" "${v_dest_data}/${v_filename_data}"
          fi
          # Same checksum reasoning as the settings archive above.
          f_assert_within_whitelist "${v_dest_data}/${v_filename_data}.sha256"
          if v_sum_err=$(cd "${v_dest_data}" && sha256sum "${v_filename_data}" 2>&1 > "${v_filename_data}.sha256"); then
            if [[ "${v_tar_owner}" == true ]]; then
              chown "${v_username}":"${v_username}" "${v_dest_data}/${v_filename_data}.sha256"
            fi
          else
            f_print_msg "WARNING: failed to write checksum for ${v_filename_data}: ${v_sum_err}"
          fi
          f_print_msg "Done"
          f_prune_old_archives "${v_dest_data}" "${v_backup_name}_DATA_${v_hostname}"
        else
          printf "\nFailed to create data TAR archive %s:\n%s\n\n" "${v_filename_data}" "${v_tar_err}" >&2
          f_log_msg "Failed to create data TAR archive ${v_filename_data}: ${v_tar_err}"
          exit 1
        fi
      fi
    fi

    # Create secrets TAR archive, if the secrets pass is enabled. Unlike
    # the settings/data archives, a_secrets_source/a_secrets_source_extra
    # entries are already copied into v_tempdir_secrets by the SECRETS
    # BACKUP step above, so no separate "extra sources" list here, and
    # deliberately no --exclude for v_mysql_cnf_path/v_postgresql_pgpass_path:
    # this archive exists specifically to hold restore-time credentials.
    if [[ "${v_secrets_active}" == true ]]; then
      v_filename_secrets="${v_backup_name}_SECRETS_${v_hostname}_${v_datetime_suffix}.tar.xz"
      if [[ "${v_dry_run}" == true ]]; then
        f_print_msg "$(printf '\n[DRY-RUN] would create secrets TAR archive %s in %s' "${v_filename_secrets}" "${v_dest_secrets}")"
        f_encrypt_archive v_filename_secrets "${v_dest_secrets}" "${v_gpg_recipient_file_secrets}" "${v_enable_gpg_secrets}"
        if [[ "${v_tar_owner_secrets}" == true ]]; then
          f_print_msg "[DRY-RUN] would change secrets tar archive ownership to user: ${v_username}"
        fi
        f_print_msg "[DRY-RUN] would write checksum: ${v_filename_secrets}.sha256"
        f_prune_old_archives "${v_dest_secrets}" "${v_backup_name}_SECRETS_${v_hostname}"
      else
        f_print_msg $'\nCreating secrets TAR archive'
        f_assert_within_whitelist "${v_dest_secrets}/${v_filename_secrets}"
        if v_tar_err=$(tar --acls --xattrs --transform="s,^,${v_filename_secrets%.tar.xz}/," \
          -cpJf "${v_dest_secrets}/${v_filename_secrets}" \
          --exclude="${v_dest_secrets}" "${v_tempdir_secrets}" 2>&1 >/dev/null); then
          f_encrypt_archive v_filename_secrets "${v_dest_secrets}" "${v_gpg_recipient_file_secrets}" "${v_enable_gpg_secrets}"
          f_assert_within_whitelist "${v_dest_secrets}/${v_filename_secrets}"
          chmod 600 "${v_dest_secrets}/${v_filename_secrets}"
          f_print_msg "Secrets TAR archive ${v_filename_secrets} created in ${v_dest_secrets}"
          if [[ "${v_tar_owner_secrets}" == true ]]; then
            f_check_command "chown"
            f_print_msg "Changing secrets tar archive ownership to user: ${v_username}"
            f_assert_within_whitelist "${v_dest_secrets}/${v_filename_secrets}"
            chown "${v_username}":"${v_username}" "${v_dest_secrets}/${v_filename_secrets}"
          fi
          # Same checksum reasoning as the settings archive above.
          f_assert_within_whitelist "${v_dest_secrets}/${v_filename_secrets}.sha256"
          if v_sum_err=$(cd "${v_dest_secrets}" && sha256sum "${v_filename_secrets}" 2>&1 > "${v_filename_secrets}.sha256"); then
            if [[ "${v_tar_owner_secrets}" == true ]]; then
              chown "${v_username}":"${v_username}" "${v_dest_secrets}/${v_filename_secrets}.sha256"
            fi
          else
            f_print_msg "WARNING: failed to write checksum for ${v_filename_secrets}: ${v_sum_err}"
          fi
          f_print_msg "Done"
          f_prune_old_archives "${v_dest_secrets}" "${v_backup_name}_SECRETS_${v_hostname}"
        else
          printf "\nFailed to create secrets TAR archive %s:\n%s\n\n" "${v_filename_secrets}" "${v_tar_err}" >&2
          f_log_msg "Failed to create secrets TAR archive ${v_filename_secrets}: ${v_tar_err}"
          exit 1
        fi
      fi
    fi

    # Remote rsync $dest directory
    f_print_msg $'\nSynchronizing backup directory'
    if [[ "${v_enable_rsync}" != true ]]; then
      f_print_msg "v_enable_rsync: disabled, skipping"
    elif [[ -n "${v_dest_rsync}" ]]; then
      if [[ "${v_dry_run}" == true ]]; then
        f_print_msg "[DRY-RUN] would rsync ${v_dest} with ${v_dest_rsync}"
      else
        f_check_command "rsync"
        f_print_msg "rsync ${v_dest} with ${v_dest_rsync}"
        # Only the source is checked: v_dest_rsync can be a remote spec
        # (user@host:/path), which readlink -f cannot meaningfully resolve.
        f_assert_within_whitelist "${v_dest}"
        if rsync -arq -AX --delete --force -- "${v_dest}" "${v_dest_rsync}"; then
          f_print_msg "Done"
        else
          printf "\nFailed to synchronize %s with %s\n\n" "${v_dest}" "${v_dest_rsync}" >&2
          f_log_msg "Failed to synchronize ${v_dest} with ${v_dest_rsync}"
        fi
      fi
    else
      f_print_msg "No rsync destination configured"
      f_print_msg "Skipped"
    fi

    # Remove $workdir directory (and $workdir_data/$workdir_secrets, if
    # the data/secrets passes are enabled)
    if [[ "${v_dry_run}" == true ]]; then
      f_print_msg "[DRY-RUN] nothing to delete: ${v_tempdir} was never created"
    elif [[ "${v_quiet}" == false ]]; then
      printf "\nYou can now delete the temporary directory %s" "${v_tempdir}"
      if [[ "${v_enable_data_backup}" == true ]]; then
        printf " (and the data workdir %s)" "${v_tempdir_data}"
      fi
      if [[ "${v_secrets_active}" == true ]]; then
        printf " (and the secrets workdir %s)" "${v_tempdir_secrets}"
      fi
      v_msg="Do you really want to delete it? ([Y]es/[N]o/[C]ancel, no default, type it out)? "
      f_ask_confirmation "${v_msg}" "delete"
    elif [[ "${v_quiet}" == true ]] && [[ "${v_keep_tempdir}" == false ]]; then
      f_assert_within_whitelist "${v_tempdir}"
      rm -rf "${v_tempdir}"
      if [[ "${v_enable_data_backup}" == true ]]; then
        f_assert_within_whitelist "${v_tempdir_data}"
        rm -rf "${v_tempdir_data}"
      fi
      if [[ "${v_secrets_active}" == true ]]; then
        f_assert_within_whitelist "${v_tempdir_secrets}"
        rm -rf "${v_tempdir_secrets}"
      fi
    fi

  fi

  # Execute post command (skipped in dry-run: arbitrary user command, not
  # guaranteed to be read-only)
  if [[ "${v_enable_post_command}" != true ]]; then
    f_print_msg $'\nv_enable_post_command: disabled, skipping'
  elif [[ -n "${v_post_command}" ]]; then
    export NDM_HOSTNAME="${v_hostname}"
    export NDM_ARCHIVE_PREFIX="${v_backup_name}"
    export NDM_LOG_PATH="${v_log_path:-}"
    export NDM_USER="${v_username}"
    export NDM_EXIT_CODE=0
    export NDM_SETTINGS_ARCHIVE="" NDM_SETTINGS_ARCHIVE_SIZE=""
    export NDM_DATA_ARCHIVE="" NDM_DATA_ARCHIVE_SIZE=""
    export NDM_SECRETS_ARCHIVE="" NDM_SECRETS_ARCHIVE_SIZE=""
    if [[ -n "${v_filename:-}" ]]; then
      NDM_SETTINGS_ARCHIVE="${v_dest}/${v_filename}"
      NDM_SETTINGS_ARCHIVE_SIZE="$(f_human_size "${NDM_SETTINGS_ARCHIVE}")"
    fi
    if [[ -n "${v_filename_data:-}" ]]; then
      NDM_DATA_ARCHIVE="${v_dest_data}/${v_filename_data}"
      NDM_DATA_ARCHIVE_SIZE="$(f_human_size "${NDM_DATA_ARCHIVE}")"
    fi
    if [[ -n "${v_filename_secrets:-}" ]]; then
      NDM_SECRETS_ARCHIVE="${v_dest_secrets}/${v_filename_secrets}"
      NDM_SECRETS_ARCHIVE_SIZE="$(f_human_size "${NDM_SECRETS_ARCHIVE}")"
    fi
    if [[ "${v_dry_run}" == true ]]; then
      f_print_msg $'\n[DRY-RUN] would execute post command: '"${v_post_command}"
    else
      f_print_msg $'\nExecuting post command'
      eval "${v_post_command}"
    fi
  fi

  # All Done. Unconditional printf (not f_print_msg): the final result
  # must stay visible even in --quiet, same reasoning as the
  # missing-packages notice above -- quiet means no chatter, not no idea
  # whether it worked or where the output landed.
  if [[ "${v_dry_run}" == true ]]; then
    v_msg="Dry run completed. Nothing was created, modified, or deleted on this system."
    printf "\n%s\n" "${v_msg}"
    f_log_msg "${v_msg}"
  else
    printf "\nAll done.\n"
    f_log_msg "All done."
    if [[ -n "${v_filename:-}" ]]; then
      v_msg="  Settings archive: ${v_dest}/${v_filename} ($(f_human_size "${v_dest}/${v_filename}"))"
      printf "%s\n" "${v_msg}"
      f_log_msg "${v_msg}"
    fi
    if [[ -n "${v_filename_data:-}" ]]; then
      v_msg="  Data archive:     ${v_dest_data}/${v_filename_data} ($(f_human_size "${v_dest_data}/${v_filename_data}"))"
      printf "%s\n" "${v_msg}"
      f_log_msg "${v_msg}"
    fi
    if [[ -n "${v_filename_secrets:-}" ]]; then
      v_msg="  Secrets archive:  ${v_dest_secrets}/${v_filename_secrets} ($(f_human_size "${v_dest_secrets}/${v_filename_secrets}"))"
      printf "%s\n" "${v_msg}"
      f_log_msg "${v_msg}"
    fi
  fi
  printf "\n"
  exit 0
}


########################
# ENTRY POINT
########################


f_parse_arguments "${@}"
if [[ "${v_start}" == true ]] || [[ "${v_analyze}" == true ]] || [[ "${v_requirements}" == true ]]; then
  if [[ -n "${v_config_error}" ]]; then
    printf 'Invalid setting in %s: %s
' "${v_config_path}" "${v_config_error}" >&2
    exit 2
  fi
  if [[ "${v_requirements}" == true ]]; then
    f_requirements
  else
    main "${@}"
  fi
fi

exit 0
