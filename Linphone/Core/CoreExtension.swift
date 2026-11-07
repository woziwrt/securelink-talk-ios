/*
 * Copyright (c) 2010-2023 Belledonne Communications SARL.
 *
 * This file is part of linphone
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

// Core Extension provides a set of utilies to manage automatically a LinphoneCore no matter if it is from App or an extension.
// It is based on a singleton pattern and adds.

import UIKit
import Security
import linphonesw

struct CoreError: Error {
	let message: String
	init(_ message: String) {
		self.message = message
	}
	public var localizedDescription: String {
		return message
	}
}

extension Core {
	
	public static func runsInsideExtension() -> Bool { // Tells wether it is run inside app extension or the main app.
		let bundleUrl: URL = Bundle.main.bundleURL
		let bundlePathExtension: String = bundleUrl.pathExtension
		return bundlePathExtension == "appex"
	}
	
}

// MARK: - SecureLink: the device identity survives a change of identifierForVendor

/// liblinphone keeps this phone's SIP identity in linphonerc: misc/uuid is the +sip.instance (the GRUU, the LIME device,
/// the push binding and the other phones' trust hang on it). Next to it it stores the identifierForVendor it last saw
/// (misc/physical_device_identifier); when the two differ at start it takes the configuration for a copy on another
/// phone and makes a new uuid – a new device for the server and for every conversation. identifierForVendor can change
/// on the same phone though: the developer account becomes an organisation or the app is transferred (Apple: the vendor
/// name changes, identifierForVendor resets with the next update), or it is nil before the first unlock.
/// Proof that the uuid belongs to THIS phone: a Keychain item ...ThisDeviceOnly holding it – such items never leave the
/// device (not in backups restored to another phone, not in Quick Start), unlike a file or a file flag in the app group.
/// The uuid is recorded whenever liblinphone itself accepts it (stored identifier == current one); when the identifiers
/// differ later, the uuid stays only if the Keychain holds that very uuid, else liblinphone decides as before (a copy on
/// another phone gets a new identity). A phone that never ran 1.2 has no record yet and is treated the old way.
/// Runs before every core starts, in the app and in the notification extension (same Keychain group). 7. 11. 2026.
enum SecureLinkDeviceIdentity {
	private static let service = "cc.securelink.talk.device"
	private static let account = "sip-instance"

	static func keep(_ config: Config) {
		let uuid = config.getString(section: "misc", key: "uuid", defaultString: "")
		guard !uuid.isEmpty, uuid != "0" else { return }   // no identity yet – liblinphone makes one
		let stored = config.getString(section: "misc", key: "physical_device_identifier", defaultString: "")
		// the same value liblinphone reads (IosPlatformHelpers::getPhysicalDeviceIdentifier); nil before the first unlock
		let current = UIDevice.current.identifierForVendor?.uuidString
		var recorded: Data?
		let status = read(&recorded)
		guard status == errSecSuccess || status == errSecItemNotFound else { return }   // Keychain locked: decide nothing
		let mine = recorded == Data(uuid.utf8)
		if let current = current, stored == current || stored.isEmpty {
			// liblinphone keeps this uuid on this start: it is this phone's
			if !mine && !record(uuid) { Log.warn("[SecureLink] device identity could not be recorded in the Keychain") }
			return
		}
		guard mine else {
			Log.warn("[SecureLink] identifierForVendor differs and the Keychain does not know this uuid – liblinphone decides")
			return
		}
		if let current = current {
			Log.warn("[SecureLink] identifierForVendor changed on this phone – the SIP device identity (misc/uuid) stays")
			config.setString(section: "misc", key: "physical_device_identifier", value: current)
		} else {
			// liblinphone would compare with "unavailable_identifier" and make a new uuid: nothing to compare with
			config.cleanEntry(section: "misc", key: "physical_device_identifier")
		}
		try? config.sync()
	}

	/// Tests only: as on a phone where this version never ran.
	static func forgetRecord() {
		SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
	}

	private static func read(_ out: inout Data?) -> OSStatus {
		let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
									  kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		out = item as? Data
		return status
	}

	private static func record(_ uuid: String) -> Bool {
		let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
		SecItemDelete(query as CFDictionary)
		var add = query
		add[kSecValueData] = Data(uuid.utf8)
		add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
	}
}
