/*
 * Copyright (c) 2010-2023 Belledonne Communications SARL.
 *
 * This file is part of linphone-iphone
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

import Foundation
import linphonesw
import CryptoKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

class LinphoneUtils: NSObject {
	static let RECORDING_FILE_NAME_HEADER = "call_recording_sip_"
	static let RECORDING_FILE_NAME_URI_TIMESTAMP_SEPARATOR = "_on_"
	static let RECORDING_MKV_FILE_EXTENSION = ".mkv"
	static let RECORDING_SMFF_FILE_EXTENSION = ".smff"
	
	public class func isChatRoomAGroup(chatRoom: ChatRoom) -> Bool {
		let oneToOne = chatRoom.hasCapability(mask: ChatRoom.Capabilities.OneToOne.rawValue)
		let conference = chatRoom.hasCapability(mask: ChatRoom.Capabilities.Conference.rawValue)
		return !oneToOne && conference
	}
	
	public class func getChatIconState(chatState: Int) -> String {
		return switch chatState {
		case ChatMessage.State.Displayed.rawValue, ChatMessage.State.FileTransferDone.rawValue:
			"checks"
		case ChatMessage.State.DeliveredToUser.rawValue:
			"check"
		case ChatMessage.State.Delivered.rawValue:
			"envelope-simple"
		case ChatMessage.State.NotDelivered.rawValue, ChatMessage.State.FileTransferError.rawValue:
			"warning-circle"
		case ChatMessage.State.InProgress.rawValue, ChatMessage.State.FileTransferInProgress.rawValue:
			"animated-in-progress"
		default:
			"animated-in-progress"
		}
	}
	
	public class func getChatRoomId(room: ChatRoom) -> String {
		return room.identifier ?? ""
		//return getChatRoomId(localAddress: room.localAddress!, remoteAddress: room.peerAddress!)
	}
	
	public class func getChatRoomId(localAddress: Address, remoteAddress: Address) -> String {
		let localSipUri = localAddress.clone()
		localSipUri!.clean()
		let remoteSipUri = remoteAddress.clone()
		remoteSipUri!.clean()
		return getChatRoomId(localSipUri: localSipUri!.asStringUriOnly(), remoteSipUri: remoteSipUri!.asStringUriOnly())
	}
	
	public class func getChatRoomId(localSipUri: String, remoteSipUri: String) -> String {
		return "\(localSipUri)#~#\(remoteSipUri)"
	}
	
	public class func applyInternationalPrefix(core: Core, account: Account? = nil) -> Bool {
		return	account?.params?.useInternationalPrefixForCallsAndChats == true 
		|| core.defaultAccount?.params?.useInternationalPrefixForCallsAndChats == true
	}
	
	public class func isEndToEndEncryptedChatAvailable(core: Core) -> Bool {
		return core.limeX3DhEnabled &&
		core.defaultAccount?.params?.limeServerUrl != nil &&
		core.defaultAccount?.params?.conferenceFactoryUri != nil
	}
	
	public class func createConferenceScheduler(core: Core) -> ConferenceScheduler? {
		let account = LinphoneUtils.getDefaultAccount()
		if let url = account?.params?.ccmpServerUrl, !url.isEmpty {
			Log.info(
				"CCMP server URL has been set in Account's params, using CCMP conference scheduler"
			)
			
			let conferenceScheduler = try? core.createConferenceSchedulerWithType(
				account: account,
				schedulingType: .CCMP
			)
				
			return conferenceScheduler
		}
		Log.info(
			"CCMP server URL hasn't been set in Account's params, using SIP conference scheduler"
		)
		
		let conferenceScheduler = try? core.createConferenceSchedulerWithType(
			account: account,
			schedulingType: .SIP
		)
		
		return conferenceScheduler
	}
	
	public class func getChatRoomParamsForMeetingInvitationsAndUpdates(core: Core) -> ConferenceParams? {
		if let chatRoomParams = try? core.createConferenceParams(conference: nil) {
			chatRoomParams.chatEnabled = true
			chatRoomParams.groupEnabled = false
			chatRoomParams.subject = "Meeting invitation" // Won't be used

			if let chatParams = chatRoomParams.chatParams {
				chatParams.ephemeralLifetime = 0 // Make sure ephemeral messages are disabled by default

				if isEndToEndEncryptedChatAvailable(core: core) {
					Log.info("\(#function) LIME is available, sending invitation through 1-1 E2E-encrypted chat rooms with each participant")

					chatParams.backend = ChatRoom.Backend.FlexisipChat
					chatRoomParams.securityLevel = Conference.SecurityLevel.EndToEnd
				} else {
					Log.warn("\(#function) LIME is not available, sending invitation through 1-1 clear-text chat rooms with each participant")

					chatParams.backend = ChatRoom.Backend.Basic
					chatRoomParams.securityLevel = Conference.SecurityLevel.None
				}
			}

			return chatRoomParams
		}

		return nil
	}
	
	public class func createGroupCall(core: Core, account: Account?, subject: String) -> Conference? {
		do {
			let conferenceParams = try core.createConferenceParams(conference: nil)
			conferenceParams.videoEnabled = true
			conferenceParams.account = account
			conferenceParams.subject = subject
			
			// Enable end-to-end encryption if client supports it
			//if isEndToEndEncryptedChatAvailable(core: core) {
			if false {
				Log.info("\(#function) Requesting EndToEnd security level for conference")
				conferenceParams.securityLevel = .EndToEnd
			} else {
				Log.info("\(#function) Requesting PointToPoint security level for conference")
				conferenceParams.securityLevel = .PointToPoint
			}
			
			// Allows to have a chat room within the conference
			conferenceParams.chatEnabled = true
			
			Log.info("\(#function) Creating group call with subject \(conferenceParams.subject ?? "Unknown")")
			
			let confWithParams = try core.createConferenceWithParams(params: conferenceParams)
			
			return confWithParams
		} catch let error {
			Log.info("\(#function) Error while creating group call: \(error)")
			return nil
		}
	}
	
	public class func getConversationId(chatRoom: ChatRoom) -> String {
		return chatRoom.identifier ?? ""
		
	}
	
	public class func getDefaultAccount() -> Account? {
		return CoreContext.shared.mCore.defaultAccount ?? (CoreContext.shared.mCore.accountList.first ?? nil)
	}
	
	public class func getAccountForAddress(address: Address) -> Account? {
		return CoreContext.shared.mCore.accountList.first { $0.params?.identityAddress?.weakEqual(address2: address) == true }
	}
	
	public class func isRemoteConferencingAvailable(core: Core) -> Bool {
		return core.defaultAccount?.params?.audioVideoConferenceFactoryAddress != nil
	}
	
	public class func isGroupChatAvailable(core: Core) -> Bool {
		return core.defaultAccount?.params?.conferenceFactoryUri != nil
	}
}

// SecureLink: group conversations carry no readable name. The chat server stores the subject in plain text, so it is a
// random number; every phone shows the members' names from its own directory instead.
enum SecureLinkGroups {
	static func randomSubject() -> String {
		return String(UInt32.random(in: 1_000_000...9_999_999))
	}

	/// "Eva, Karel, Milan" from this phone's directory (sorted, without me); falls back to "Skupina"
	static func title(_ chatRoom: ChatRoom) -> String {
		let names = chatRoom.participants.compactMap { participant -> String? in
			guard let address = participant.address else { return nil }
			if let name = ContactsManager.shared.getFriendWithAddress(address: address)?.name, !name.isEmpty { return name }
			if let display = address.displayName, !display.isEmpty { return display }
			return nil
		}.sorted { $0.localizedCompare($1) == .orderedAscending }
		return names.isEmpty ? NSLocalizedString("Skupina", comment: "") : names.joined(separator: ", ")
	}
}

// SecureLink: reports, account deletion requests and blocking (App Review 1.2 and 5.1.1(v)).
// Reports and requests go to the administrator as an end-to-end encrypted message – the server never sees them.
// The administrator's address and the web pages come from the server profile ([app] admin_uri, privacy_url, terms_url).
enum SecureLinkAdmin {
	/// text put into the message field when the administrator's conversation opens (the user sees it and sends it)
	static var pendingDraft: String?

	/// v1 agreement: messages disappear 7 days after they are read by default; users can shorten it, not switch it off.
	/// Not in the administrator's conversation – reports and requests stay there as a record.
	static let disappearAfterSeconds = 7 * 24 * 3600

	static func isAdminRoom(_ core: Core, _ room: ChatRoom) -> Bool {
		let uri = setting(core, "admin_uri")
		guard !uri.isEmpty, let admin = try? Factory.Instance.createAddress(addr: uri) else { return false }
		return room.participants.contains { $0.address?.weakEqual(address2: admin) == true }
	}

	/// every conversation of this phone (also ones others started) disappears after at most 7 days; a shorter time
	/// chosen in the conversation stays; run at start and foreground
	static func enforceDisappearing(_ core: Core) {
		for room in core.chatRooms where !isAdminRoom(core, room) {
			if !room.ephemeralEnabled || room.ephemeralLifetime <= 0 || room.ephemeralLifetime > disappearAfterSeconds {
				room.ephemeralLifetime = disappearAfterSeconds
				room.ephemeralEnabled = true
				Log.info("[SecureLink] disappearing messages (7 days) switched on in a conversation")
			}
		}
	}
	private static var creationDelegate: ChatRoomDelegateStub?

	static func setting(_ core: Core?, _ key: String) -> String {
		return core?.config?.getString(section: "app", key: key, defaultString: "") ?? ""
	}

	/// opens (or creates) the encrypted conversation with the administrator, the draft is pre-filled;
	/// with sendNow the text is sent at once and the user stays where they are (e.g. after an account deletion request)
	static func openConversation(draft: String, sendNow: Bool = false) {
		CoreContext.shared.doOnCoreQueue { core in
			let uri = setting(core, "admin_uri")
			guard !uri.isEmpty, let admin = try? Factory.Instance.createAddress(addr: uri),
				  let account = core.defaultAccount, let params = try? core.createConferenceParams(conference: nil) else {
				Log.error("[SecureLink] no administrator address in the profile – cannot open the conversation")
				DispatchQueue.main.async { ToastViewModel.shared.show("Failed_to_create_conversation_error") }
				return
			}
			// chat parameters exist only once chat is enabled on the conference parameters
			params.chatEnabled = true
			guard let chatParams = params.chatParams else {
				Log.error("[SecureLink] no chat parameters – cannot open the administrator conversation")
				DispatchQueue.main.async { ToastViewModel.shared.show("Failed_to_create_conversation_error") }
				return
			}
			params.groupEnabled = false
			params.subject = NSLocalizedString("conversation_one_to_one_hidden_subject", comment: "")
			params.account = account
			chatParams.ephemeralLifetime = 0
			chatParams.backend = ChatRoom.Backend.FlexisipChat
			params.securityLevel = Conference.SecurityLevel.EndToEnd
			let ready: (ChatRoom) -> Void = { room in
				if sendNow {
					if let message = try? room.createMessageFromUtf8(message: draft) {
						message.send()
						Log.info("[SecureLink] message sent to the administrator")
					}
				} else {
					pendingDraft = draft
					show(room)
				}
			}
			if let room = core.searchChatRoom(params: params, localAddr: account.params?.identityAddress, remoteAddr: nil, participants: [admin]) {
				ready(room)
				return
			}
			do {
				let room = try core.createChatRoom(params: params, participants: [admin])
				if room.state == ChatRoom.State.Created {
					ready(room)
					return
				}
				// an encrypted conversation is ready when the server lets us join it (as in ContactsListViewModel)
				let stub = ChatRoomDelegateStub(onStateChanged: { (room: ChatRoom, state: ChatRoom.State) in
					if state == ChatRoom.State.CreationFailed {
						if let d = creationDelegate { room.removeDelegate(delegate: d); creationDelegate = nil }
						DispatchQueue.main.async { ToastViewModel.shared.show("Failed_to_create_conversation_error") }
					}
				}, onConferenceJoined: { (room: ChatRoom, _: EventLog) in
					if room.state == ChatRoom.State.Created {
						if let d = creationDelegate { room.removeDelegate(delegate: d); creationDelegate = nil }
						ready(room)
					}
				})
				creationDelegate = stub
				room.addDelegate(delegate: stub)
			} catch {
				Log.error("[SecureLink] cannot create the administrator conversation: \(error)")
				DispatchQueue.main.async { ToastViewModel.shared.show("Failed_to_create_conversation_error") }
			}
		}
	}

	/// "123456789@securelink.cc" instead of "sip:123456789@securelink.cc;gr=…"
	static func plainAddress(_ uri: String) -> String {
		var a = uri
		for prefix in ["sips:", "sip:"] where a.lowercased().hasPrefix(prefix) { a = String(a.dropFirst(prefix.count)) }
		if let cut = a.firstIndex(where: { $0 == ";" || $0 == ">" }) { a = String(a[..<cut]) }
		return a
	}

	/// report of a person: who, then the reason the user writes after "Co se stalo:"
	static func reportContactDraft(name: String, address: String) -> String {
		return String(format: NSLocalizedString("securelink_report_contact_draft", comment: ""), name, plainAddress(address))
	}

	/// report of one received message: sender, time, the text as the reporter sees it, then the reason
	static func reportMessageDraft(senderAddress: String, sent: Date, text: String) -> String {
		var name = plainAddress(senderAddress)
		if let addr = try? Factory.Instance.createAddress(addr: senderAddress),
		   let friendName = ContactsManager.shared.getFriendWithAddress(address: addr)?.name, !friendName.isEmpty {
			name = friendName
		}
		let when = DateFormatter.localizedString(from: sent, dateStyle: .short, timeStyle: .short)
		return String(format: NSLocalizedString("securelink_report_message_draft", comment: ""), name, plainAddress(senderAddress), when, text)
	}

	private static func show(_ room: ChatRoom) {
		let model = ConversationModel(chatRoom: room)
		DispatchQueue.main.async {
			// the conversation is shown on the Messages tab (index 2), also when the report starts from a contact card
			SharedMainViewModel.shared.changeIndexView(indexViewInt: 2)
			SharedMainViewModel.shared.displayedFriend = nil
			SharedMainViewModel.shared.displayedCall = nil
			SharedMainViewModel.shared.displayedConversation = model
		}
	}

	// --- account deletion (App Review 5.1.1(v)): one tap sends a signed request to the server ([app] request_url,
	// HTTP digest SHA-256 with the SIP account – the same check as attachments); the administrator deletes within 7 days
	static func requestDeletion(done: @escaping (Bool) -> Void) {
		CoreContext.shared.doOnCoreQueue { core in
			let link = setting(core, "request_url")
			guard let url = URL(string: link), !link.isEmpty, let auth = core.defaultAccount?.findAuthInfo(),
				  let user = auth.username, !user.isEmpty else {
				Log.error("[SecureLink] deletion request: no request_url or no credentials")
				DispatchQueue.main.async { done(false) }
				return
			}
			let storedHa1 = (auth.algorithm ?? "").uppercased() == "SHA-256" ? (auth.ha1 ?? "") : ""
			postDeletion(url: url, user: user, password: auth.password ?? "", storedHa1: storedHa1, authorization: nil, done: done)
		}
	}

	private static func sha256(_ text: String) -> String {
		return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
	}

	private static func postDeletion(url: URL, user: String, password: String, storedHa1: String, authorization: String?,
									 done: @escaping (Bool) -> Void) {
		var request = URLRequest(url: url, timeoutInterval: 30)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.httpBody = Data("type=delete".utf8)
		if let authorization = authorization {
			request.setValue(authorization, forHTTPHeaderField: "Authorization")
		}
		URLSession.shared.dataTask(with: request) { _, response, error in
			let http = response as? HTTPURLResponse
			if http?.statusCode == 200 {
				Log.info("[SecureLink] account deletion requested")
				DispatchQueue.main.async { done(true) }
				return
			}
			guard authorization == nil, http?.statusCode == 401,
				  let challenge = http?.value(forHTTPHeaderField: "WWW-Authenticate") else {
				Log.error("[SecureLink] deletion request failed: \(http?.statusCode ?? 0) \(error?.localizedDescription ?? "")")
				DispatchQueue.main.async { done(false) }
				return
			}
			var fields: [String: String] = [:]
			let pattern = try? NSRegularExpression(pattern: "(\\w+)=\"?([^\",]*)\"?")
			for m in pattern?.matches(in: challenge, range: NSRange(challenge.startIndex..., in: challenge)) ?? [] {
				if let k = Swift.Range(m.range(at: 1), in: challenge), let v = Swift.Range(m.range(at: 2), in: challenge) {
					fields[String(challenge[k])] = String(challenge[v])
				}
			}
			let realm = fields["realm"] ?? "", nonce = fields["nonce"] ?? "", opaque = fields["opaque"] ?? ""
			let ha1 = !storedHa1.isEmpty ? storedHa1 : (password.isEmpty ? "" : sha256("\(user):\(realm):\(password)"))
			guard !ha1.isEmpty, !nonce.isEmpty else {
				Log.error("[SecureLink] deletion request: no SHA-256 credentials for the digest")
				DispatchQueue.main.async { done(false) }
				return
			}
			let cnonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
			let nc = "00000001", uri = url.path
			let response = sha256("\(ha1):\(nonce):\(nc):\(cnonce):auth:" + sha256("POST:\(uri)"))
			let header = "Digest username=\"\(user)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\", "
				+ "algorithm=SHA-256, qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", response=\"\(response)\", opaque=\"\(opaque)\""
			postDeletion(url: url, user: user, password: password, storedHa1: storedHa1, authorization: header, done: done)
		}.resume()
	}

	// --- blocking on this phone (App Review 1.2): no calls ring, messages are dropped, the one-to-one conversation
	// leaves the list at once, and the administrator gets an automatic report
	private static let blockedKey = "blocked_uris"
	static let blockedChangedNotification = Notification.Name("SecureLinkBlockedChanged")

	static func blockedList(_ core: Core) -> [String] {
		return (core.config?.getString(section: "securelink", key: blockedKey, defaultString: "") ?? "")
			.split(separator: ",").map(String.init)
	}

	/// "sip:user@domain" – the same key in the app and in the notification extension, whatever the device (;gr=) or scheme
	static func blockKey(_ address: Address?) -> String? {
		guard let a = address, let user = a.username, let domain = a.domain else { return nil }
		return "sip:\(user)@\(domain)"
	}

	static func isBlocked(_ core: Core, _ address: Address?) -> Bool {
		guard let uri = blockKey(address) else { return false }
		return blockedList(core).contains(uri)
	}

	static func setBlocked(_ core: Core, _ address: Address, _ blocked: Bool) {
		guard let uri = blockKey(address) else { return }
		var list = blockedList(core).filter { $0 != uri }
		if blocked { list.append(uri) }
		core.config?.setString(section: "securelink", key: blockedKey, value: list.joined(separator: ","))
		for room in core.chatRooms where room.participants.count == 1 && room.participants.first?.address?.weakEqual(address2: address) == true {
			room.muted = blocked
			if blocked {
				room.markAsRead()   // its unread messages would keep a badge the user can no longer clear
			}
		}
		Log.info("[SecureLink] \(uri) \(blocked ? "blocked" : "unblocked") on this phone")
		if blocked && uri != blockKey(try? Factory.Instance.createAddress(addr: setting(core, "admin_uri"))) {
			openConversation(draft: blockReportDraft(address), sendNow: true)
		}
		SharedMainViewModel.shared.updateUnreadMessagesCount()
		DispatchQueue.main.async {
			if blocked, let shown = SharedMainViewModel.shared.displayedConversation,
			   shown.chatRoom.participants.count == 1, shown.chatRoom.participants.first?.address?.weakEqual(address2: address) == true {
				SharedMainViewModel.shared.displayedConversation = nil
			}
			NotificationCenter.default.post(name: blockedChangedNotification, object: nil)
		}
	}

	/// a one-to-one conversation with a contact blocked on this phone: not shown in the list
	static func isBlockedRoom(_ core: Core, _ room: ChatRoom) -> Bool {
		guard room.hasCapability(mask: ChatRoom.Capabilities.OneToOne.rawValue), room.participants.count == 1 else { return false }
		return isBlocked(core, room.participants.first?.address)
	}

	/// messages from a blocked contact (one-to-one or in a group) are deleted as they arrive
	static func dropBlockedMessages(_ core: Core, _ room: ChatRoom, _ messages: [ChatMessage]) {
		let list = blockedList(core)
		guard !list.isEmpty else { return }
		var dropped = 0
		for message in messages where !message.isOutgoing {
			if let key = blockKey(message.fromAddress), list.contains(key) {
				room.deleteMessage(message: message)
				dropped += 1
			}
		}
		if dropped > 0 {
			if isBlockedRoom(core, room) {
				room.markAsRead()   // not in a group: the other members' unread messages stay unread
			}
			Log.info("[SecureLink] \(dropped) message(s) from a blocked contact dropped")
		}
	}

	/// the notification extension stores messages while the app sleeps – this delegate never sees them; at foreground
	/// the unread ones from a blocked contact are deleted the same way
	static func purgeBlockedMessages(_ core: Core) {
		guard !blockedList(core).isEmpty else { return }
		for room in core.chatRooms where room.unreadMessagesCount > 0 {
			dropBlockedMessages(core, room, room.getHistory(nbMessage: room.unreadMessagesCount))
			if isBlockedRoom(core, room) {
				room.markAsRead()
			}
		}
	}

	/// automatic report sent to the administrator when a contact is blocked
	private static func blockReportDraft(_ address: Address) -> String {
		let plain = plainAddress(address.asStringUriOnly())
		let name = ContactsManager.shared.getFriendWithAddress(address: address)?.name ?? plain
		return String(format: NSLocalizedString("securelink_block_report_draft", comment: ""), name, plain)
	}
}

/// v1 agreement: location and camera data never leave the phone with a photo or video, app data stays out of iCloud backups
enum SecureLinkPrivacy {

	/// removes location, time and device data from a photo or video before it is sent; other files are left alone.
	/// false = it could not be cleaned and must not be sent
	static func cleanAttachment(at url: URL) -> Bool {
		guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return true }
		if type.conforms(to: .gif) {
			return true   // GIF has no EXIF or location block
		}
		if type.conforms(to: .image) {
			guard let data = try? Data(contentsOf: url), let clean = cleanImageData(data) else { return false }
			return clean == data || (try? clean.write(to: url)) != nil
		}
		if type.conforms(to: .movie) {
			return cleanVideo(at: url)
		}
		return true
	}

	/// true when no location, time or device data is left in the picture
	private static func isClean(_ data: Data) -> Bool {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil),
			  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
		if props[kCGImagePropertyGPSDictionary] != nil || props[kCGImagePropertyMakerAppleDictionary] != nil {
			return false
		}
		let exif = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
		let tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
		let exifKeys: [CFString] = [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifLensModel,
									kCGImagePropertyExifLensMake, kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifCameraOwnerName,
									kCGImagePropertyExifUserComment]
		let tiffKeys: [CFString] = [kCGImagePropertyTIFFModel, kCGImagePropertyTIFFMake, kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFSoftware,
									kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFHostComputer]
		return !exifKeys.contains { exif[$0] != nil } && !tiffKeys.contains { tiff[$0] != nil }
	}

	/// first a lossless copy with empty metadata (only the orientation, so the photo is not rotated); ImageIO keeps
	/// some fields for HEIC and PNG, then the pixels are re-encoded. Checked on JPEG, HEIC and PNG (13. 10.)
	private static func cleanImageData(_ data: Data) -> Data? {
		if isClean(data) {
			return data
		}
		guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else { return nil }
		let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation]
		
		let metadata = CGImageMetadataCreateMutable()
		if let orientation {
			_ = CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, orientation as CFTypeRef)
		}
		let copyOptions: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false,
											kCGImageMetadataShouldExcludeGPS: true, kCGImageMetadataShouldExcludeXMP: true]
		let copied = NSMutableData()
		if let dest = CGImageDestinationCreateWithData(copied, type, 1, nil),
		   CGImageDestinationCopyImageSource(dest, source, copyOptions as CFDictionary, nil), isClean(copied as Data) {
			return copied as Data
		}
		
		let encoded = NSMutableData()
		guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
			  let encoder = CGImageDestinationCreateWithData(encoded, type, 1, nil) else { return nil }
		var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
		if let orientation {
			props[kCGImagePropertyOrientation] = orientation
		}
		CGImageDestinationAddImage(encoder, image, props as CFDictionary)
		guard CGImageDestinationFinalize(encoder), isClean(encoded as Data) else { return nil }
		return encoded as Data
	}

	/// picture and sound copied as they are (no re-encoding) into a new movie without metadata; the camera's timed
	/// metadata tracks stay behind. Checked on an iPhone 16 video (location, date, model gone, plays rotated right)
	private static func cleanVideo(at url: URL) -> Bool {
		let out = url.deletingLastPathComponent().appendingPathComponent("clean-" + UUID().uuidString + ".mov")
		do {
			let source = AVMovie(url: url, options: nil)
			let movie = try AVMutableMovie(settingsFrom: source, options: nil)
			movie.metadata = []
			movie.defaultMediaDataStorage = AVMediaDataStorage(url: out, options: nil)
			for track in source.tracks where track.mediaType == .video || track.mediaType == .audio {
				guard let copy = movie.addMutableTrack(withMediaType: track.mediaType, copySettingsFrom: track, options: nil) else {
					throw CocoaError(.fileWriteUnknown)
				}
				try copy.insertTimeRange(track.timeRange, of: track, at: track.timeRange.start, copySampleData: true)
				copy.metadata = []
			}
			guard !movie.tracks.isEmpty else { throw CocoaError(.fileWriteUnknown) }
			movie.metadata = []
			try movie.writeHeader(to: out, fileType: .mov, options: .addMovieHeaderToDestination)
			_ = try FileManager.default.replaceItemAt(url, withItemAt: out)
			return true
		} catch {
			Log.error("[SecureLink] video \(url.lastPathComponent) could not be cleaned of metadata: \(error)")
			try? FileManager.default.removeItem(at: out)
			return false
		}
	}

	/// messages, attachments and keys are not copied into the iPhone's iCloud/computer backup; a flag on a folder covers
	/// everything in it, also files created later. Run at every start
	static func excludeFromBackup() {
		var folders = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
			+ FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
		for group in ["group.cc.securelink.talk", "group.cc.securelink.talk.msgNotification", "group.cc.securelink.talk.linphoneExtension"] {
			if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
				folders.append(container)
				folders += (try? FileManager.default.contentsOfDirectory(at: container, includingPropertiesForKeys: nil)) ?? []
			}
		}
		for var folder in folders {
			if (try? folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true {
				continue
			}
			var values = URLResourceValues()
			values.isExcludedFromBackup = true
			do {
				try folder.setResourceValues(values)
			} catch {
				Log.warn("[SecureLink] could not exclude \(folder.lastPathComponent) from backup: \(error)")
			}
		}
	}
}

// SecureLink: dates in the phone's own language and 12/24 h setting – upstream hardcoded English words
// ("Yesterday", "Today") and US formats (h:mm a, MM/dd) for everything except fr_FR
enum SecureLinkDates {
	static func time(_ date: Date) -> String {
		return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
	}
	
	/// "Today"/"Yesterday" in the phone's language, otherwise the date (without the year in the current year)
	static func day(_ date: Date) -> String {
		let calendar = Calendar.current
		let formatter = DateFormatter()
		if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
			formatter.doesRelativeDateFormatting = true
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			let text = formatter.string(from: date)
			return text.prefix(1).uppercased() + text.dropFirst()
		}
		formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: .now, toGranularity: .year) ? "dM" : "dMyy")
		return formatter.string(from: date)
	}
}
