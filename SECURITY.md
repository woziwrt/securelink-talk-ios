# Security policy – SecureLink Talk

SecureLink Talk (iOS app `cc.securelink.talk`, Android app, and the server installer) is made by
**Securelink s.r.o.** (Czech Republic). This file says how to report a vulnerability and what we do with it.

## Reporting a vulnerability

- E-mail **support@securelink.cz** with the subject starting with **`SECURITY:`**.
- Please include: the affected product and version (App Store build number, Android version, or server installer
  commit), what an attacker can do, and how to reproduce it.
- Please do not open a public issue for a vulnerability and do not test against servers of our customers. Use your
  own installation (`securelink/BUILD.md`, server installer) or ask us for a test account.

## What happens next

| step | when |
|---|---|
| we confirm that we received your report | within 3 working days |
| first assessment (is it real, how severe, which versions) | within 10 working days |
| fix released, or a plan agreed with you | as soon as possible; for critical issues we aim for days, not weeks |
| public disclosure | coordinated with you, at the latest 90 days after the report unless agreed otherwise |

We credit reporters in the release notes unless they prefer to stay anonymous.

Vulnerabilities in components we take from upstream (Linphone SDK, Flexisip, lime-server, Mbed TLS, Kamailio, …)
are forwarded to their maintainers; we ship the fix as soon as it is available.

Actively exploited vulnerabilities and severe incidents are reported to the authorities as required by the
EU Cyber Resilience Act (Regulation (EU) 2024/2847, Article 14).

## Supported versions

| product | supported |
|---|---|
| iOS app | the current App Store version and the current TestFlight build |
| Android app | the current release |
| server | installations updated with the current installer |

Older versions get no fixes – please update.

## How it is protected

[`securelink/SECURITY-DESIGN.md`](securelink/SECURITY-DESIGN.md) (Czech: [`SECURITY-DESIGN.cs.md`](securelink/SECURITY-DESIGN.cs.md))
describes the encryption, what the server can and cannot see, the protection on the phone and the limits. The server
installer is public too: https://github.com/woziwrt/securelink-server

## What is in the app

The list of components and their versions is in [`securelink/SBOM.md`](securelink/SBOM.md);
licences in [`securelink/THIRD-PARTY-LICENSES.md`](securelink/THIRD-PARTY-LICENSES.md).
The exact source of every App Store build is tagged `build-N` in this repository.
