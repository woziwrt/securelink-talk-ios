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
import LocalAuthentication
import linphonesw
import UserNotifications
import Intents
import PushKit

let accountTokenNotification = Notification.Name("AccountCreationTokenReceived")
var displayedChatroomPeerAddr: String?

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
	
	var launchNotificationCallId: String?
	var launchNotificationPeerAddr: String?
	var launchNotificationLocalAddr: String?
	
	var coreContext: CoreContext?
 	var navigationManager: NavigationManager?
	
	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		let tokenStr = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
		Log.info("Received remote push token : \(tokenStr)")
		if let coreContext = coreContext {
			coreContext.doOnCoreQueue { core in
				Log.info("Forwarding remote push token to core")
				core.didRegisterForRemotePushWithStringifiedToken(deviceTokenStr: tokenStr + ":remote")
			}
		}
	}
	
	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		Log.error("Failed to register for push notifications : \(error.localizedDescription)")
	}
	
	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		Log.info("Received background push notification, payload = \(userInfo.description)")
		let creationToken = (userInfo["customPayload"] as? NSDictionary)?["token"] as? String
		if let creationToken = creationToken {
			NotificationCenter.default.post(name: accountTokenNotification, object: nil, userInfo: ["token": creationToken])
		}
		
		completionHandler(UIBackgroundFetchResult.newData)
	}
					 
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Set up notifications
		UNUserNotificationCenter.current().delegate = self

		return true
	}
	
	// Called when the user interacts with the notification
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let userInfo = response.notification.request.content.userInfo
		
		if let callId = userInfo["CallId"] as? String, let peerAddr = userInfo["peer_addr"] as? String, let localAddr = userInfo["local_addr"] as? String {
			if self.navigationManager != nil {
				self.navigationManager!.selectedCallId = callId
				self.navigationManager!.peerAddr = peerAddr
				self.navigationManager!.localAddr = localAddr
			} else {
				launchNotificationCallId = callId
				launchNotificationPeerAddr = peerAddr
				launchNotificationLocalAddr = localAddr
			}
		}
		
		completionHandler()
	}
	
	// Display notifications on foreground
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		let userInfo = notification.request.content.userInfo
		Log.info("Received push notification in foreground, payload= \(userInfo)")
		
		let strPeerAddr = userInfo["peer_addr"] as? String
		if strPeerAddr == nil {
			completionHandler([.banner, .sound])
		} else {
			// Only display notification if we're not in the chatroom they come from
			if displayedChatroomPeerAddr != strPeerAddr {
				if let coreContext = coreContext {
					coreContext.doOnCoreQueue { core in
						let nilParams: ConferenceParams? = nil
						if 	let peerAddr = try? Factory.Instance.createAddress(addr: strPeerAddr!)
								, let chatroom = core.searchChatRoom(params: nilParams, localAddr: nil, remoteAddr: peerAddr, participants: nil), chatroom.muted {
							Log.info("message comes from a muted chatroom, ignore it")
							return
						}
						completionHandler([.banner, .sound])
					}
				}
			}
		}
	}
	
	func application(_ application: UIApplication,
					 continue userActivity: NSUserActivity,
					 restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
		
		guard let interaction = userActivity.interaction,
			  let intent = interaction.intent as? INStartCallIntent,
			  let person = intent.contacts?.first,
			  let number = person.personHandle?.value else { return false }

		let isVideo = intent.callCapability == .videoCall
		
		Log.info("[AppDelegate][INStartCallIntent] Generic call intent received for number: \(number) isVideo: \(isVideo)")

		CoreContext.shared.doOnCoreQueue { core in
			if let address = core.interpretUrl(url: number, applyInternationalPrefix: LinphoneUtils.applyInternationalPrefix(core: core)) {
				TelecomManager.shared.doCallOrJoinConf(address: address, isVideo: isVideo)
			}
		}
		
		return true
	}
	
	func applicationWillTerminate(_ application: UIApplication) {
		Log.info("IOS applicationWillTerminate")
		if let coreContext = coreContext {
			coreContext.doOnCoreQueue(synchronous: true) { core in
				Log.info("applicationWillTerminate - Stopping linphone core")
				MagicSearchSingleton.shared.destroyMagicSearch()
				if core.globalState != GlobalState.Off {
					core.stop()
				} else {
					Log.info("applicationWillTerminate - Core already stopped")
				}
			}
		}
	}
}

