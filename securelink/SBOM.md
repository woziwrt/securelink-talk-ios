# Software bill of materials – SecureLink Talk v2

What the iOS app and the server consist of, with versions (state of 2 November 2026, v2: Mbed TLS 3.6.7,
ML-KEM-1024 for messages). Licences: `THIRD-PARTY-LICENSES.md`. Build: `BUILD.md`.
Update this file with every App Store build and every installer change of a component.

## iOS app

| component | version | note |
|---|---|---|
| SecureLink Talk (modified linphone-iphone) | version 1.1, build 29 (for review) | this repository, tag `build-29` |
| linphone-sdk (liblinphone, mediastreamer2, ortp, belle-sip, bctoolbox, bzrtp, lime, postquantumcryptoengine, belr, belcard) | 5.5.29 (`80bf7c1d`) + `linphone-sdk-5.5.29-*.patch` | built from source, `BUILD.md` |
| bcmatroska2 | 5.4.126 | |
| Mbed TLS | 3.6.7 (`068ff080`) + Belledonne commits + `mbedtls-3.6.7/0001–0009` | TLS 1.3 to the server |
| liboqs | `e219b1a6` (submodule of linphone-sdk 5.5.29) | ML-KEM / Kyber |
| decaf | `e5cc624` (v1.0.2+20) | X448 |
| libsrtp2 | as shipped with linphone-sdk 5.5.29 | SRTP (AEAD_AES_256_GCM negotiated by ZRTP) |
| Opus | `f86ad14b` | |
| Speex, SpeexDSP | linphone-sdk 5.5.29 (branch `linphone`) | |
| GSM 06.10, BroadVoice16, mswebrtc | as shipped with linphone-sdk 5.5.29 | |
| SQLite | linphone-sdk 5.5.29 (branch `master` of its submodule) | |
| SOCI | linphone-sdk 5.5.29 (branch `bc`) | |
| Xerces-C++ | linphone-sdk 5.5.29 (branch `bc`) | |
| JsonCpp | `dadce78` (1.9.0+178) | |
| libxml2 | `d6131eb3` (2.9.8+193) | |
| zlib | `446edd4` (1.2.13+9) | |
| OpenLDAP client library | as shipped with linphone-sdk 5.5.29 | |
| AppAuth-iOS | 2.0.0 | Swift package |
| Elegant-Emoji-Picker | `598ff0a7` | Swift package |

Not built in: video codecs (VP8, H.264, AV1), Firebase / Crashlytics, analytics.

## Server (installed by the SecureLink installer on the customer's VPS)

| component | version | source |
|---|---|---|
| Debian | 13 (customer servers), 12 (lab) | Debian |
| Flexisip | 2.6.2-1 (`bc-flexisip`) | Belledonne Debian repository |
| lime-server | `7e769ca` (branch `release/1.3`, ML-KEM-1024) | Belledonne git |
| Kamailio | 6.0.x | deb.kamailio.org (key `E79ACECB…508EA4C8`) |
| Apache, PHP, MariaDB | Debian packages of the server's release | Debian security updates |
| HAProxy | Debian package (servers where SIP and HTTPS share port 443) | Debian security updates |
| media relay | part of Flexisip | – |
| SecureLink scripts (`securelink-user`, admin web, robot, metadata cleanup) | installer commit | own code |
