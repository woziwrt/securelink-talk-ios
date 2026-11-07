/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (c) 2026 Petr Wozniak <petr.wozniak@gmail.com>
 *
 * This file is part of SecureLink, a modified version of linphone-iphone.
 */

import XCTest
import linphonesw
@testable import LinphoneApp

/// The SIP device identity (misc/uuid) survives a new identifierForVendor on the same phone (the developer account
/// becoming an organisation), but a configuration copied to another phone still gets a new one from liblinphone.
class SecureLinkDeviceIdentityTests: XCTestCase {

	private let uuid = "urn:uuid:11111111-2222-3333-4444-555555555555"
	private var idfv: String { UIDevice.current.identifierForVendor!.uuidString }

	override func setUp() {
		super.setUp()
		SecureLinkDeviceIdentity.forgetRecord()
	}

	override func tearDown() {
		SecureLinkDeviceIdentity.forgetRecord()
		super.tearDown()
	}

	private func config(stored: String?) throws -> Config {
		let config = try Factory.Instance.createConfigFromString(data: "")
		config.setString(section: "misc", key: "uuid", value: uuid)
		if let stored = stored { config.setString(section: "misc", key: "physical_device_identifier", value: stored) }
		return config
	}

	private func stored(_ config: Config) -> String {
		config.getString(section: "misc", key: "physical_device_identifier", defaultString: "")
	}

	/// The usual start: the identifiers match, the uuid is recorded; later the identifierForVendor changes – it stays.
	func testNewIdentifierForVendorOnTheSamePhoneKeepsTheIdentity() throws {
		SecureLinkDeviceIdentity.keep(try config(stored: idfv))   // 1.2 runs once before the account changes
		let after = try config(stored: "AAAAAAAA-0000-0000-0000-000000000000")
		SecureLinkDeviceIdentity.keep(after)
		XCTAssertEqual(stored(after), idfv, "the stored identifier is refreshed, so liblinphone keeps misc/uuid")
	}

	/// A copy on another phone (Quick Start, backup): no record in this phone's Keychain – liblinphone decides.
	func testCopyOnAnotherPhoneIsLeftToLiblinphone() throws {
		let copy = try config(stored: "BBBBBBBB-0000-0000-0000-000000000000")
		SecureLinkDeviceIdentity.keep(copy)
		XCTAssertEqual(stored(copy), "BBBBBBBB-0000-0000-0000-000000000000", "untouched: liblinphone makes a new uuid")
	}

	/// The Keychain knows a different uuid (another installation): not ours, liblinphone decides.
	func testRecordOfAnotherUuidDoesNotCount() throws {
		let other = try Factory.Instance.createConfigFromString(data: "")
		other.setString(section: "misc", key: "uuid", value: "urn:uuid:99999999-0000-0000-0000-000000000000")
		other.setString(section: "misc", key: "physical_device_identifier", value: idfv)
		SecureLinkDeviceIdentity.keep(other)
		let copy = try config(stored: "CCCCCCCC-0000-0000-0000-000000000000")
		SecureLinkDeviceIdentity.keep(copy)
		XCTAssertEqual(stored(copy), "CCCCCCCC-0000-0000-0000-000000000000")
	}

	/// A fresh configuration (no stored identifier yet) is this phone's too.
	func testFirstStartRecordsTheIdentity() throws {
		SecureLinkDeviceIdentity.keep(try config(stored: nil))
		let after = try config(stored: "DDDDDDDD-0000-0000-0000-000000000000")
		SecureLinkDeviceIdentity.keep(after)
		XCTAssertEqual(stored(after), idfv)
	}
}