@main
struct LinphoneApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

	@State private var configAvailable = AppServices.configIfAvailable != nil
	private let earlyPushDelegate = EarlyPushkitDelegate()
	private let voipRegistry = PKPushRegistry(queue: coreQueue)

	init() {
#if DEBUG
		LinphoneApp.applyUITestMDMConfigIfNeeded()
#endif
		if !configAvailable {
			voipRegistry.delegate = earlyPushDelegate
			voipRegistry.desiredPushTypes = [.voIP]
			waitForConfig()
		} else {
			let _ = CoreContext.shared
		}
	}

#if DEBUG
	/// UI-test hook: reads `UITEST_MDM_CONFIG` (JSON) or `UITEST_MDM_CONFIG_CLEAR=1` from
	/// the launch environment and writes it to the managed config key before MDMManager runs.
	/// Only active in DEBUG builds.
	private static func applyUITestMDMConfigIfNeeded() {
		let env = ProcessInfo.processInfo.environment
		let key = "com.apple.configuration.managed"
		if env["UITEST_MDM_CONFIG_CLEAR"] == "1" {
			UserDefaults.standard.removeObject(forKey: key)
			return
		}
		guard let json = env["UITEST_MDM_CONFIG"],
			  let data = json.data(using: .utf8),
			  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return
		}
		UserDefaults.standard.set(dict, forKey: key)
	}
#endif

	var body: some Scene {
		WindowGroup {
			if configAvailable {
				AppView(delegate: delegate)
			} else {
				SplashScreen(showSpinner: true)
					.onAppear {
						waitForConfig()
				}
			}
		}
	}

	private func waitForConfig() {
		if AppServices.configIfAvailable != nil {
			let _ = CoreContext.shared
			configAvailable = true
		} else {
			Log.warn("AppServices.config not available yet, retrying in 1s...")
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				waitForConfig()
			}
		}
	}
}

struct AppView: View {
	@Environment(\.scenePhase) var scenePhase
	let delegate: AppDelegate

	@StateObject private var coreContext = CoreContext.shared
	@StateObject private var navigationManager = NavigationManager()
	@StateObject private var telecomManager = TelecomManager.shared
	@StateObject private var sharedMainViewModel = SharedMainViewModel.shared

	@StateObject private var appLock = AppLock.shared
	
