/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (c) 2026 Petr Wozniak <petr.wozniak@gmail.com>
 *
 * This file is part of SecureLink, a modified version of linphone-iphone.
 */

import Foundation
import CryptoKit
import linphonesw

/// One phone, two servers (two employers, navrhy/DVA-SERVERY-JEDEN-TELEFON.md; as SecureLinkAccounts.kt on Android):
/// a sign-in link from a second server adds an account next to the first one instead of overwriting it. Remote
/// provisioning cannot do that – the profile always writes proxy_0 – so the app downloads the profile itself and builds
/// the account through the API. The server's own values (directory, uploads, support…) travel in the profile's
/// securelink_account section and stay with the account.
enum SecureLinkAccounts {
	private static let section = "securelink_account"
	private static let paramPrefix = "sl_"
	private static let keys = ["domain", "org_name", "dir_url", "upload_url", "admin_uri", "support_email", "privacy_url",
							   "terms_url", "request_url"]

	/// debug and TestFlight builds only until the whole feature is done; the App Store app keeps one account
	static var enabled: Bool {
		#if DEBUG
		return true
		#else
		return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
		#endif
	}

	/// the server value [key] of the account (securelink_account in its profile), "" when it has none
	static func setting(_ account: Account?, _ key: String) -> String {
		return account?.params?.getCustomParam(key: paramPrefix + key) ?? ""
	}

	/// more than one server: directories are downloaded by the app (liblinphone cannot pick the right password)
	static func isMultiServer(_ core: Core) -> Bool {
		return core.accountList.count > 1
	}

	/// the account of the server [remote] belongs to (each server knows only its own people), else the default one
	static func accountFor(_ core: Core, _ remote: Address?) -> Account? {
		return core.accountList.first { $0.params?.identityAddress?.domain == remote?.domain } ?? core.defaultAccount
	}

	/// liblinphone leaves no default account when the default one is removed (sign-out, a new invitation of the same
	/// server) and remembers that (default_proxy=-1): Messages then stay empty. The first remaining account takes over.
	static func ensureDefaultAccount(_ core: Core) {
		let current = core.defaultAccount?.params?.identityAddress
		if let current = current, core.accountList.contains(where: { $0.params?.identityAddress?.weakEqual(address2: current) == true }) {
			return
		}
		guard let first = core.accountList.first else { return }
		Log.warn("[SecureLink Accounts] no default account, \(first.params?.identityAddress?.asStringUriOnly() ?? "") takes over")
		core.defaultAccount = first
		DispatchQueue.main.async {
			NotificationCenter.default.post(name: NSNotification.Name("DefaultAccountChanged"), object: nil)
		}
	}

	/// the domain whose people a directory list holds – nil with one server (the directory then replaces everybody)
	static func directoryDomain(_ list: FriendList) -> String? {
		guard let core = list.core, isMultiServer(core), let uri = list.uri, !uri.isEmpty else { return nil }
		return core.accountList.first { setting($0, "dir_url") == uri }?.params?.identityAddress?.domain
	}

	/// the conversations of all accounts, newest first – two servers (two employers) are one list, the name says the company
	static func chatRooms(_ core: Core, filter: String) -> [ChatRoom] {
		return core.accountList.flatMap { $0.filterChatRooms(filter: filter) }.sorted { $0.lastUpdateTime > $1.lastUpdateTime }
	}

	/// a conversation of one of this phone's accounts (Linphone lists only the default account's; with two servers both)
	static func isListed(_ core: Core, _ room: ChatRoom) -> Bool {
		guard let local = room.localAddress else { return false }
		return core.accountList.contains { $0.params?.identityAddress?.weakEqual(address2: local) == true }
	}

	/// the upload server is one for the whole core: before sending, point it at the server of [room]'s account
	static func useUploadServerOf(_ core: Core, _ room: ChatRoom) {
		let url = setting(room.account, "upload_url")
		if !url.isEmpty && core.fileTransferServer != url {
			Log.info("[SecureLink Accounts] attachments now go to \(url)")
			core.fileTransferServer = url
		}
	}

	/// downloads the profile behind a sign-in link and adds (or, for the same server, replaces) its account
	static func addFromProvisioning(_ link: String, done: @escaping (Bool) -> Void) {
		guard let url = URL(string: link) else {
			done(false)
			return
		}
		session.dataTask(with: URLRequest(url: url, timeoutInterval: 30)) { data, response, error in
			let code = (response as? HTTPURLResponse)?.statusCode ?? 0
			let xml = code == 200 ? data.flatMap { String(data: $0, encoding: .utf8) } : nil
			if xml == nil { Log.error("[SecureLink Accounts] downloading the profile failed: \(code) \(String(describing: error))") }
			CoreContext.shared.doOnCoreQueue { core in
				let added = xml.map { addAccount(core, $0) } ?? false
				DispatchQueue.main.async { done(added) }
			}
		}.resume()
	}

