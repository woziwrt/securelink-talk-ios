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

import SwiftUI
import Combine

struct LoginFragment: View {
	
	@ObservedObject private var coreContext = CoreContext.shared
	
	@StateObject private var accountLoginViewModel = AccountLoginViewModel()
	@StateObject private var keyboard = KeyboardResponder()
	
	@State private var isSecured: Bool = true
	
	@FocusState var isNameFocused: Bool
	@FocusState var isPasswordFocused: Bool
	
	@State private var isShowPopup = false
	
	@State private var linkActive = ""
	
	@State private var isLinkSIPActive = false
	@State private var isLinkREGActive = false
	
	@State var isShowHelpFragment = false
	
	var isShowBack = false
	
	var onBackPressed: (() -> Void)?

	var body: some View {
		NavigationView {
			ZStack {
				GeometryReader { geometry in
					if #available(iOS 16.4, *) {
						ScrollView(.vertical) {
							innerScrollView(geometry: geometry)
						}
						.scrollBounceBehavior(.basedOnSize)
					} else {
						ScrollView(.vertical) {
							innerScrollView(geometry: geometry)
						}
					}
					
					if self.isShowPopup {
						let generalTerms = String(format: "[%@](%@)", String(localized: "assistant_dialog_general_terms_label"), "https://www.linphone.org/en/terms-of-use/")
						let privacyPolicy = String(format: "[%@](%@)", String(localized: "assistant_dialog_privacy_policy_label"), "https://linphone.org/en/privacy-policy")
						let splitMsg = String(localized: "assistant_dialog_general_terms_and_privacy_policy_message").components(separatedBy: "%@")
						if splitMsg.count == 3 { // We expect form of  STRING %A STRING %@ STRING
							let contentPopup1 = Text(.init(splitMsg[0]))
							let contentPopup2 = Text(.init(generalTerms)).underline()
							let contentPopup3 = Text(.init(splitMsg[1]))
							let contentPopup4 = Text(.init(privacyPolicy)).underline()
							let contentPopup5 = Text(.init(splitMsg[2]))
							PopupView(
								isShowPopup: $isShowPopup,
								title: Text("assistant_dialog_general_terms_and_privacy_policy_title"),
								content: contentPopup1 + contentPopup2 + contentPopup3 + contentPopup4 + contentPopup5,
								titleFirstButton: nil,
								actionFirstButton: {},
								titleSecondButton: Text("dialog_accept"),
								actionSecondButton: { acceptGeneralTerms() },
								titleThirdButton: Text("dialog_deny"),
								actionThirdButton: { self.isShowPopup.toggle() }
							)
							.background(.black.opacity(0.65))
							.onTapGesture {
								self.isShowPopup.toggle()
							}
						} else {  // backup just in case
							PopupView(
								isShowPopup: $isShowPopup,
								title: Text("assistant_dialog_general_terms_and_privacy_policy_title"),
								content: Text(.init(String(format: String(localized: "assistant_dialog_general_terms_and_privacy_policy_message"), generalTerms, privacyPolicy))),
								titleFirstButton: nil,
								actionFirstButton: {},
								titleSecondButton: Text("dialog_accept"),
								actionSecondButton: { acceptGeneralTerms() },
								titleThirdButton: Text("dialog_deny"),
								actionThirdButton: { self.isShowPopup.toggle() }
							)
							.background(.black.opacity(0.65))
							.onTapGesture {
								self.isShowPopup.toggle()
							}
						}
					}
				}
				
				if isShowHelpFragment {
					HelpFragment(
						isShowHelpFragment: $isShowHelpFragment
					)
					.transition(.move(edge: .trailing))
					.zIndex(3)
				}
				
				if coreContext.loggingInProgress {
					PopupLoadingView()
						.background(.black.opacity(0.65))
				}
			}
			.navigationTitle("")
			.navigationBarHidden(true)
			.edgesIgnoringSafeArea(.bottom)
			.edgesIgnoringSafeArea(.horizontal)
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
	
	// SecureLink: the only way in is the administrator's QR code – no login form, no registration, no third-party SIP.
	func innerScrollView(geometry: GeometryProxy) -> some View {
		VStack {
			Spacer()

			Image("linphone")
				.resizable()
				.scaledToFit()
				.frame(width: 110, height: 110)
				.padding(.bottom, 10)

			Text("SecureLink")
				.default_text_style_800(styleSize: 28)
				.foregroundStyle(Color.orangeMain500)
				.padding(.bottom, 6)

			Text("Komunikace jen uvnitř okruhu.\nÚčet dostanete od správce jako QR kód.")
				.default_text_style(styleSize: 16)
				.foregroundStyle(Color.grayMain2c700)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 30)

			Spacer()

			NavigationLink(destination: {
				QrCodeScannerFragment()
			}, label: {
				HStack {
					Image("qr-code")
						.renderingMode(.template)
						.resizable()
						.foregroundStyle(Color.white)
						.frame(width: 24, height: 24)
					Text("assistant_scan_qr_code")
						.default_text_style_white_600(styleSize: 20)
						.frame(height: 35)
				}
				.frame(maxWidth: .infinity)
			})
			.padding(.horizontal, 20)
			.padding(.vertical, 12)
			.background(Color.orangeMain500)
			.cornerRadius(60)
			.padding(.horizontal, 30)
			.padding(.bottom, 12)

			Text("Nic dalšího nastavovat nemusíte.")
				.default_text_style(styleSize: 13)
				.foregroundStyle(Color.grayMain2c500)
				.padding(.bottom, 40)
		}
		.frame(maxWidth: SharedMainViewModel.shared.maxWidth)
		.frame(minHeight: geometry.size.height)
		.frame(maxWidth: .infinity)
	}

	func acceptGeneralTerms() {
		SharedMainViewModel.shared.changeGeneralTerms()
		self.isShowPopup.toggle()
		switch linkActive {
		case "SIP":
			self.isLinkSIPActive = true
		case "REG":
			self.isLinkREGActive = true
		default:
			print("Link Not Active")
		}
	}
}

#Preview {
	LoginFragment()
}