	var body: some View {
		ZStack {
			RootView(
				coreContext: coreContext,
				telecomManager: telecomManager,
				sharedMainViewModel: sharedMainViewModel,
				navigationManager: navigationManager,
				appDelegate: delegate
			)
			.environmentObject(coreContext)
			.environmentObject(navigationManager)
			.environmentObject(telecomManager)
			.environmentObject(sharedMainViewModel)
			// SecureLink: touches are counted by TouchSpy (UIKit) – a SwiftUI DragGesture(minimumDistance: 0) here
			// swallowed every button tap on iOS 15.
			
			// SecureLink: the lock screen lives in its own window above everything (see AppLock) – a view in this
			// ZStack stayed hidden under screens that iOS presents in a higher layer (e.g. an open conversation)
		}
		.onAppear {
			appLock.lockNow()
			requestPermissionsIfLoggedIn()
		}
		.onChange(of: coreContext.loggedIn) { _ in
			requestPermissionsIfLoggedIn()
		}
		// SecureLink: the screen may stay awake only during a call. The call view's onDisappear did not always run,
		// so the phone never auto-locked afterwards and the app lock never kicked in.
		.onChange(of: telecomManager.callInProgress) { inCall in
			UIApplication.shared.isIdleTimerDisabled = inCall && coreContext.activeCalls > 0
		}
		.onChange(of: scenePhase) { newPhase in
			switch newPhase {
			case .active:
				// A stuck "call in progress" flag must not keep the screen awake or the lock away: ask the core too.
				let inCall = telecomManager.callInProgress && coreContext.activeCalls > 0
				UIApplication.shared.isIdleTimerDisabled = inCall
				Log.info("[AppLock] foreground: inCall=\(inCall) flag=\(telecomManager.callInProgress) calls=\(coreContext.activeCalls)")
				appLock.enteredForeground()
				// SecureLink: a new member of the circle shows up at the next foreground, not only after an app restart
				if coreContext.mCore != nil { ContactsManager.shared.refreshCardDavContacts() }
			case .background:
				appLock.enteredBackground()
			default:
				break
			}
			if !telecomManager.callInProgress {
				switch newPhase {
				case .active:
					Log.info("Entering foreground")
					coreContext.onEnterForeground()
				case .background:
					Log.info("Entering background")
					coreContext.onEnterBackground()
				default:
					break
				}
			}
		}
	}
}

extension AppView {
	// SecureLink: the Linphone welcome/permissions pages are gone, so ask for notifications (messages, badge) and the
	// microphone (calls) ourselves, once the account is in. iOS asks the user only the first time; later calls are silent.
	func requestPermissionsIfLoggedIn() {
		guard coreContext.loggedIn else { return }
		PermissionManager.shared.pushNotificationRequestPermission {
			Log.info("[SecureLink] notification permission asked")
		}
		PermissionManager.shared.microphoneRequestPermission()
	}
}

// MARK: - SecureLink app lock (Face ID / Touch ID / device passcode)

final class AppLock: ObservableObject {
	static let shared = AppLock()
	@Published var locked = true { didSet { updateWindow() } }
	@Published var failed = false
	@Published var noPasscode = false          // the phone has no passcode: the app refuses to open and says why
	private var backgroundSince: Date?
	private var authenticating = false
	private let graceSeconds: TimeInterval = 30
	private let idleSeconds: TimeInterval = 300   // foreground without a touch (or keyboard) → lock
	private var lastActivity = Date()
	private var keyboardVisible = false
	private var idleTimer: Timer?
	private var lockWindow: UIWindow?
	