	private static func addAccount(_ core: Core, _ xml: String) -> Bool {
		guard let profile = try? Factory.Instance.createConfigFromString(data: ""), (try? profile.loadFromXmlString(buffer: xml)) != nil,
			  profile.hasSection(section: "proxy_0") != 0 else {
			Log.error("[SecureLink Accounts] the sign-in link brought no account (expired or already used)")
			return false
		}
		let factory = Factory.Instance
		guard let identity = try? factory.createAddress(addr: profile.getString(section: "proxy_0", key: "reg_identity", defaultString: "")),
			  let server = try? factory.createAddress(addr: profile.getString(section: "proxy_0", key: "reg_proxy", defaultString: "")),
			  let username = Optional(profile.getString(section: "auth_info_0", key: "username", defaultString: "")), !username.isEmpty,
			  let password = Optional(profile.getString(section: "auth_info_0", key: "passwd", defaultString: "")), !password.isEmpty,
			  let params = try? core.createAccountParams() else {
			Log.error("[SecureLink Accounts] the profile has an incomplete account")
			return false
		}
		let domain = identity.domain ?? ""

		// the same person again (a new QR of the same number): updated in place below. Removing and adding it again let
		// the old account's unregister delete the binding the new one had just made – signed in, never rang (Android, 31. 10.)
		let samePerson = core.accountList.first {
			$0.params?.identityAddress?.domain == domain && $0.params?.identityAddress?.username == identity.username
		}
		// another number of the same server (a new invitation): the old login of that server goes, the other server's
		// stays. As a sign-out: unregistered first with its credentials, else the server keeps ringing for the old number
		for old in core.accountList where old.params?.identityAddress?.domain == domain
			&& old.params?.identityAddress?.username != identity.username {
			Log.warn("[SecureLink Accounts] replacing the account \(old.params?.identityAddress?.asStringUriOnly() ?? "")")
			let oldAuth = old.findAuthInfo()
			core.removeAccountWithData(account: old)
			AccountModel.removeCredentialsAfterUnregister(core: core, account: old, authInfo: oldAuth)
		}

		// the first account came by remote provisioning: its server values are in the phone-wide sections
		let first = core.defaultAccount?.params
		core.accountList.forEach { adoptPhoneWideValues(core, $0) }

		try? params.setIdentityaddress(newValue: identity)
		try? params.setServeraddress(newValue: server)
		let route = profile.getString(section: "proxy_0", key: "reg_route", defaultString: "")
		if let routeAddress = try? factory.createAddress(addr: route) { try? params.setRoutesaddresses(newValue: [routeAddress]) }
		params.expires = profile.getInt(section: "proxy_0", key: "reg_expires", defaultValue: 3600)
		params.registerEnabled = true
		params.publishEnabled = false
		params.realm = profile.getString(section: "proxy_0", key: "realm", defaultString: domain)
		params.conferenceFactoryUri = profile.getString(section: "proxy_0", key: "conference_factory_uri", defaultString: "")
		params.limeServerUrl = profile.getString(section: "proxy_0", key: "lime_server_url", defaultString: "")
		params.limeAlgo = profile.getString(section: "proxy_0", key: "lime_algo", defaultString: "")
		params.instantMessagingEncryptionMandatory = true
		// push as the first account has it (the app sets it up at the first sign-in)
		params.pushNotificationAllowed = first?.pushNotificationAllowed ?? true
		params.remotePushNotificationAllowed = first?.remotePushNotificationAllowed ?? true
		if let push = first?.pushNotificationConfig?.clone() { params.pushNotificationConfig = push }
		if profile.hasSection(section: section) != 0 {
			for key in keys {
				params.addCustomParam(key: paramPrefix + key, value: profile.getString(section: section, key: key, defaultString: ""))
			}
		} else { // a server from before securelink_account (31. 10. 2026): its values from its own profile, never the phone's
			params.addCustomParam(key: paramPrefix + "domain", value: domain)
			params.addCustomParam(key: paramPrefix + "org_name", value: domain)
			params.addCustomParam(key: paramPrefix + "dir_url", value: profile.getString(section: "misc", key: "contacts-vcard-list", defaultString: ""))
			params.addCustomParam(key: paramPrefix + "upload_url", value: profile.getString(section: "misc", key: "file_transfer_server_url", defaultString: ""))
			for key in ["admin_uri", "support_email", "privacy_url", "terms_url", "request_url"] {
				params.addCustomParam(key: paramPrefix + key, value: profile.getString(section: "app", key: key, defaultString: ""))
			}
		}

		let realm = profile.getString(section: "auth_info_0", key: "realm", defaultString: domain)
		let algorithm = profile.getString(section: "auth_info_0", key: "algorithm", defaultString: "SHA-256")
		guard let auth = try? factory.createAuthInfo(username: username, userid: nil, passwd: password, ha1: nil, realm: realm,
													 domain: domain, algorithm: algorithm) else {
			Log.error("[SecureLink Accounts] the account could not be created")
			return false
		}
		if let same = samePerson {
			core.addAuthInfo(info: auth)   // replaces the old password (same user name and domain)
			same.params = params
			core.refreshRegisters()
			Log.info("[SecureLink Accounts] signed in again as \(identity.asStringUriOnly())")
			refreshDirectories(core)
			return true
		}
		guard let account = try? core.createAccount(params: params) else {
			Log.error("[SecureLink Accounts] the account could not be created")
			return false
		}
		core.addAuthInfo(info: auth)
		try? core.addAccount(account: account)
		Log.info("[SecureLink Accounts] added the account \(identity.asStringUriOnly()) of \(setting(account, "org_name"))")
		refreshDirectories(core)
		return true
	}

