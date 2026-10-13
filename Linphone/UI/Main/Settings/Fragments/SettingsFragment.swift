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
import UniformTypeIdentifiers
import Network
import UserNotifications
import AVFoundation
import linphonesw

struct SettingsFragment: View {
	
	@StateObject private var settingsViewModel = SettingsViewModel()
	
	@Binding var isShowSettingsFragment: Bool
	
	@State var securityIsOpen: Bool = false
	@State var callsIsOpen: Bool = false
	@State var conversationsIsOpen: Bool = false
	@State var contactsIsOpen: Bool = false
	@State var meetingsIsOpen: Bool = false
	@State var networkIsOpen: Bool = false
	@State var userInterfaceIsOpen: Bool = false
	
	var body: some View {
		NavigationView {
			ZStack {
				VStack(spacing: 1) {
					Rectangle()
						.foregroundColor(Color.orangeMain500)
						.edgesIgnoringSafeArea(.top)
						.frame(height: 0)
					
					HStack {
						Image("caret-left")
							.renderingMode(.template)
							.resizable()
							.foregroundStyle(Color.orangeMain500)
							.frame(width: 25, height: 25, alignment: .leading)
							.padding(.all, 10)
							.padding(.top, 4)
							.padding(.leading, -10)
							.onTapGesture {
								settingsViewModel.saveChangesWhenLeaving()
								withAnimation {
									if isShowSettingsFragment {
										isShowSettingsFragment = false
									}
								}
							}
						
						Text("settings_title")
							.default_text_style_orange_800(styleSize: 16)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.top, 4)
							.lineLimit(1)
						
						Spacer()
					}
					.frame(maxWidth: .infinity)
					.frame(height: 50)
					.padding(.horizontal)
					.padding(.bottom, 4)
					.background(.white)
					
					ScrollView {
						VStack(spacing: 0) {
							SecureLinkAccountSection()   // SecureLink: my account, state now, connection check, sign out
							// TODO: Wait for VFS fix
							/*
							HStack(alignment: .center) {
								Text("settings_security_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(securityIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									securityIsOpen.toggle()
								}
							}
							
							if securityIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 30) {
										HStack {
											VStack(alignment: .leading, spacing: 2) {
												Text("settings_security_enable_vfs_title")
													.default_text_style_700(styleSize: 15)
												Text("settings_security_enable_vfs_subtitle")
													.foregroundColor(Color.grayMain2c500)
													.default_text_style(styleSize: 14)
											}
											.layoutPriority(1)
											
											Toggle(isOn: $settingsViewModel.enableVfs) {
												EmptyView()
											}
											.toggleStyle(SwitchToggleStyle())
											.disabled(settingsViewModel.enableVfs)
										}
										
										/*
										Toggle("settings_security_prevent_screenshots_title", isOn: $isOn)
											.default_text_style_700(styleSize: 15)
										*/
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
								.padding(.horizontal, 20)
								.zIndex(-1)
								.transition(.move(edge: .top))
							}
							*/
							
							if false {   // SecureLink: no call/conversation settings – encryption and behaviour are fixed by the factory config
							HStack(alignment: .center) {
								Text("settings_calls_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(callsIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									callsIsOpen.toggle()
								}
							}
							
							if callsIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 30) {
										Toggle("settings_calls_adaptive_rate_control_title", isOn: $settingsViewModel.adaptiveRateControl)
											.default_text_style_700(styleSize: 15)
										
										/*
										Toggle("settings_calls_enable_video_title", isOn: $settingsViewModel.enableVideo)
											.default_text_style_700(styleSize: 15)
										
										Toggle("settings_calls_vibrate_while_ringing_title", isOn: $isOn)
											.default_text_style_700(styleSize: 15)
										*/
										
										Toggle("settings_calls_auto_record_title", isOn: $settingsViewModel.autoRecord)
											.default_text_style_700(styleSize: 15)
										
										/*
										Button {
										} label: {
											HStack {
												Text("settings_calls_change_ringtone_title")
													.default_text_style_700(styleSize: 15)
													.frame(maxWidth: .infinity, alignment: .leading)
												
												Image("arrow-square-out")
													.renderingMode(.template)
													.resizable()
													.foregroundStyle(Color.grayMain2c600)
													.frame(width: 25, height: 25, alignment: .leading)
													.padding(.trailing, 10)
											}
										}
										*/
										
										NavigationLink(destination: {
											SettingsAdvancedCallFragment(settingsViewModel: settingsViewModel)
										}, label: {
											HStack(alignment: .center) {
												Text("settings_advanced_calls")
													.default_text_style_700(styleSize: 15)
													.frame(maxWidth: .infinity, alignment: .leading)
												
												Spacer()
												
												Image("caret-right")
													.renderingMode(.template)
													.resizable()
													.foregroundStyle(Color.grayMain2c600)
													.frame(width: 25, height: 25, alignment: .leading)
											}
											.frame(maxWidth: .infinity)
											
										})
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
								.padding(.horizontal, 20)
								.zIndex(-2)
								.transition(.move(edge: .top))
								.background(Color.gray100)
							}
							
							HStack(alignment: .center) {
								Text("settings_conversations_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(conversationsIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									conversationsIsOpen.toggle()
								}
							}
							
							if conversationsIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 30) {
										Toggle("settings_conversations_auto_download_title", isOn: $settingsViewModel.autoDownload)
											.default_text_style_700(styleSize: 15)
										
										Toggle("settings_conversations_hide_message_content_in_notif_title", isOn: $settingsViewModel.hideNotificationContent)
											.default_text_style_700(styleSize: 15)
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
								.padding(.horizontal, 20)
								.zIndex(-3)
								.transition(.move(edge: .top))
								.background(Color.gray100)
							}
							
							}
							if false {   // SecureLink: no LDAP/CardDAV contacts, no meetings, no network settings
							HStack(alignment: .center) {
								Text("settings_contacts_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(contactsIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									contactsIsOpen.toggle()
								}
							}
							
							if contactsIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 20) {
										NavigationLink(destination: {
											LdapServerConfigurationFragment()
												.environmentObject(settingsViewModel)
										}, label: {
											HStack(alignment: .center) {
												Text("settings_contacts_add_ldap_server_title")
													.default_text_style_700(styleSize: 15)
													.frame(maxWidth: .infinity, alignment: .leading)
												
												Spacer()
												
												Image("caret-right")
													.renderingMode(.template)
													.resizable()
													.foregroundStyle(Color.grayMain2c600)
													.frame(width: 20, height: 20, alignment: .leading)
													.padding(.all, 10)
											}
											.frame(maxWidth: .infinity)
										})
										
										if !settingsViewModel.ldapServers.isEmpty {
											ForEach(settingsViewModel.ldapServers, id: \.self) { ldap in
												NavigationLink(destination: {
													LdapServerConfigurationFragment(url: ldap)
														.environmentObject(settingsViewModel)
												}, label: {
													HStack(alignment: .center) {
														Text(ldap)
															.default_text_style_700(styleSize: 15)
															.frame(maxWidth: .infinity, alignment: .leading)
														
														Spacer()
														
														Image("pencil-simple")
															.renderingMode(.template)
															.resizable()
															.foregroundStyle(Color.grayMain2c600)
															.frame(width: 20, height: 20, alignment: .leading)
															.padding(.all, 10)
													}
													.padding(.horizontal, 10)
													.frame(maxWidth: .infinity)
												})
											}
										}
										
										NavigationLink(destination: {
											CardDavAddressBookConfigurationFragment()
												.environmentObject(settingsViewModel)
										}, label: {
											HStack(alignment: .center) {
												Text("settings_contacts_add_carddav_server_title")
													.default_text_style_700(styleSize: 15)
													.frame(maxWidth: .infinity, alignment: .leading)
												
												Spacer()
												
												Image("caret-right")
													.renderingMode(.template)
													.resizable()
													.foregroundStyle(Color.grayMain2c600)
													.frame(width: 20, height: 20, alignment: .leading)
													.padding(.all, 10)
											}
											.frame(maxWidth: .infinity)
										})
										
										if !settingsViewModel.cardDavFriendsLists.isEmpty {
											ForEach(settingsViewModel.cardDavFriendsLists, id: \.self) { cardDavName in
												NavigationLink(destination: {
													CardDavAddressBookConfigurationFragment(name: cardDavName)
												  .environmentObject(settingsViewModel)
												}, label: {
													HStack(alignment: .center) {
														Text(cardDavName)
															.default_text_style_700(styleSize: 15)
															.frame(maxWidth: .infinity, alignment: .leading)
														
														Spacer()
														
														Image("pencil-simple")
															.renderingMode(.template)
															.resizable()
															.foregroundStyle(Color.grayMain2c600)
															.frame(width: 20, height: 20, alignment: .leading)
															.padding(.all, 10)
													}
													.padding(.horizontal, 10)
													.frame(maxWidth: .infinity)
												})
											}
										}
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
								.padding(.horizontal, 20)
								.zIndex(-4)
								.transition(.move(edge: .top))
								.background(Color.gray100)
							}
							
							HStack(alignment: .center) {
								Text("settings_meetings_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(meetingsIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									meetingsIsOpen.toggle()
								}
							}
							
							if meetingsIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 30) {
										Toggle("settings_meetings_show_past_meetings_title", isOn: $settingsViewModel.showPastMeetings)
											.default_text_style_700(styleSize: 15)
										
										VStack(alignment: .leading) {
											Text("settings_meetings_default_layout_title")
												.default_text_style_700(styleSize: 15)
												.padding(.bottom, -5)
											
											Menu {
												Button("settings_meetings_layout_active_speaker_label") { settingsViewModel.defaultLayout = String(localized: "settings_meetings_layout_active_speaker_label") }
												Button("settings_meetings_layout_mosaic_label") { settingsViewModel.defaultLayout = String(localized: "settings_meetings_layout_mosaic_label") }
											} label: {
												Text(settingsViewModel.defaultLayout)
													.default_text_style(styleSize: 15)
													.frame(maxWidth: .infinity, alignment: .leading)
												Image("caret-down")
													.renderingMode(.template)
													.resizable()
													.foregroundStyle(Color.grayMain2c500)
													.frame(width: 20, height: 20)
											}
											.frame(height: 25)
											.padding(.horizontal, 20)
											.padding(.vertical, 15)
											.cornerRadius(60)
											.overlay(
												RoundedRectangle(cornerRadius: 60)
													.inset(by: 0.5)
													.stroke(Color.gray200, lineWidth: 1)
											)
										}
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
								.padding(.horizontal, 20)
								.zIndex(-5)
								.transition(.move(edge: .top))
								.background(Color.gray100)
							}
							
							HStack(alignment: .center) {
								Text("settings_network_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(networkIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									networkIsOpen.toggle()
								}
							}
							
							if networkIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 30) {
										Toggle("settings_network_use_wifi_only", isOn: $settingsViewModel.useWifiOnly)
											.default_text_style_700(styleSize: 15)
										
										Toggle("settings_network_allow_ipv6", isOn: $settingsViewModel.allowIpv6)
											.default_text_style_700(styleSize: 15)
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
								.padding(.horizontal, 20)
								.zIndex(-6)
								.transition(.move(edge: .top))
								.background(Color.gray100)
							}
							
							}
							/*
							// Hide User interface (Dark mode)
							
							HStack(alignment: .center) {
								Text("manage_account_details_title")
									.default_text_style_800(styleSize: 18)
									.frame(maxWidth: .infinity, alignment: .leading)
								
								Spacer()
								
								Image(userInterfaceIsOpen ? "caret-up" : "caret-down")
									.renderingMode(.template)
									.resizable()
									.foregroundStyle(Color.grayMain2c600)
									.frame(width: 25, height: 25, alignment: .leading)
									.padding(.all, 10)
							}
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							.onTapGesture {
								withAnimation {
									userInterfaceIsOpen.toggle()
								}
							}
							
							if userInterfaceIsOpen {
								VStack(spacing: 0) {
									VStack(spacing: 30) {
										Toggle("account_settings_avpf_title", isOn: $isOn)
											.default_text_style_700(styleSize: 15)
										
										Toggle("account_settings_avpf_title", isOn: $isOn)
											.default_text_style_700(styleSize: 15)
									}
									.padding(.vertical, 30)
									.padding(.horizontal, 20)
								}
								.background(.white)
								.cornerRadius(15)
							 	.padding(.horizontal, 20)
								.zIndex(-7)
								.transition(.move(edge: .top))
							 	.background(Color.gray100)
							}
							*/
							
							if false {   // SecureLink: no advanced settings
							NavigationLink(destination: {
								SettingsAdvancedFragment(settingsViewModel: settingsViewModel)
							}, label: {
								HStack(alignment: .center) {
									Text("settings_advanced_title")
										.default_text_style_800(styleSize: 18)
										.frame(maxWidth: .infinity, alignment: .leading)
									
									Spacer()
									
									Image("caret-right")
										.renderingMode(.template)
										.resizable()
										.foregroundStyle(Color.grayMain2c600)
										.frame(width: 25, height: 25, alignment: .leading)
										.padding(.all, 10)
								}
								.frame(maxWidth: .infinity)
								
							})
							.padding(.vertical, 10)
							.padding(.horizontal, 20)
							.background(Color.gray100)
							}
							
							if false {   // SecureLink: no developer settings, whatever an older build stored
								NavigationLink(destination: {
									SettingsDeveloperFragment(settingsViewModel: settingsViewModel)
								}, label: {
									HStack(alignment: .center) {
										Text("settings_developer_title")
											.default_text_style_800(styleSize: 18)
											.frame(maxWidth: .infinity, alignment: .leading)
										
										Spacer()
										
										Image("caret-right")
											.renderingMode(.template)
											.resizable()
											.foregroundStyle(Color.grayMain2c600)
											.frame(width: 25, height: 25, alignment: .leading)
											.padding(.all, 10)
									}
									.frame(maxWidth: .infinity)
									
								})
								.padding(.vertical, 10)
								.padding(.horizontal, 20)
								.background(Color.gray100)
							}
						}
						.frame(maxWidth: SharedMainViewModel.shared.maxWidth)
						.frame(maxWidth: .infinity)
					}
					.background(Color.gray100)
				}
				.background(Color.gray100)
			}
			.navigationTitle("")
			.navigationBarHidden(true)
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}