	private init() {
		// Lock after 5 min without any touch while the app is on screen – the phone's own auto-lock may be off ("Never")
		idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.checkIdle() }
		NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
			self?.keyboardVisible = true; self?.touched()
		}
		NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
			self?.keyboardVisible = false; self?.touched()
		}
	}
	
	func touched() { lastActivity = Date() }
	
	// Sees every touch in the app's main window without taking it from the view underneath.
	private final class TouchSpy: UIGestureRecognizer, UIGestureRecognizerDelegate {
		override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
			AppLock.shared.touched()
			state = .failed
		}
		func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
	}
	private var spiedWindows: [ObjectIdentifier] = []
	
	func watchTouches() {
		for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
			for window in scene.windows where window !== lockWindow && !spiedWindows.contains(ObjectIdentifier(window)) {
				let spy = TouchSpy()
				spy.cancelsTouchesInView = false
				spy.delaysTouchesBegan = false
				spy.delaysTouchesEnded = false
				spy.delegate = spy
				window.addGestureRecognizer(spy)
				spiedWindows.append(ObjectIdentifier(window))
				Log.info("[AppLock] watching touches in window \(window)")
			}
		}
	}
	
	private func checkIdle() {
		guard !locked, !keyboardVisible, UIApplication.shared.applicationState == .active else { return }
		let inCall = TelecomManager.shared.callInProgress && CoreContext.shared.activeCalls > 0
		if !inCall && Date().timeIntervalSince(lastActivity) >= idleSeconds {
			Log.info("[AppLock] no touch for \(Int(idleSeconds)) s – locking")
			lockNow()
		}
	}
	
	// The lock screen is a separate UIWindow above alerts, so nothing the app presents can sit on top of it.
	func updateWindow() {
		DispatchQueue.main.async {
			let inCall = TelecomManager.shared.callInProgress && CoreContext.shared.activeCalls > 0
			Log.info("[AppLock] window update: locked=\(self.locked) inCall=\(inCall)")
			self.watchTouches()
			if self.locked && !inCall {
				guard self.lockWindow == nil else { return }
				let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
				guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
				let window = UIWindow(windowScene: scene)
				window.windowLevel = .alert + 1
				window.backgroundColor = .clear
				window.rootViewController = UIHostingController(rootView: AppLockView(appLock: self))
				window.isHidden = false
				self.lockWindow = window
			} else {
				self.lockWindow?.isHidden = true
				self.lockWindow = nil
			}
		}
	}
	
	func lockNow() {
		locked = true
		failed = false
		updateWindow()
		authenticate()
	}
	
	func enteredBackground() {
		backgroundSince = Date()
	}
	
	func enteredForeground() {
		let away = backgroundSince.map { Date().timeIntervalSince($0) } ?? -1
		Log.info("[AppLock] entered foreground after \(Int(away)) s in background, locked=\(locked)")
		if away >= graceSeconds {
			locked = true
		}
		backgroundSince = nil
		if locked {
			updateWindow()
			authenticate()
		}
	}
	
	func authenticate() {
		guard !authenticating else { return }
		authenticating = true
		failed = false
		let context = LAContext()
		context.localizedCancelTitle = "Zrušit"
		var error: NSError?
		// deviceOwnerAuthentication = biometrics with the device passcode as fallback; no own PIN to forget
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			Log.error("[AppLock] no device authentication available: \(error?.localizedDescription ?? "?") – app stays locked")
			authenticating = false
			failed = true
			noPasscode = (error as? LAError)?.code == .passcodeNotSet
			return
		}
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Odemknout SecureLink") { ok, err in
			DispatchQueue.main.async {
				self.authenticating = false
				if ok {
					self.noPasscode = false
					self.lastActivity = Date()
					self.locked = false
				} else {
					self.failed = true
					Log.warn("[AppLock] authentication failed: \(err?.localizedDescription ?? "?")")
				}
			}
		}
	}
}

struct AppLockView: View {
	@ObservedObject var appLock: AppLock
	
	var body: some View {
		ZStack {
			Color.orangeMain500.ignoresSafeArea()
			VStack(spacing: 18) {
				Image("securelink-white")
					.resizable()
					.scaledToFit()
					.frame(width: 90, height: 90)
				Text("SecureLink")
					.default_text_style_white_700(styleSize: 26)
				Text("Zamčeno")
					.default_text_style_white_600(styleSize: 16)
				if appLock.noPasscode {
					Text("Tento iPhone nemá nastavený kód zámku. SecureLink jde otevřít jen na telefonu s kódem (Nastavení → Face ID a kód / Touch ID a kód).")
						.default_text_style_white(styleSize: 15)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 30)
						.padding(.top, 10)
				}
				if appLock.failed && !appLock.noPasscode {
					Button(action: { appLock.authenticate() }, label: {
						Text("Odemknout")
							.default_text_style_600(styleSize: 18)
							.frame(height: 35)
							.frame(maxWidth: 200)
					})
					.padding(.horizontal, 20)
					.padding(.vertical, 8)
					.background(Color.white)
					.cornerRadius(60)
					.padding(.top, 20)
				}
			}
		}
	}
}

