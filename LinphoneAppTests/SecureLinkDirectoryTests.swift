/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (c) 2026 Petr Wozniak <petr.wozniak@gmail.com>
 *
 * This file is part of SecureLink, a modified version of linphone-iphone.
 */

import XCTest
import linphonesw
@testable import LinphoneApp

/// A2 (1.2): the contacts of a circle leave the phone with the circle. SecureLink's contacts are the server directory
/// lists (vCard4, address = the server's directory URL); these tests build them on a core of their own, next to the
/// app's, with accounts that never register.
class SecureLinkDirectoryTests: XCTestCase {

	private var core: Core!
	private let dirA = "https://a.example/dir"
	private let dirB = "https://b.example/dir"

	override func setUpWithError() throws {
		core = try Factory.Instance.createCore(configPath: nil, factoryConfigPath: nil, systemContext: nil)
	}

	override func tearDown() {
		core = nil
		super.tearDown()
	}

	@discardableResult
	private func addAccount(_ user: String, _ domain: String, dir: String) throws -> Account {
		let params = try core.createAccountParams()
		try params.setIdentityaddress(newValue: Factory.Instance.createAddress(addr: "sip:\(user)@\(domain)"))
		try params.setServeraddress(newValue: Factory.Instance.createAddress(addr: "sip:\(domain);transport=tls"))
		params.registerEnabled = false
		params.addCustomParam(key: "sl_dir_url", value: dir)
		params.addCustomParam(key: "sl_domain", value: domain)
		let account = try core.createAccount(params: params)
		try core.addAccount(account: account)
		return account
	}

	@discardableResult
	private func addDirectory(_ uri: String, people: [String]) throws -> FriendList {
		let list = try core.createFriendList()
		list.displayName = uri
		list.uri = uri
		list.type = .VCard4
		core.addFriendList(list: list)
		for address in people {
			let friend = try core.createFriend()
			friend.edit()
			try friend.setName(newValue: address)
			friend.addAddress(address: try Factory.Instance.createAddress(addr: address))
			friend.done()
			_ = list.addFriend(linphoneFriend: friend)
		}
		return list
	}

	private var directoryUris: Set<String> {
		Set(core.friendsLists.filter { $0.type == .VCard4 || $0.type == .CardDAV }.compactMap { $0.uri })
	}

	// (a) two circles, one signed out: only its directory goes, the other circle's people stay
	func testSigningOutOneOfTwoCirclesRemovesOnlyItsDirectory() throws {
		try addAccount("100", "a.example", dir: dirA)
		let b = try addAccount("200", "b.example", dir: dirB)
		try addDirectory(dirA, people: ["sip:eva@a.example"])
		try addDirectory(dirB, people: ["sip:jan@b.example"])

		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, [dirA, dirB], "both circles signed in – nothing may go")