	/// gives an account from remote provisioning its server values (securelink_account / [app] / [misc] of the phone)
	private static func adoptPhoneWideValues(_ core: Core, _ account: Account) {
		guard setting(account, "domain").isEmpty, let config = core.config, let params = account.params?.clone() else { return }
		let domain = account.params?.identityAddress?.domain ?? ""
		if config.getString(section: section, key: "domain", defaultString: "") == domain {
			for key in keys {
				params.addCustomParam(key: paramPrefix + key, value: config.getString(section: section, key: key, defaultString: ""))
			}
		} else { // a profile from before securelink_account (31. 10. 2026)
			params.addCustomParam(key: paramPrefix + "domain", value: domain)
			params.addCustomParam(key: paramPrefix + "org_name", value: domain)
			params.addCustomParam(key: paramPrefix + "dir_url", value: config.getString(section: "misc", key: "contacts-vcard-list", defaultString: ""))
			params.addCustomParam(key: paramPrefix + "upload_url", value: core.fileTransferServer ?? "")
			for key in ["admin_uri", "support_email", "privacy_url", "terms_url", "request_url"] {
				params.addCustomParam(key: paramPrefix + key, value: config.getString(section: "app", key: key, defaultString: ""))
			}
		}
		account.params = params
		// the phone-wide directory list would keep failing with two passwords – the app takes it over
		config.cleanEntry(section: "misc", key: "contacts-vcard-list")
		config.cleanEntry(section: "misc", key: "fetch_contacts_vcard_list_at_startup")
		Log.info("[SecureLink Accounts] the account \(account.params?.identityAddress?.asStringUriOnly() ?? "") keeps its server values itself")
	}

	/// downloads every server's directory with that account's own login and puts it into the account's contact list
	static func refreshDirectories(_ core: Core) {
		for account in core.accountList {
			let link = setting(account, "dir_url")
			guard !link.isEmpty, let url = URL(string: link), let auth = account.findAuthInfo() else { continue }
			let user = auth.username ?? ""
			let ha1 = (auth.algorithm ?? "").uppercased() == "SHA-256" ? (auth.ha1 ?? "") : ""
			let password = auth.password ?? ""
			let company = setting(account, "org_name")
			let name = company.isEmpty ? (account.params?.identityAddress?.domain ?? "") : company
			getWithDigest(url: url, user: user, storedHa1: ha1, password: password, authorization: nil) { body in
				guard let body = body else { return }
				CoreContext.shared.doOnCoreQueue { core in fillDirectory(core, link, name, body) }
			}
		}
	}

