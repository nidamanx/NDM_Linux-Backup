# Security Policy

## Supported versions

Only the latest release receives fixes.

| Version | Supported |
| ------- | --------- |
| latest  | yes       |
| older   | no        |

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub's private reporting instead: open the **Security** tab of this
repository and click **Report a vulnerability**. You will get a private
channel with the maintainer.

Useful details to include:

- script version (`./ndm_linux-backup.sh --version`) and the output of
  `sudo ./ndm_linux-backup.sh --analyze`;
- Linux distribution and version (`lsb_release --all`);
- steps to reproduce, on a throw-away test machine or VM, never with real
  credentials or real backup archives: they contain system configuration and,
  with the secrets archive, private keys and password hashes;
- the impact you expect (for example "command injection" or "a secret written
  into the settings archive").

## What is in scope

- Unsafe handling of command-line options or of the settings file
  `ndm_linux-backup.conf` (code execution, injection, writing outside the
  configured working and destination directories). The settings file must only
  be read, never executed: anything in it that runs, other than the three hook
  commands (`v_pre_command`, `v_post_command`, `v_on_failure_command`) when their
  own switch is on, is in scope.
- Secrets-archive material (SSH host keys, TLS private keys, `/etc/shadow`,
  credentials) ending up in the settings or data archive.
- Archives, logs, working directories or credential files created with
  permissions that let other local users read them.
- GPG encryption leaving a plaintext archive behind without saying so, or
  encrypting to a key other than the configured one.
- `--dry-run` or `--analyze` creating, changing or deleting anything.
- Retention deleting files that the script did not create.

## What is out of scope

- The content of the archives once created: protecting them, and the
  destination they are copied to, is up to you (see the Encryption section of
  the README).
- Commands you configure yourself (`v_pre_command`, `v_post_command`,
  `v_on_failure_command`): they run as root by design, once their switch is on.
- Vulnerabilities in the tools the script calls (tar, rsync, gpg, mysqldump,
  pg_dump, docker, podman, ...).

## Disclosure

This is a personal project maintained on a best-effort basis. Reports are
acknowledged as soon as reasonably possible and fixes are released before any
public disclosure.
