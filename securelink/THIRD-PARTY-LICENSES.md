# Third-party components and licences

SecureLink Talk is a modified version of linphone-iphone (GPLv3) and is distributed under the **GNU GPL v3**.
The complete source code of every App Store version is public (see `README.md`, `securelink/BUILD.md`).
This list covers what is actually built into the app (iOS SDK build flags in `securelink/BUILD.md`; no video,
no analytics, no crash reporting – the Firebase/Crashlytics code of upstream Linphone is not compiled in).

## Linphone SDK (Belledonne Communications)
| component | licence |
|---|---|
| liblinphone, mediastreamer2, ortp | GNU AGPL v3 |
| bctoolbox, belle-sip, belr, belcard, lime, bzrtp, postquantumcryptoengine, bcmatroska2 | GNU GPL v3 |

## Libraries built into the SDK
| component | licence |
|---|---|
| liboqs (post-quantum algorithms) | MIT |
| decaf (X448) | public domain / MIT |
| Mbed TLS | Apache 2.0 |
| libsrtp2 | BSD 3-clause |
| Opus | BSD 3-clause |
| Speex, SpeexDSP | BSD 3-clause |
| GSM 06.10 | permissive (Jutta Degener, Carsten Bormann, TU Berlin) |
| BroadVoice16 | BSD-style (Broadcom) |
| WebRTC echo canceller / VAD (mswebrtc) | BSD 3-clause |
| JsonCpp | public domain / MIT |
| Xerces-C++ | Apache 2.0 |
| SOCI | Boost Software License 1.0 |
| SQLite | public domain |
| OpenLDAP (client library) | OpenLDAP Public License 2.8 |
| libxml2 | MIT |
| zlib | zlib licence |

## Swift packages
| package | licence |
|---|---|
| AppAuth-iOS 2.0.0 | Apache 2.0 |
| Elegant-Emoji-Picker | MIT |

Empty placeholder frameworks of optional codecs (`msamr`, `mscodec2`, `msopenh264`) contain no codec code.
