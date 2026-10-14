# Building SecureLink Talk for iOS

SecureLink Talk is built from two sources:

1. **This repository** (branch `securelink`): a modified [linphone-iphone](https://gitlab.linphone.org/BC/public/linphone-iphone).
   Every App Store / TestFlight build has a tag `build-<number>` that points to its exact source.
2. **linphone-sdk 5.5.29** (commit `80bf7c1d269a185dbe30248271c6590887637e4f`), built with the post-quantum
   engine. The public Swift package of linphone-sdk does not contain it, so the SDK is built locally.

## 1. linphone-sdk

```sh
git clone --recursive https://gitlab.linphone.org/BC/public/linphone-sdk.git linphone-sdk-src
cd linphone-sdk-src
git checkout 80bf7c1d269a185dbe30248271c6590887637e4f
git submodule update --init --recursive
git apply ../linphone-iphone/securelink/linphone-sdk-5.5.29-developer-dir.patch
cmake --preset=ios-sdk -G Ninja -B build-ios \
  -DLINPHONESDK_IOS_ARCHS=arm64 -DLINPHONESDK_IOS_PLATFORM=Iphone \
  -DENABLE_PQCRYPTO=ON -DENABLE_NON_FREE_FEATURES=ON -DENABLE_VIDEO=OFF
cmake --build build-ios
```

- The patch passes `DEVELOPER_DIR` to the per-architecture build, which runs under `env -i`
  (without it `xcrun` fails when `xcode-select` points to the Command Line Tools).
- `ENABLE_NON_FREE_FEATURES=ON` is required by the build system for `ENABLE_PQCRYPTO`. With video off it adds
  no patent-encumbered codec (the audio codecs in the build are Opus, Speex, GSM and BV16).
- The post-quantum engine (`postquantumcryptoengine`) is GPLv3, liboqs is MIT.
- A Python 3 with `pystache` is needed (`-DPython3_EXECUTABLE=…` if it is not the default one).

The result is the Swift package `build-ios/linphone-sdk-swift-ios`.

## 2. The app

Clone this repository next to `linphone-sdk-src` (the Xcode project refers to
`../linphone-sdk-src/build-ios/linphone-sdk-swift-ios`) and build the `Linphone` scheme:

```sh
xcodebuild -project LinphoneApp.xcodeproj -scheme Linphone -configuration Release \
  -destination generic/platform=iOS DEVELOPMENT_TEAM=<your team> build
```

To install it on your own devices, change the bundle identifiers (`cc.securelink.talk` and its extensions)
and the App Group to ones of your own team.

## What the app connects to

The app has no server built in for users to sign up on. A phone is set up by scanning a QR code from a
SecureLink server (`https://…securelink.cc` only); the server runs unmodified Flexisip and lime-server.
`Linphone/Ressources/securelink-ca.pem` is the only certificate authority the app trusts for SIP over TLS.
