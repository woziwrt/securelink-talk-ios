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
/// on the same phone though: the app moved to another developer account (Apple's app transfer), or nil before the first
/// unlock ("unavailable_identifier"). SecureLink's linphonerc lives in the app group, which every start since 13. 10. 2026
/// excludes from backups (SecureLinkPrivacy.excludeFromBackup): it cannot come from a backup of another phone, so a
/// mismatch here means a new identifierForVendor, and the stored one is refreshed – the uuid stays (7. 11. 2026).
/// Runs before every core starts, in the app and in the notification extension.
enum SecureLinkDeviceIdentity {
	static func keep(_ config: Config, appGroup: String) {
		let uuid = config.getString(section: "misc", key: "uuid", defaultString: "")
		let stored = config.getString(section: "misc", key: "physical_device_identifier", defaultString: "")
		guard !uuid.isEmpty, uuid != "0", !stored.isEmpty else { return }   // no identity yet – liblinphone makes one
		// the same value liblinphone reads (IosPlatformHelpers::getPhysicalDeviceIdentifier)
		let current = UIDevice.current.identifierForVendor?.uuidString ?? "unavailable_identifier"
		guard stored != current else { return }
		guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
			  (try? container.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true else {
			Log.warn("[SecureLink] identifierForVendor differs and the app group is not excluded from backup – liblinphone decides")
			return
		}
		Log.warn("[SecureLink] identifierForVendor changed on this phone – the SIP device identity (misc/uuid) stays")
		config.setString(section: "misc", key: "physical_device_identifier", value: current)
		try? config.sync()
	}
}
