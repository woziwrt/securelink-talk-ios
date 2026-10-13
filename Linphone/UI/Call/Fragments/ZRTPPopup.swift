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

import SwiftUI
import Foundation

// swiftlint:disable:next type_body_length
struct ZRTPPopup: View {
	
	@ObservedObject private var telecomManager = TelecomManager.shared
	
	@ObservedObject var callViewModel: CallViewModel
	
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@State private var orientation = UIDevice.current.orientation
	
	var resizeView: CGFloat
	
	var body: some View {
		if callViewModel.isNotVerified {
			alertZRTP
		} else {
			popupZRTP
		}
	}
	
	// SecureLink: one security word for both sides, "matches" / "does not match" – no four-letter guessing game.
	var popupZRTP: some View {
		VStack(alignment: .center, spacing: 0) {
			HStack {
				Image("security")
					.renderingMode(.template)
					.resizable()
					.foregroundStyle(Color.white)
					.frame(width: 20, height: 20)
				Text("call_dialog_zrtp_validate_trust_title")
					.default_text_style_white_700(styleSize: 16)
			}
			.padding(.top, 15)
			.padding(.bottom, 12)

			VStack(alignment: .center, spacing: 10) {
				Text(callViewModel.cacheMismatch
					 ? LocalizedStringKey("Druhá strana má nové zařízení. Řekněte si navzájem bezpečnostní slovo a potvrďte, že souhlasí.")
					 : LocalizedStringKey("Řekněte si navzájem bezpečnostní slovo. Musí být na obou telefonech stejné."))
					.default_text_style(styleSize: 16)
					.multilineTextAlignment(.center)
					.padding(.top, 20)
					.padding(.horizontal, 16)

				Text(callViewModel.fullSas.isEmpty ? "…" : callViewModel.fullSas)
					.default_text_style_800(styleSize: 44)
					.foregroundStyle(Color.orangeMain500)
					.padding(.vertical, 14)

				HStack(spacing: 12) {
					Button(action: {
						callViewModel.confirmZrtpSas()
					}, label: {
						Text("Souhlasí")
							.default_text_style_white_600(styleSize: 20)
							.frame(height: 35)
							.frame(maxWidth: .infinity)
					})
					.padding(.horizontal, 16)
					.padding(.vertical, 10)
					.background(Color.greenSuccess500)
					.cornerRadius(60)

					Button(action: {
						callViewModel.updateZrtpSas(authTokenClicked: "")
						callViewModel.zrtpPopupDisplayed = false
					}, label: {
						Text("Nesouhlasí")
							.foregroundStyle(Color.redDanger500)
							.default_text_style_orange_600(styleSize: 20)
							.frame(height: 35)
							.frame(maxWidth: .infinity)
					})
					.padding(.horizontal, 16)
					.padding(.vertical, 10)
					.cornerRadius(60)
					.overlay(
						RoundedRectangle(cornerRadius: 60)
							.inset(by: 0.5)
							.stroke(Color.redDanger500, lineWidth: 1)
					)
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 20)
			}
			.frame(maxWidth: .infinity)
			.background(.white)
			.cornerRadius(20)
		}
		.background(callViewModel.cacheMismatch ? Color.orangeWarning600 : Color.blueInfo500)
		.cornerRadius(20)
		.padding(.horizontal, 16)
		.frame(maxWidth: SharedMainViewModel.shared.maxWidth)
	}

	var alertZRTP: some View {
		GeometryReader { geometry in
			VStack(alignment: .leading) {
				ZStack(alignment: .top, content: {
					HStack {
						Spacer()
						
						VStack {
							Image("shield-warning")
								.renderingMode(.template)
								.resizable()
								.foregroundStyle(.white)
								.frame(width: 25, height: 25, alignment: .leading)
							
							Text("call_dialog_zrtp_security_alert_title")
								.default_text_style_white_700(styleSize: 16 / resizeView)
						}
						.frame(maxWidth: .infinity)
						
						Spacer()
					}
					.padding(.top, 15)
					.padding(.bottom, 2)
				})
				
				VStack(alignment: .center) {
					VStack {
						Text("call_dialog_zrtp_security_alert_message")
							.default_text_style(styleSize: 16 / resizeView)
							.multilineTextAlignment(.center)
							.padding(.bottom, 10 / resizeView)
					}
					.padding(.bottom, 5)
					
					Button(action: {
						callViewModel.terminateCall()
					}, label: {
						HStack {
							Image("phone-disconnect")
								.renderingMode(.template)
								.resizable()
								.foregroundStyle(.white)
								.frame(width: 20, height: 20)
							
							Text("call_action_hang_up")
								.default_text_style_white_600(styleSize: 20)
								.frame(height: 35)
						}
						.frame(maxWidth: .infinity)
					})
					.padding(.horizontal, 20 / resizeView)
					.padding(.vertical, 10 / resizeView)
					.background(Color.redDanger500)
					.cornerRadius(60)
					.padding(.bottom)
				}
				.padding(.top, 20 / resizeView)
				.padding(.horizontal, 20 / resizeView)
				.background(.white)
				.cornerRadius(20)
			}
			.background(Color.redDanger500)
			.cornerRadius(20)
			.padding(.horizontal, 2)
			.frame(maxHeight: .infinity)
			.shadow(color: Color.redDanger500, radius: 0, x: 0, y: 2)
			.frame(maxWidth: SharedMainViewModel.shared.maxWidth * 1.2)
			.position(x: geometry.size.width / 2, y: geometry.size.height / 2)
			.onAppear {
				callViewModel.remoteAuthenticationTokens()
			}
		}
	}
}

#Preview {
	ZRTPPopup(callViewModel: CallViewModel(), resizeView: 1)
}