		core.removeAccount(account: b)   // what sign-out does with the account (removeAccountWithData)
		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, [dirA])
		XCTAssertNotNil(core.findFriend(address: try Factory.Instance.createAddress(addr: "sip:eva@a.example")))
		XCTAssertNil(core.findFriend(address: try Factory.Instance.createAddress(addr: "sip:jan@b.example")))
	}

	// (a) the first circle (signed in by its QR: no own value, the phone-wide profile names its directory) signed out,
	// the second stays: the first one's directory goes, and so does its phone-wide profile – liblinphone would bring the
	// directory back at the next start
	func testSigningOutTheFirstCircleRemovesItsDirectoryAndProfile() throws {
		let config = try XCTUnwrap(core.config)
		config.setString(section: "securelink_account", key: "domain", value: "a.example")
		config.setString(section: "securelink_account", key: "dir_url", value: dirA)
		config.setString(section: "misc", key: "contacts-vcard-list", value: dirA)
		let a = try addAccount("100", "a.example", dir: "")
		try addAccount("200", "b.example", dir: dirB)
		try addDirectory(dirA, people: ["sip:eva@a.example"])
		try addDirectory(dirB, people: ["sip:jan@b.example"])

		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, [dirA, dirB], "both circles signed in – nothing may go")

		core.removeAccount(account: a)
		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, [dirB])
		XCTAssertEqual(config.getString(section: "misc", key: "contacts-vcard-list", defaultString: ""), "")
		XCTAssertEqual(config.getString(section: "securelink_account", key: "domain", defaultString: ""), "")
		XCTAssertNotNil(core.findFriend(address: try Factory.Instance.createAddress(addr: "sip:jan@b.example")))
	}

	// one circle signed in by its QR, alone on the phone: its directory is liblinphone's list and stays
	func testTheOnlyCircleFromItsQrKeepsItsDirectory() throws {
		core.config?.setString(section: "misc", key: "contacts-vcard-list", value: dirA)
		try addAccount("100", "a.example", dir: "")
		try addDirectory(dirA, people: ["sip:eva@a.example"])
		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, [dirA])
		XCTAssertEqual(core.config?.getString(section: "misc", key: "contacts-vcard-list", defaultString: ""), dirA)
	}

	// (b) the last circle wiped: every directory goes (the same clean-up as "Sign out and erase everything")
	func testWipingTheLastAccountRemovesEveryDirectory() throws {
		let a = try addAccount("100", "a.example", dir: dirA)
		try addDirectory(dirA, people: ["sip:eva@a.example"])
		try addDirectory("https://old.example/dir", people: ["sip:vera@old.example"])

		SecureLinkAccounts.wipeAccount(core, a)
		XCTAssertTrue(directoryUris.isEmpty)
		XCTAssertNil(core.findFriend(address: try Factory.Instance.createAddress(addr: "sip:eva@a.example")))
	}

	// (c) the server moved (same domain, new directory address): the old directory goes, the new one stays
	func testServerMoveRemovesTheOldDirectory() throws {
		let newDir = "https://a2.example/dir"
		try addAccount("100", "a.example", dir: newDir)
		try addDirectory(dirA, people: ["sip:eva@a.example", "sip:vera@a.example"])
		try addDirectory(newDir, people: ["sip:eva@a.example"])

		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, [newDir])
		XCTAssertNil(core.findFriend(address: try Factory.Instance.createAddress(addr: "sip:vera@a.example")))
	}

	// (c) a domain change: the new circle's account, the old circle's directory goes
	func testDomainChangeRemovesTheOldDirectory() throws {
		try addAccount("100", "new.example", dir: "https://new.example/dir")
		try addDirectory("https://new.example/dir", people: ["sip:eva@new.example"])
		try addDirectory(dirA, people: ["sip:eva@a.example"])

		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertEqual(directoryUris, ["https://new.example/dir"])
	}

	// lists that are not server directories (local lists) are never touched
	func testOtherListsStay() throws {
		try addAccount("100", "a.example", dir: dirA)
		let local = try core.createFriendList()
		local.displayName = "Linphone address-book"
		core.addFriendList(list: local)
		let friend = try core.createFriend()
		friend.edit()
		try friend.setName(newValue: "Own contact")
		friend.addAddress(address: try Factory.Instance.createAddress(addr: "sip:own@elsewhere.example"))
		friend.done()
		_ = local.addFriend(linphoneFriend: friend)
		try addDirectory(dirB, people: ["sip:jan@b.example"])

		SecureLinkAccounts.pruneOrphanDirectories(core)
		XCTAssertTrue(directoryUris.isEmpty)
		XCTAssertNotNil(core.getFriendListByName(name: "Linphone address-book"))
		XCTAssertNotNil(core.findFriend(address: try Factory.Instance.createAddress(addr: "sip:own@elsewhere.example")))
	}

	// the decision itself
	func testOrphanDirectoriesRules() {
		// one account from remote provisioning: no own value, the phone-wide profile or liblinphone's list name it
		XCTAssertEqual(SecureLinkAccounts.orphanDirectories(listUris: [dirA, dirB], accounts: [("a.example", "")],
															phoneWideDomain: "a.example", phoneWideDir: dirA, vcardList: ""), [dirB])
		XCTAssertEqual(SecureLinkAccounts.orphanDirectories(listUris: [dirA, dirB], accounts: [("a.example", "")],
															phoneWideDomain: "", phoneWideDir: "", vcardList: dirA), [dirB])
		// the phone-wide profile of another domain does not count
		XCTAssertNil(SecureLinkAccounts.orphanDirectories(listUris: [dirA, dirB], accounts: [("a.example", "")],
														  phoneWideDomain: "b.example", phoneWideDir: dirB, vcardList: ""))
		// an account with an unknown directory, or no account at all: nothing is decided
		XCTAssertNil(SecureLinkAccounts.orphanDirectories(listUris: [dirA, dirB], accounts: [("a.example", dirA), ("b.example", "")],
														  phoneWideDomain: "", phoneWideDir: "", vcardList: ""))
		XCTAssertNil(SecureLinkAccounts.orphanDirectories(listUris: [dirA], accounts: [],
														  phoneWideDomain: "", phoneWideDir: "", vcardList: ""))
		// an account with its own value does not own the phone-wide vCard list of a circle that left
		XCTAssertEqual(SecureLinkAccounts.orphanDirectories(listUris: [dirA, dirB], accounts: [("b.example", dirB)],
															phoneWideDomain: "a.example", phoneWideDir: dirA, vcardList: dirA), [dirA])
		// a list without an address is never removed
		XCTAssertEqual(SecureLinkAccounts.orphanDirectories(listUris: ["", dirB], accounts: [("a.example", dirA)],
															phoneWideDomain: "", phoneWideDir: "", vcardList: ""), [dirB])
	}
}
