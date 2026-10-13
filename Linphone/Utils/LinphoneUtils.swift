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

// SecureLink: reports, account deletion requests and blocking (App Review 1.2 and 5.1.1(v)).
// Reports and requests go to the administrator as an end-to-end encrypted message – the server never sees them.
// The administrator's address and the web pages come from the server profile ([app] admin_uri, privacy_url, terms_url).
enum SecureLinkAdmin {
	/// text put into the message field when the administrator's conversation opens (the user sees it and sends it)
	static var pendingDraft: String?

	/// v1 agreement: messages disappear 7 days after they are read, users cannot switch it off.
	/// Not in the administrator's conversation – reports and requests stay there as a record.
	static let disappearAfterSeconds = 7 * 24 * 3600

	static func isAdminRoom(_ core: Core, _ room: ChatRoom) -> Bool {
		let uri = setting(core, "admin_uri")
		guard !uri.isEmpty, let admin = try? Factory.Instance.createAddress(addr: uri) else { return false }
		return room.participants.contains { $0.address?.weakEqual(address2: admin) == true }
	}

	/// every conversation of this phone (also ones others started) disappears after 7 days; run at start and foreground
	static func enforceDisappearing(_ core: Core) {
		for room in core.chatRooms where !isAdminRoom(core, room) {
			if !room.ephemeralEnabled || room.ephemeralLifetime != disappearAfterSeconds {
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

	/// "karel@securelink.cc" instead of "sip:karel@securelink.cc;gr=…"
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

	// --- blocking on this phone: no calls ring, the conversation is muted; the administrator gets a report
	private static let blockedKey = "blocked_uris"

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
		}
		Log.info("[SecureLink] \(uri) \(blocked ? "blocked" : "unblocked") on this phone")
	}
}
