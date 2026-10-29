# Changelog

All notable changes to NDM Linux Backup are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0] - 2026-10-29

First release on GitHub. NDM Linux Backup is a rework of NDM Backup, published on GitLab
up to version 2.0.10 (<https://gitlab.com/nidamanx/ndm-backup>, where the changelog of
those versions remains). This release renames the project and its files, makes the
settings file safe (it is now only read, never executed) and aligns the command line
with the author's other projects. What gets backed up does not change.

### Added

- `--requirements`: shows the tools your settings need, which ones are missing and the
  `apt-get` command to install them. It needs no root.
- `--version` also shows the description, author, license and disclaimer; `--help` also
  describes the settings file, the output files and the exit codes.
- An invalid settings file is reported with the line that is wrong.
- The `--analyze` report starts with the name and version of the script.

### Changed

- Project renamed from NDM Backup to **NDM Linux Backup**, now hosted at
  <https://github.com/nidamanx/NDM_Linux-Backup>.
- The script is now `ndm_linux-backup.sh` (was `ndm_backup.sh`); the suggested symlink
  in `PATH` is `ndm_linux-backup` (was `ndm_backup`).
- The settings file is now `ndm_linux-backup.conf` (was `ndm_backup.conf`), and it is
  read as `KEY=value` lines instead of being run as a Bash script. Only the settings of
  the CONFIGURE section are accepted, each value is checked (true/false, number,
  absolute path...), lists are written as `KEY=( "a" "b" )`, and values are literal:
  `$HOME`, `$(...)` and backticks are refused, except in the three hook commands. An
  unknown setting or an invalid value stops the script with exit code 2. **Upgrading:**
  rename `ndm_backup.conf` to `ndm_linux-backup.conf`, write full paths instead of
  `${HOME}`, and remove anything that is not a setting; the script names the line to
  fix.
- `v_datetime_suffix` is replaced by `v_datetime_format`, a `date` format. Archive,
  checksum and log names now end with `YYYYMMDD-HHMMSS` (e.g.
  `ndm_linux-backup_myhost_20261029-031500.tar.xz`), was
  `<weekday number>-<weekday>_YYYY-MM-DD_HH-MM-SS`. To keep the old names set
  `v_datetime_format='%w-%a_%Y-%m-%d_%H-%M-%S'`.
- Exit codes: invalid command-line usage (unknown option, unexpected argument, `-n`,
  `-q`, `-k` or `--secrets` without `--start` or `--analyze`) and an invalid setting now
  exit with 2 (was 1, or 0 with the usage shown); SIGTERM now exits with 143 (was 130).
- New defaults that follow the new name: archives are named
  `ndm_linux-backup_<host>_<YYYYMMDD>-<HHMMSS>.tar.xz` (`v_backup_name`, was `NDM_BK`),
  and the working directories are under `/home/ndm_linux-backup/` (was
  `/home/ndm_backup/`, which can be deleted after upgrading). Retention only deletes
  archives with the current name: to keep the old names, and their retention, set
  `v_backup_name=NDM_BK`.
- The hook commands get `NDM_ARCHIVE_PREFIX` (was `NDM_BACKUP_NAME`): the value of
  `v_backup_name`.
- Archives are created with mode 600 (was 700: an archive is not a program). Messages
  that point to a setting now name `ndm_linux-backup.conf` too, not only CONFIGURE.
- Example files renamed: `ndm_linux-backup.conf.example`, `my.cnf.example`,
  `pgpass.example` (were `*.template`).
- The default destination folder `backup/`, next to the script, is now part of the
  repository (empty: archives, logs and checksums written there are never versioned).

### Removed

- `v_config_path`: the settings file is always `ndm_linux-backup.conf` next to the
  script (its real location).

### Security

- The settings file can no longer run code as root: it was sourced as a Bash script, so
  anyone able to write to it could run any command at the next backup.

[Unreleased]: https://github.com/nidamanx/NDM_Linux-Backup/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/nidamanx/NDM_Linux-Backup/releases/tag/v3.0.0