// MARK: - SecureLink: "Můj účet" – what is true now, a connection check the user can read out to the administrator,
// and the one destructive action: sign out and wipe this phone's data (a new QR from the administrator is the way back).
struct SecureLinkAccountSection: View {
	@ObservedObject private var coreContext = CoreContext.shared
	@State private var checking = false
	@State private var checkLines: [String] = []
	@State private var showLogoutConfirm = false
	
	var account: AccountModel? { coreContext.accounts.first }
	
	var body: some View {
		VStack(spacing: 0) {
			HStack(alignment: .center) {
				Text("Můj účet")
					.default_text_style_800(styleSize: 18)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.padding(.vertical, 10)
			.padding(.horizontal, 20)
			.background(Color.gray100)
			
			VStack(spacing: 14) {
				row("Jméno", account?.displayName ?? "–")
				row("Účet", account?.address ?? "–")
				row("Stav", account?.humanReadableRegistrationState ?? NSLocalizedString("žádný účet", comment: ""))
				
				Button(action: { runCheck() }, label: {
					Text(checking ? LocalizedStringKey("Kontroluji…") : LocalizedStringKey("Zkontrolovat spojení"))
						.default_text_style_white_600(styleSize: 16)
						.frame(height: 32)
						.frame(maxWidth: .infinity)
				})
				.disabled(checking)
				.padding(.horizontal, 16)
				.padding(.vertical, 6)
				.background(Color.orangeMain500)
				.cornerRadius(60)
				
				if !checkLines.isEmpty {
					VStack(alignment: .leading, spacing: 6) {
						ForEach(checkLines, id: \.self) { line in
							Text(line)
								.default_text_style(styleSize: 14)
								.frame(maxWidth: .infinity, alignment: .leading)
						}
						Text("Když něco svítí ✗, přečtěte tyto řádky správci.")
							.default_text_style(styleSize: 12)
							.foregroundStyle(Color.grayMain2c500)
					}
				}
				
				Button(action: { showLogoutConfirm = true }, label: {
					Text("Odhlásit a smazat vše")
						.foregroundStyle(Color.redDanger500)
						.default_text_style_600(styleSize: 16)
						.frame(height: 32)
						.frame(maxWidth: .infinity)
				})
				.padding(.horizontal, 16)
				.padding(.vertical, 6)
				.overlay(RoundedRectangle(cornerRadius: 60).inset(by: 0.5).stroke(Color.redDanger500, lineWidth: 1))
			}
			.padding(.vertical, 20)
			.padding(.horizontal, 20)
			.background(.white)
			.cornerRadius(15)
			.padding(.horizontal, 20)
			.background(Color.gray100)
		}
		.alert("Odhlásit a smazat vše?", isPresented: $showLogoutConfirm) {
			Button("Smazat", role: .destructive) { coreContext.accounts.forEach { $0.logout() } }
			Button("Zrušit", role: .cancel) {}
		} message: {
			Text("Účet, zprávy, kontakty i klíče zmizí z tohoto telefonu. Zpátky se dostanete jen novým QR kódem od správce.")
		}
	}
	
	func row(_ key: String, _ value: String) -> some View {
		HStack(alignment: .top) {
			Text(LocalizedStringKey(key))
				.default_text_style(styleSize: 15)
				.foregroundStyle(Color.grayMain2c500)
			Spacer()
			Text(value)
				.default_text_style_700(styleSize: 15)
				.multilineTextAlignment(.trailing)
		}
	}
	
	func runCheck() {
		checking = true
		let regLine = ((account?.isRegistrered ?? false) ? "✓" : "✗") + " " + NSLocalizedString("Přihlášení k serveru:", comment: "") + " " + (account?.humanReadableRegistrationState ?? NSLocalizedString("žádný účet", comment: ""))
		let micLine = NSLocalizedString(AVAudioSession.sharedInstance().recordPermission == .granted ? "✓ Mikrofon povolen" : "✗ Mikrofon nepovolen – hovory nepůjdou", comment: "")
		let version = NSLocalizedString("Verze", comment: "") + " " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
		coreContext.doOnCoreQueue { core in
			var host = ""
			var port = 5061
			if let addr = core.defaultAccount?.params?.serverAddress, let d = addr.domain, !d.isEmpty {
				host = d
				if addr.port > 0 { port = addr.port }
			}
			var serverLine = NSLocalizedString("✗ Server: adresa účtu neznámá", comment: "")
			var notifLine = NSLocalizedString("✗ Oznámení: stav neznámý", comment: "")
			let group = DispatchGroup()
			if !host.isEmpty {
				group.enter()
				let lock = NSLock()
				var done = false
				let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp)
				let finish: (String) -> Void = { text in
					lock.lock(); defer { lock.unlock() }
					if done { return }
					done = true
					serverLine = text
					conn.cancel()
					group.leave()
				}
				conn.stateUpdateHandler = { state in
					switch state {
					case .ready: finish(String(format: NSLocalizedString("✓ Server %@ dosažitelný", comment: ""), "\(host):\(port)"))
					case .failed(let error): finish("✗ Server \(host):\(port): \(error.localizedDescription)")
					case .waiting(let error): finish(String(format: NSLocalizedString("✗ Server %@ nedostupný: %@", comment: ""), "\(host):\(port)", error.localizedDescription))
					default: break
					}
				}
				conn.start(queue: .global())
				DispatchQueue.global().asyncAfter(deadline: .now() + 5) { finish(String(format: NSLocalizedString("✗ Server %@ neodpovídá (5 s)", comment: ""), "\(host):\(port)")) }
			}
			group.enter()
			UNUserNotificationCenter.current().getNotificationSettings { settings in
				notifLine = NSLocalizedString(settings.authorizationStatus == .authorized ? "✓ Oznámení povolena" : "✗ Oznámení nepovolena – zamčený telefon nezazvoní", comment: "")
				group.leave()
			}
			group.notify(queue: .main) {
				self.checkLines = [regLine, serverLine, notifLine, micLine, version]
				self.checking = false
			}
		}
	}
}