	private static func fillDirectory(_ core: Core, _ link: String, _ name: String, _ vcards: String) {
		// a new list each time: the list liblinphone made from the first profile does not let its friends go one by one
		for old in core.friendsLists where old.uri == link { core.removeFriendList(list: old) }
		guard let list = try? core.createFriendList() else { return }
		list.displayName = name
		list.uri = link
		list.type = .VCard4
		core.addFriendList(list: list)
		let count = vcards.isEmpty ? 0 : list.importFriendsFromVcard4Buffer(vcardBuffer: vcards)
		// two employers: the company goes with the name, so a contact, a call, a message and a notification all say it
		if isMultiServer(core) {
			for friend in list.friends {
				friend.edit()
				try? friend.setName(newValue: "\(friend.name ?? "") · \(name)")
				friend.done()
			}
		}
		Log.info("[SecureLink Accounts] directory of \(name): \(count) people")
		ContactsManager.shared.onDirectorySynchronized(list)
	}

	private static func getWithDigest(url: URL, user: String, storedHa1: String, password: String, authorization: String?,
									  done: @escaping (String?) -> Void) {
		var request = URLRequest(url: url, timeoutInterval: 30)
		request.setValue("text/vcard", forHTTPHeaderField: "Accept")
		if let authorization = authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
		session.dataTask(with: request) { data, response, error in
			let http = response as? HTTPURLResponse
			if http?.statusCode == 200 {
				done(data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
				return
			}
			guard authorization == nil, http?.statusCode == 401, let challenge = http?.value(forHTTPHeaderField: "WWW-Authenticate"),
				  let header = digest(challenge: challenge, user: user, storedHa1: storedHa1, password: password, uri: url.path) else {
				Log.warn("[SecureLink Accounts] \(url) answered \(http?.statusCode ?? 0) \(error?.localizedDescription ?? "")")
				done(nil)
				return
			}
			getWithDigest(url: url, user: user, storedHa1: storedHa1, password: password, authorization: header, done: done)
		}.resume()
	}

	/// RFC 7616 digest (SHA-256, qop=auth) for a GET – the server is /opt/securelink/www/sl-auth.php
	private static func digest(challenge: String, user: String, storedHa1: String, password: String, uri: String) -> String? {
		var fields: [String: String] = [:]
		let pattern = try? NSRegularExpression(pattern: "(\\w+)=\"?([^\",]*)\"?")
		for m in pattern?.matches(in: challenge, range: NSRange(challenge.startIndex..., in: challenge)) ?? [] {
			if let k = Swift.Range(m.range(at: 1), in: challenge), let v = Swift.Range(m.range(at: 2), in: challenge) {
				fields[String(challenge[k])] = String(challenge[v])
			}
		}
		let realm = fields["realm"] ?? "", nonce = fields["nonce"] ?? "", opaque = fields["opaque"] ?? ""
		let ha1 = !storedHa1.isEmpty ? storedHa1 : (password.isEmpty ? "" : sha256("\(user):\(realm):\(password)"))
		guard !ha1.isEmpty, !nonce.isEmpty else { return nil }
		let cnonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
		let nc = "00000001"
		let response = sha256("\(ha1):\(nonce):\(nc):\(cnonce):auth:" + sha256("GET:\(uri)"))
		return "Digest username=\"\(user)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\", "
			+ "algorithm=SHA-256, qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", response=\"\(response)\", opaque=\"\(opaque)\""
	}

	private static func sha256(_ text: String) -> String {
		return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
	}

	// our CA (as liblinphone with sip/root_ca) and the system ones (install pages, Let's Encrypt)
	private static let session = URLSession(configuration: .ephemeral, delegate: TrustOurCA(), delegateQueue: nil)

	private final class TrustOurCA: NSObject, URLSessionDelegate {
		private lazy var anchors: [SecCertificate] = {
			guard let path = Bundle.main.path(forResource: "securelink-ca.pem", ofType: nil),
				  let pem = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
			return pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().compactMap { block in
				let base64 = block.components(separatedBy: "-----END CERTIFICATE-----")[0]
					.components(separatedBy: .whitespacesAndNewlines).joined()
				return Data(base64Encoded: base64).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
			}
		}()

		func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
						completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
			guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
				  let trust = challenge.protectionSpace.serverTrust else {
				completionHandler(.performDefaultHandling, nil)
				return
			}
			SecTrustSetAnchorCertificates(trust, anchors as CFArray)
			SecTrustSetAnchorCertificatesOnly(trust, false)
			var failure: CFError?
			if SecTrustEvaluateWithError(trust, &failure) {
				completionHandler(.useCredential, URLCredential(trust: trust))
			} else {
				Log.error("[SecureLink Accounts] \(challenge.protectionSpace.host) not trusted (\(anchors.count) anchors): \(String(describing: failure))")
				completionHandler(.cancelAuthenticationChallenge, nil)
			}
		}
	}
}
