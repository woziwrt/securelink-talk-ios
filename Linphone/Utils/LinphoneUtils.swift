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
	private static var creationDelegate: ChatRoomDelegateStub?

	static func setting(_ core: Core?, _ key: String) -> String {
		return core?.config?.getString(section: "app", key: key, defaultString: "") ?? ""
	}

	/// opens (or creates) the encrypted conversation with the administrator, the draft is pre-filled
	static func openConversation(draft: String) {
		CoreContext.shared.doOnCoreQueue { core in
			let uri = setting(core, "admin_uri")
			guard !uri.isEmpty, let admin = try? Factory.Instance.createAddress(addr: uri),
				  let account = core.defaultAccount, let params = try? core.createConferenceParams(conference: nil),
				  let chatParams = params.chatParams else {
				Log.error("[SecureLink] no administrator address in the profile – cannot open the conversation")
				DispatchQueue.main.async { ToastViewModel.shared.show("Failed_to_create_conversation_error") }
				return
			}
			params.chatEnabled = true
			params.groupEnabled = false
			params.subject = NSLocalizedString("conversation_one_to_one_hidden_subject", comment: "")
			params.account = account
			chatParams.ephemeralLifetime = 0
			chatParams.backend = ChatRoom.Backend.FlexisipChat
			params.securityLevel = Conference.SecurityLevel.EndToEnd
			pendingDraft = draft
			if let room = core.searchChatRoom(params: params, localAddr: account.params?.identityAddress, remoteAddr: nil, participants: [admin]) {
				show(room)
				return
			}
			do {
				let room = try core.createChatRoom(params: params, participants: [admin])
				if room.state == ChatRoom.State.Created {
					show(room)
					return
				}
				let stub = ChatRoomDelegateStub(onStateChanged: { (room: ChatRoom, state: ChatRoom.State) in
					if state == ChatRoom.State.Created || state == ChatRoom.State.CreationFailed {
						if let d = creationDelegate { room.removeDelegate(delegate: d); creationDelegate = nil }
						if state == ChatRoom.State.Created {
							show(room)
						} else {
							DispatchQueue.main.async { ToastViewModel.shared.show("Failed_to_create_conversation_error") }
						}
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

	private static func show(_ room: ChatRoom) {
		let model = ConversationModel(chatRoom: room)
		DispatchQueue.main.async {
			SharedMainViewModel.shared.displayedConversation = model
		}
	}

	// --- blocking on this phone: no calls ring, the conversation is muted; the administrator gets a report
	private static let blockedKey = "blocked_uris"

	static func blockedList(_ core: Core) -> [String] {
		return (core.config?.getString(section: "securelink", key: blockedKey, defaultString: "") ?? "")
			.split(separator: ",").map(String.init)
	}

	static func isBlocked(_ core: Core, _ address: Address?) -> Bool {
		guard let uri = address?.asStringUriOnly() else { return false }
		return blockedList(core).contains(uri)
	}

	static func setBlocked(_ core: Core, _ address: Address, _ blocked: Bool) {
		let uri = address.asStringUriOnly()
		var list = blockedList(core).filter { $0 != uri }
		if blocked { list.append(uri) }
		core.config?.setString(section: "securelink", key: blockedKey, value: list.joined(separator: ","))
		for room in core.chatRooms where room.participants.count == 1 && room.participants.first?.address?.weakEqual(address2: address) == true {
			room.muted = blocked
		}
		Log.info("[SecureLink] \(uri) \(blocked ? "blocked" : "unblocked") on this phone")
	}
}
