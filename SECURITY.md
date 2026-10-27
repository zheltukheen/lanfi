# Security Policy

## Supported versions

Security fixes are applied to the latest release on `main`.

## Reporting a vulnerability

Please **do not** open a public issue for a security vulnerability. Use GitHub's
private vulnerability reporting:

<https://github.com/zheltukheen/lanfi/security/advisories/new>

Include:

- affected version and macOS version;
- steps to reproduce;
- impact (for example: crash, data exposure, privilege boundary);
- a proof of concept if available.

You can expect an acknowledgement within 72 hours and a coordinated disclosure
timeline. LanFi has no server component and collects no telemetry, so most
reports will concern local parsing, file export, or macOS permissions.

## Scope

In scope: the LanFi application, build scripts and GitHub workflows in this
repository. Out of scope: vulnerabilities in macOS, CoreWLAN, Xcode, or
third-party services used by GitHub.
