/*
 * Copyright (c) 2010-2020 Belledonne Communications SARL.
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
import SwiftUI

class CallMediaEncryptionModel: ObservableObject {
	var coreContext = CoreContext.shared
	
	@Published var mediaEncryption = ""

	@Published var isMediaEncryptionZrtp = false
	@Published var zrtpCipher = ""
	@Published var zrtpKeyAgreement = ""
	@Published var zrtpHash = ""
	@Published var zrtpAuthTag = ""
	@Published var zrtpAuthSas = ""
	@Published var messagesEncryption = ""   // SecureLink: what protects the messages with this person (LIME)
	
	func update(call: Call) {
		coreContext.doOnCoreQueue { core in
			let messagesTmp = CallMediaEncryptionModel.messagesLine(call.params?.account ?? core.defaultAccount)
			DispatchQueue.main.async { self.messagesEncryption = messagesTmp }
			let stats = call.getStats(type: StreamType.Audio)
			if stats != nil {
				// ZRTP stats are only available when authentication token isn't null !
				if call.currentParams!.mediaEncryption == .ZRTP && call.authenticationToken != nil {
					let isMediaEncryptionZrtpTmp = true
					
					var mediaEncryptionTmp = ""
					if stats!.isZrtpKeyAgreementAlgoPostQuantum {
						mediaEncryptionTmp = CallMediaEncryptionModel.label("securelink_enc_media") + NSLocalizedString("securelink_enc_pq_zrtp", comment: "")
					} else {
						switch call.currentParams!.mediaEncryption {
						case .None:
							mediaEncryptionTmp = CallMediaEncryptionModel.label("securelink_enc_media") + "None"
						case .SRTP:
							mediaEncryptionTmp = CallMediaEncryptionModel.label("securelink_enc_media") + "SRTP"
						case .ZRTP:
							mediaEncryptionTmp = CallMediaEncryptionModel.label("securelink_enc_media") + "ZRTP"
						case .DTLS:
							mediaEncryptionTmp = CallMediaEncryptionModel.label("securelink_enc_media") + "DTLS"
						}
					}
					
					let zrtpCipherTmp = CallMediaEncryptionModel.label("securelink_enc_cipher") + stats!.zrtpCipherAlgo
					
					let zrtpKeyAgreementTmp = CallMediaEncryptionModel.label("securelink_enc_key") + stats!.zrtpKeyAgreementAlgo
					
					let zrtpHashTmp = CallMediaEncryptionModel.label("securelink_enc_hash") + stats!.zrtpHashAlgo
					
					let zrtpAuthTagTmp = CallMediaEncryptionModel.label("securelink_enc_auth") + stats!.zrtpAuthTagAlgo
					
					let zrtpAuthSasTmp = CallMediaEncryptionModel.label("securelink_enc_sas") + stats!.zrtpSasAlgo
					
					DispatchQueue.main.async {
						self.isMediaEncryptionZrtp = isMediaEncryptionZrtpTmp
						
						self.mediaEncryption = mediaEncryptionTmp
						
						self.zrtpCipher = zrtpCipherTmp
						
						self.zrtpKeyAgreement = zrtpKeyAgreementTmp
						
						self.zrtpHash = zrtpHashTmp
						
						self.zrtpAuthTag = zrtpAuthTagTmp
						
						self.zrtpAuthSas = zrtpAuthSasTmp
					}
				} else {
					let mediaEncryptionTmp = CallMediaEncryptionModel.label("securelink_enc_media") + call.currentParams!.mediaEncryption.rawValue.description // call.currentParams.mediaEncryption
					
					DispatchQueue.main.async {
						self.mediaEncryption = mediaEncryptionTmp
					}
				}
				
			}
		}
	}

	// SecureLink: the encryption window in Czech/English (it was English only)
	private static func label(_ key: String) -> String {
		return NSLocalizedString(key, comment: "") + ": "
	}

	/// the account's LIME algorithm (first = the one new conversations use) in words
	private static func messagesLine(_ account: Account?) -> String {
		let algo = (account?.params?.limeAlgo ?? "").split(separator: ",").first.map(String.init) ?? ""
		let name: String
		switch algo {
		case "c448mlk1024": name = "X448 + ML-KEM-1024 (" + NSLocalizedString("securelink_enc_pq", comment: "") + ")"
		case "c25519mlk512": name = "X25519 + ML-KEM-512 (" + NSLocalizedString("securelink_enc_pq", comment: "") + ")"
		case "c25519k512": name = "X25519 + Kyber-512 (" + NSLocalizedString("securelink_enc_pq", comment: "") + ")"
		case "": return ""
		default: name = algo
		}
		return label("securelink_enc_messages") + name
	}
}
