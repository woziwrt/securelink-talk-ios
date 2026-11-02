# How SecureLink Talk protects calls and messages

How SecureLink Talk protects calls and messages, what the server can and cannot see, and where the limits are.
State of 2 November 2026 (iOS 1.1 build 31 – submitted for review; **version 1.0 in the App Store does not have these changes yet**; Android `67b29a3ca`, server installer v2 – customer servers are being moved to v2). Czech version: [`SECURITY-DESIGN.cs.md`](SECURITY-DESIGN.cs.md). Components and versions: [`SBOM.md`](SBOM.md).
Reporting vulnerabilities: [`../SECURITY.md`](../SECURITY.md). Every App Store build is tagged `build-N` in this
repository and can be rebuilt with [`BUILD.md`](BUILD.md).

SecureLink has not had an independent audit. Everything is public instead (GPL v3), so every statement here can be
checked: the iOS app (github.com/woziwrt/securelink-talk-ios), the Android app (github.com/woziwrt/securelink-android)
and the server installer (github.com/woziwrt/securelink-server).

## 1. Model: a closed circle on the customer's own server

- Each customer (a company) runs **its own server** (a VPS rented in the customer's name). One server is one **circle**:
  accounts exist only when the circle's administrator creates them. Nobody can register from outside, and there is
  no public directory, no phone-number discovery and no federation with other servers.
- An account joins a phone with an **invitation**: a link plus a 6-digit code sent another way (phone, SMS, in person),
  valid 48 hours, 5 attempts; a new invitation cancels the older ones. The administrator can also hand over a single-use QR
  code (7 days). Profiles are fetched only over HTTPS from a server whose certificate our CA signed.
- A phone can hold accounts of **several circles** (e.g. an administrator of several companies), only when **both** circles
  allow it – the administrator switches it in the web console (`allow_other_circles`).
- Upstream components: Linphone SDK 5.5.29 (Belledonne Communications), Flexisip 2.6 (SIP proxy, push gateway,
  conference server for chats), lime-server (key server for messages), Kamailio 6.0 in front of Flexisip.

## 2. Calls

- Signalling: SIP over **TLS 1.3** (Mbed TLS 3.6.7) to the customer's server; the server certificate must be signed by
  the SecureLink CA built into the app (one CA for all circles; its key is being moved offline).
- Key agreement: **ZRTP** between the two phones with a **hybrid X448 + ML-KEM-1024** key exchange (ZRTP key agreement
  `X3M3`; seen on the wire in the ZRTP Commit as `S512/AES3/GCM/X3M3/B32`). The server is not part of the key agreement.
- Voice: SRTP with **AES-256-GCM**. The media relay on the server forwards encrypted packets only.
- The apps themselves allow only ZRTP and only the post-quantum hybrid key agreements (X448 + ML-KEM-1024, X25519 +
  ML-KEM-512), whatever the server's profile says – a compromised server cannot downgrade a call to a classic exchange.
- **Security word** (ZRTP short authentication string): both people read it aloud and confirm it. A man in the middle
  – including a compromised server – would produce different words. Confirmation is remembered per contact.

## 3. Messages

- End-to-end encryption with **LIME** (Belledonne's X3DH + Double Ratchet, AES-256-GCM per message).
- Key agreement per circle: **X448 + ML-KEM-1024** (`c448mlk1024`, lime-server branch `release/1.3`, which Belledonne
  still calls beta) together with **X25519 + Kyber-512** (`c25519k512`). The About screen of the app shows what the
  current circle uses.
- Each device has its own identity key; a new device of a contact is shown in the conversation ("new, unverified device").
- **Encryption cannot be switched off.** Plain chats are refused in the app's own code (iOS `SecureLinkAdmin.enforceEncryption`,
  Android `enforceEncryptedMessaging`), not only by the server profile. Tested on 2 November 2026 by injecting a
  plain SIP MESSAGE straight into Flexisip (simulating a compromised server): the phone refused it, its text was not shown
  anywhere and the push said only "New message".
- Push notifications (Apple / Google) carry **no message content and no sender name** – only a wake-up for the app.
  The notification on the phone says only "SecureLink – Message received" (no sender, no text; missed calls without
  the caller's name). The notification data keeps the conversation's address (a tap opens the right conversation); the
  emergency PIN removes delivered notifications.
- Disappearing messages are on by default (one week) in every conversation.

## 4. What the server sees – and what it does not

| the server operator **can** see | the server operator **cannot** see |
|---|---|
| the list of accounts and their display names | the content of messages and attachments (end-to-end encrypted) |
| IP addresses of connected phones, registration times | what is said in calls (keys agreed only between the phones) |
| who calls whom and when (signalling) | the phones' local databases |
| which accounts have a conversation together (chat server) | the security word |
| sizes and times of encrypted messages | |

Limits we keep small:
- A **nightly cleanup** deletes conversations of deleted accounts and leftover records from the chat server
  (`securelink-metadata-cleanup`). Live conversations stay: removing them breaks message delivery in the current
  Linphone SDK.
- Release builds log **errors only** (from iOS build 29 / Android `efa66e48d`). Earlier builds logged in detail, including
  the downloaded profile with the account's password; the update removes those log files once. Logs stay on the phone.

## 5. On the phone

- **Lock:** the app locks with Face ID / fingerprint / the phone's screen lock after 30 seconds in the background
  and after 5 minutes without a touch.
- **SecureLink PIN (optional):** an app PIN instead of the phone lock, plus an **emergency PIN**. Entering the
  emergency PIN deletes every account with its data (conversations, contacts, call history, LIME identity), the logs and
  the app's settings, switches the PIN off and shows an empty app. It works also while the PIN pad is blocked after
  wrong attempts. It does not hide that the app was installed and used. Only salted PBKDF2-SHA256 hashes of the PINs are
  stored (iOS Keychain, this device only; Android preferences encrypted with a key in the Android Keystore).
- **Local data at rest:**
  - iOS: the app's files are protected by iOS Data Protection (per-file keys; default class, available after the first
    unlock). Deleting a file discards its key, so deleted data cannot be recovered from the flash memory.
  - Android: new installations keep all databases and the configuration encrypted with **AES-256-GCM** (bctoolbox
    encrypted file system, key in the Android Keystore). The emergency PIN destroys that key. Installations from
    before 2 November 2026 keep unencrypted databases (protected by Android file-based encryption) until reinstalled.
- **The account's credential** (the SIP digest, `ha1`) is kept in the app's configuration on the phone: encrypted with a
  key in the Android Keystore (Android, new installations), protected by iOS Data Protection and excluded from backups
  (iOS). Moving it to the Keychain would add nothing – forensic tools extract the Keychain from a phone unlocked since
  boot just as they extract files. What protects it: the administrator blocks the account on the server and the
  credential stops working at once; the emergency PIN deletes it.
- While the app is locked, its content is hidden also from window dumps and accessibility (Android). Android forbids
  screenshots and screen recording of the app; iOS cannot forbid screenshots, but covers the app while the screen is
  recorded, mirrored or shared.
- No analytics, no crash reporting, no advertising identifiers. Android uses Firebase Cloud Messaging for push only
  (Crashlytics is switched off at build time); the iOS app contains no Firebase at all.

## 6. Administration and support access

- The circle's administrator manages accounts in a web console on the customer's server (HTTPS with a client certificate,
  plus a password of its own on every server).
- Support can reach the server only with **SSH keys made for that one customer** (each under its own name – the login
  record shows who it was).
  There is no universal key for all customers. The customer can **switch support access off** in the web console at any time.
- Server backups are encrypted with **age** for the support partner's backup key and, when the customer wants it, also for
  the customer's own key.
- The administrator can block an account at once on the server (its password and message keys stop working) and **wipe it
  remotely**: the phone deletes the account and its data when it next connects.

## 7. What SecureLink does not protect against

- A phone that is already compromised (malware with system rights, an unlocked phone in someone else's hands).
- Metadata listed in section 4 for whoever controls the server (the customer, and support with the customer's consent).
- The fact that a push was sent, visible to Apple / Google (not its content).
- A targeted state-level investigation of a particular person. This is beyond what any app alone can promise.
- Post-quantum protection of messages relies on lime-server `release/1.3`, which Belledonne has not yet released as stable.