struct RootView: View {
	@ObservedObject var coreContext: CoreContext
	@ObservedObject var telecomManager: TelecomManager
	@ObservedObject var sharedMainViewModel: SharedMainViewModel
	@ObservedObject var navigationManager: NavigationManager
	@State private var pendingURL: URL?
	let appDelegate: AppDelegate

	var body: some View {
		Group {
			if coreContext.coreHasStartedOnce {
				if showWelcome {
					ZStack {
						WelcomeView()
						ToastView().zIndex(3)
					}
					.onAppear {
						appDelegate.coreContext = coreContext
					}
				} else if showAssistant {
					ZStack {
						AssistantView()
						ToastView().zIndex(3)
					}
					.onAppear {
						appDelegate.coreContext = coreContext
					}
					
					if coreContext.coreIsStarted {
						   VStack {} // Force trigger .onAppear
							   .onAppear {
								   if let url = pendingURL {
									   URIHandler.handleURL(url: url)
									   pendingURL = nil
								   }
							   }
					   }
				} else {
					ZStack {
						MainViewSwitcher(
							coreContext: coreContext,
							navigationManager: navigationManager,
							sharedMainViewModel: sharedMainViewModel,
							pendingURL: $pendingURL,
							appDelegate: appDelegate
						)
						
						if coreContext.coreIsStarted {
							VStack {} // Force trigger .onAppear
								.onAppear {
									if let url = pendingURL {
										URIHandler.handleURL(url: url)
										pendingURL = nil
									}
								}
						}
					}
				}
			} else {
				SplashScreen()
			}
		}
		.onOpenURL { url in
			if SharedMainViewModel.shared.displayedConversation != nil && url.absoluteString.contains("linphone-message://") {
				SharedMainViewModel.shared.displayedConversation = nil
			}
			if coreContext.coreIsStarted {
				URIHandler.handleURL(url: url)
			} else {
				pendingURL = url
			}
		}
		.onContinueUserActivity("INStartCallIntent") { activity in
			guard let interaction = activity.interaction,
				  let intent = interaction.intent as? INStartCallIntent,
				  let person = intent.contacts?.first,
				  let number = person.personHandle?.value else { return }
			
			let isVideo = intent.callCapability == .videoCall
			
			Log.info("[INStartCallIntent] Generic call intent received for number: \(number) isVideo: \(isVideo)")
			
			coreContext.doOnCoreQueue { core in
				if let address = core.interpretUrl(url: number, applyInternationalPrefix: LinphoneUtils.applyInternationalPrefix(core: core)) {
					telecomManager.doCallOrJoinConf(address: address, isVideo: isVideo)
				}
			}
		}
	}
	
	
	var showWelcome: Bool {
		false   // SecureLink: no welcome pages, the first screen is the assistant with the QR scanner
	}

	var showAssistant: Bool {
		(coreContext.codeScannerIsOpen && coreContext.accounts.isEmpty)
		|| (coreContext.coreIsStarted && coreContext.accounts.isEmpty)
		|| sharedMainViewModel.displayProfileMode
	}
}

struct MainViewSwitcher: View {
	let coreContext: CoreContext
	let navigationManager: NavigationManager
	let sharedMainViewModel: SharedMainViewModel
	@Binding var pendingURL: URL?
	let appDelegate: AppDelegate
	@ObservedObject private var colors = ColorProvider.shared

	var body: some View {
		selectedMainView()
	}
	
	@ViewBuilder
	func selectedMainView() -> some View {
		ContentView()
			.onAppear {
				appDelegate.coreContext = coreContext
				appDelegate.navigationManager = navigationManager
				
				if let callId = appDelegate.launchNotificationCallId,
				   let peerAddr = appDelegate.launchNotificationPeerAddr,
				   let localAddr = appDelegate.launchNotificationLocalAddr {
					navigationManager.openChatRoom(callId: callId, peerAddr: peerAddr, localAddr: localAddr)
				}
			}
			.id(colors.theme.name)
	}
}
