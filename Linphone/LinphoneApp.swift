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
import CommonCrypto
import Security

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
		
		// SecureLink: the server sends this silent push to phones past half of their registration lifetime
		// (Flexisip register-wakeup). Being woken is not enough – refresh the registration now, while iOS lets us run.
		CoreContext.shared.doOnCoreQueue { core in
			Log.info("[Push] wake-up push: refreshing registration")
			core.refreshRegisters()
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
			completionHandler(UIBackgroundFetchResult.newData)
		}
	}
					 
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Set up notifications
		UNUserNotificationCenter.current().delegate = self
		// SecureLink: cover the app before iOS takes the app-switcher snapshot
		PrivacyCover.shared.start()

		return true
	}
	
	// Called when the user interacts with the notification
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		let userInfo = response.notification.request.content.userInfo
		
		// SecureLink: "new member in your contacts" – show the contacts, freshly loaded
		if userInfo["securelink"] as? String == "dir" {
			ContactsManager.shared.refreshCardDavContacts()
			DispatchQueue.main.async { SharedMainViewModel.shared.changeIndexView(indexViewInt: 0) }
		}
		
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
		
		// SecureLink: a chat room invite while the app is open needs no banner – the app joins the room itself.
		// The conference server re-invites a device into rooms it already has (new registration, app start).
		if let inviteAddr = userInfo["chat-room-addr"] as? String, !inviteAddr.isEmpty {
			completionHandler([])
			return
		}
		// SecureLink: somebody new in the contacts (server securelink-dirwatch) – load the directory now
		if userInfo["securelink"] as? String == "dir" {
			ContactsManager.shared.refreshCardDavContacts()
		}

		let strPeerAddr = userInfo["peer_addr"] as? String
		// SecureLink: with the app open the extension cannot read the message (the app owns the core), so the push says
		// only "Message received" and names no conversation – inside a conversation it just repeated what is on the
		// screen (two banners for the test line's two answers, Petr 18. 10.)
		if strPeerAddr == nil, userInfo["call-id"] != nil, displayedChatroomPeerAddr != nil {
			completionHandler([])
			return
		}
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
							completionHandler([])
							return
						}
						completionHandler([.banner, .sound])
					}
				}
			} else {
				completionHandler([])
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
			CaptureShield.shared.start()
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
				if coreContext.mCore != nil { ContactsManager.shared.refreshDirectoryIfStale(); ContactsManager.shared.startDirectoryTimer() }
				// SecureLink: messages from a blocked contact that the notification extension stored while the app slept
				if coreContext.mCore != nil { CoreContext.shared.doOnCoreQueue { core in SecureLinkAdmin.purgeBlockedMessages(core) } }
				// SecureLink: badge and Messages tab from the real count – after an account was removed they kept the old number
				if coreContext.mCore != nil { SharedMainViewModel.shared.updateUnreadMessagesCount() }
				// SecureLink: messages and attachments stay out of iCloud backups (also folders created since the last start)
				DispatchQueue.global(qos: .utility).async { SecureLinkPrivacy.excludeFromBackup() }
				// SecureLink: conversations others started get the 7-day disappearing messages too
				if coreContext.mCore != nil { CoreContext.shared.doOnCoreQueue { core in SecureLinkAdmin.enforceDisappearing(core) } }
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
	/// SecureLink: development builds (installed from the Mac by cable for testing) never lock – Release builds (TestFlight,
	/// App Store) always do; the switch is compiled out of them, so it cannot be forgotten (Petr 2. 11. 2026)
	static let enabled: Bool = {
		#if DEBUG
		return false
		#else
		return true
		#endif
	}()
	@Published var locked = AppLock.enabled || SecureLinkPin.isEnabled { didSet { updateWindow() } }
	/// the lock works when the build allows it (Release) or when the user chose the SecureLink PIN (also in development builds)
	static var active: Bool { enabled || SecureLinkPin.isEnabled }
	@Published var failed = false
	@Published var noPasscode = false          // the device has no passcode: a warning, then the app opens unprotected
	// SecureLink PIN lock (optional, Petr 2. 11. 2026): the user's own PIN instead of Face ID / the device passcode, plus an
	// emergency PIN that quietly wipes everything and leaves an empty app (SecureLinkPin, EmergencyWipe)
	@Published var pinMode = false
	@Published var pinWrong = false
	// kept across restarts: closing and reopening the app used to clear the one-minute block (Panel 2, 2. 11. 2026)
	private var wrongPins: Int {
		get { UserDefaults.standard.integer(forKey: "securelink_pin_wrong") }
		set { UserDefaults.standard.set(newValue, forKey: "securelink_pin_wrong") }
	}
	private var pinBlockedUntil: Date? {
		get { UserDefaults.standard.object(forKey: "securelink_pin_blocked_until") as? Date }
		set { UserDefaults.standard.set(newValue, forKey: "securelink_pin_blocked_until") }
	}
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
		guard AppLock.active else { return }
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
			locked = AppLock.active
		}
		backgroundSince = nil
		if locked {
			updateWindow()
			authenticate()
		}
	}
	
	func authenticate() {
		if SecureLinkPin.isEnabled {
			pinMode = true
			failed = false
			return
		}
		pinMode = false
		guard !authenticating else { return }
		authenticating = true
		failed = false
		let context = LAContext()
		context.localizedCancelTitle = NSLocalizedString("Zrušit", comment: "")
		var error: NSError?
		// deviceOwnerAuthentication = biometrics with the device passcode as fallback; no own PIN to forget
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			Log.error("[AppLock] no device authentication available: \(error?.localizedDescription ?? "?") – warning shown")
			authenticating = false
			failed = true
			noPasscode = (error as? LAError)?.code == .passcodeNotSet
			return
		}
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: NSLocalizedString("Odemknout SecureLink", comment: "")) { ok, err in
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

	/// the PIN pad's answer: the normal PIN opens the app, the emergency PIN wipes everything and opens an empty app,
	/// a wrong one counts – five in a row block the pad for a minute
	/// The emergency PIN works also while the pad is blocked (Panel 2: five wrong PINs used to disable it); the normal PIN
	/// does not, so the block still slows down guessing.
	func submitPin(_ pin: String) {
		let blocked = (pinBlockedUntil ?? .distantPast) > Date()
		let result = SecureLinkPin.check(pin)
		if blocked && result != .emergency { pinWrong = true; return }
		switch result {
		case .normal:
			wrongPins = 0
			pinWrong = false
			lastActivity = Date()
			locked = false
		case .emergency:
			Log.warn("[AppLock] emergency PIN")
			EmergencyWipe.run {
				self.wrongPins = 0
				self.pinWrong = false
				self.pinMode = false
				self.lastActivity = Date()
				self.locked = false
			}
		case .wrong:
			wrongPins += 1
			pinWrong = true
			if wrongPins >= 5 { pinBlockedUntil = Date().addingTimeInterval(60); wrongPins = 0 }
		}
	}

	// No passcode on the device: the app cannot lock itself. It warns on every opening and lets the user in –
	// refusing to open locked out anyone without a passcode, an App Review tester too (16. 10.)
	func continueWithoutPasscode() {
		Log.warn("[AppLock] opened without a device passcode")
		lastActivity = Date()
		locked = false
	}
}

// MARK: - SecureLink privacy cover (app switcher)

// iOS stores a screenshot of the app for the app switcher when it leaves the foreground; without a cover the open
// conversation was readable there (and on disk). The cover is a window like the lock screen, shown before the snapshot.
final class PrivacyCover {
	static let shared = PrivacyCover()
	private var window: UIWindow?

	private init() {
		// queue .main: the handlers run synchronously while the notification is posted, i.e. before iOS takes the snapshot
		NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
			self?.show()
		}
		NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
			self?.hide()
		}
	}

	func start() {}   // touching `shared` registers the observers

	private func show() {
		guard window == nil else { return }
		let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
		let cover = UIWindow(windowScene: scene)
		cover.windowLevel = .alert + 2   // above the lock screen too: the switcher shows only the logo
		cover.rootViewController = UIHostingController(rootView: PrivacyCoverView())
		cover.isHidden = false
		window = cover
	}

	private func hide() {
		window?.isHidden = true
		window = nil
	}
}

struct PrivacyCoverView: View {
	var body: some View {
		ZStack {
			Color.orangeMain500.ignoresSafeArea()
			Image("securelink-white")
				.resizable()
				.scaledToFit()
				.frame(width: 90, height: 90)
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
				if appLock.pinMode {
					PinPadView(title: NSLocalizedString("securelink_pin_enter", comment: ""),
							   error: appLock.pinWrong ? NSLocalizedString("securelink_pin_wrong", comment: "") : nil) { pin in
						appLock.submitPin(pin)
					}
				} else if appLock.noPasscode {
					Text("Toto zařízení nemá nastavený kód zámku. Bez něj si vaše konverzace přečte každý, kdo ho vezme do ruky. Kód nastavíte v Nastavení → Face ID a kód (nebo Touch ID a kód).")
						.default_text_style_white(styleSize: 15)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 30)
						.padding(.top, 10)
					Button(action: { appLock.continueWithoutPasscode() }, label: {
						Text("Pokračovat bez ochrany")
							.default_text_style_600(styleSize: 18)
							.frame(height: 35)
							.frame(maxWidth: 260)
					})
					.padding(.horizontal, 20)
					.padding(.vertical, 8)
					.background(Color.white)
					.cornerRadius(60)
					.padding(.top, 20)
				}
				if appLock.failed && !appLock.noPasscode && !appLock.pinMode {
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
	@AppStorage("securelink_terms_accepted") private var termsAccepted = false
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
						
						// SecureLink: terms (no objectionable content, reports answered within 24 h) accepted once after login
						if !termsAccepted {
							SecureLinkTermsView(accepted: $termsAccepted).zIndex(5)
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
					}
				}
			} else {
				SplashScreen()
			}
		}
		.onOpenURL { url in
			if SharedMainViewModel.shared.displayedConversation != nil && url.absoluteString.contains("securelink-message://") {
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

// SecureLink: terms of use shown once after the first login (App Review guideline 1.2)
struct SecureLinkTermsView: View {
	@Binding var accepted: Bool

	var body: some View {
		VStack(spacing: 20) {
			Text("securelink_terms_title")
				.default_text_style_800(styleSize: 20)
				.frame(maxWidth: .infinity, alignment: .leading)
			ScrollView {
				Text("securelink_terms_text")
					.default_text_style(styleSize: 16)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			let link = SecureLinkAdmin.setting(CoreContext.shared.mCore, "terms_url")
			if let url = URL(string: link), !link.isEmpty {
				Button {
					UIApplication.shared.open(url)
				} label: {
					Text("securelink_terms_read_full")
						.underline()
						.default_text_style(styleSize: 15)
				}
			}
			Button {
				accepted = true
			} label: {
				Text("securelink_terms_accept")
					.default_text_style_white_600(styleSize: 18)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 14)
			}
			.background(Color.orangeMain500)
			.cornerRadius(15)
		}
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color.white)
	}
}


// MARK: - SecureLink PIN (optional lock + emergency PIN, Petr 2. 11. 2026)

/// The user's own PIN for the app lock and an emergency PIN. Only salted PBKDF2-SHA256 hashes are kept, in the Keychain
/// (this device only, after the first unlock) – never the PINs.
enum SecureLinkPin {
	enum Result { case normal, emergency, wrong }
	private static let service = "cc.securelink.talk.pin"
	private static let rounds: UInt32 = 200_000

	static var isEnabled: Bool { read("normal") != nil }

	static func set(normal: String, emergency: String) -> Bool {
		guard normal != emergency, valid(normal), valid(emergency) else { return false }
		return store("normal", hash(normal)) && store("emergency", hash(emergency))
	}

	static func disable() {
		for account in ["normal", "emergency"] {
			SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
		}
	}

	static func valid(_ pin: String) -> Bool { (4...8).contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber } }

	static func check(_ pin: String) -> Result {
		if matches(pin, read("normal")) { return .normal }
		if matches(pin, read("emergency")) { return .emergency }
		return .wrong
	}

	private static func matches(_ pin: String, _ stored: Data?) -> Bool {
		guard let stored = stored, stored.count == 48 else { return false }
		let salt = stored.prefix(16), expected = stored.suffix(32)
		let got = derive(pin, salt: Data(salt))
		return got.count == 32 && zip(got, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
	}

	private static func hash(_ pin: String) -> Data {
		var salt = Data(count: 16)
		_ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
		return salt + derive(pin, salt: salt)
	}

	private static func derive(_ pin: String, salt: Data) -> Data {
		var out = Data(count: 32)
		let pw = Array(pin.utf8).map { Int8(bitPattern: $0) }
		let status = out.withUnsafeMutableBytes { o in
			salt.withUnsafeBytes { s in
				CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.count, s.bindMemory(to: UInt8.self).baseAddress, salt.count,
									 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, o.bindMemory(to: UInt8.self).baseAddress, 32)
			}
		}
		return status == kCCSuccess ? out : Data()
	}

	private static func store(_ account: String, _ value: Data) -> Bool {
		let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
		SecItemDelete(query as CFDictionary)
		var add = query
		add[kSecValueData] = value
		add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
	}

	private static func read(_ account: String) -> Data? {
		let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
									  kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
		var item: CFTypeRef?
		return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
	}
}

/// Emergency PIN: every account goes with its data (conversations, calls, directory, LIME identity), then the app's data
/// files are deleted – on iOS every file has its own key, discarded with the file, so what was deleted cannot be read
/// back. The app then looks freshly installed (no account, no PIN). Core queue for the core, main queue for `done`.
/// Screen recording, mirroring or AirPlay: the app's content is covered while the screen is captured (iOS cannot forbid
/// screenshots – Android can and does). Panel 2, 2. 11. 2026.
final class CaptureShield {
	static let shared = CaptureShield()
	private var window: UIWindow?
	private var started = false

	func start() {
		guard !started else { return }
		started = true
		NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
			self?.update()
		}
		update()
	}

	private func update() {
		let captured = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
			.contains { $0.screen.isCaptured }
		if captured {
			guard window == nil,
				  let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
			Log.info("[CaptureShield] screen is captured – content covered")
			let w = UIWindow(windowScene: scene)
			w.windowLevel = .alert + 2
			w.rootViewController = UIHostingController(rootView: CaptureShieldView())
			w.isHidden = false
			window = w
		} else if window != nil {
			Log.info("[CaptureShield] capture ended")
			window?.isHidden = true
			window = nil
		}
	}
}

struct CaptureShieldView: View {
	var body: some View {
		ZStack {
			Color(red: 0.12, green: 0.37, blue: 0.75).ignoresSafeArea()
			Text("SecureLink").font(.system(size: 28, weight: .semibold)).foregroundColor(.white)
		}
	}
}

enum EmergencyWipe {
	static func run(done: @escaping () -> Void) {
		CoreContext.shared.doOnCoreQueue { core in
			for account in core.accountList { SecureLinkAccounts.wipeAccount(core, account) }
			core.clearAllAuthInfo()
			let dataDir = (core.config?.getString(section: "storage", key: "uri", defaultString: "") ?? "")
			let dirs = Set([dataDir, core.callLogsDatabasePath ?? "", core.friendsDatabasePath ?? "", core.zrtpSecretsFile ?? ""]
				.filter { !$0.isEmpty }.map { ($0 as NSString).deletingLastPathComponent })
			var removed = 0
			for dir in dirs {
				for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name != "securelink-ca.pem" {
					if (try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(name))) != nil { removed += 1 }
				}
			}
			for url in [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
						FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
						URL(fileURLWithPath: NSTemporaryDirectory())].compactMap({ $0 }) {
				for item in (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] {
					if (try? FileManager.default.removeItem(at: item)) != nil { removed += 1 }
				}
			}
			if let cfg = core.config {
				for section in ["securelink_account", "securelink_names", "app"] { cfg.cleanSection(section: section) }
				try? cfg.sync()
			}
			SecureLinkPin.disable()
			// logs and the app's settings too: they held account names, numbers and addresses (Panel 2, 2. 11. 2026)
			Core.resetLogCollection()
			let groupDir = Factory.Instance.getDataDir(context: UnsafeMutablePointer<Int8>(mutating: (SharedMainViewModel.appGroupName as NSString).utf8String))
			for name in (try? FileManager.default.contentsOfDirectory(atPath: groupDir)) ?? [] where name.hasSuffix(".log") {
				if (try? FileManager.default.removeItem(atPath: (groupDir as NSString).appendingPathComponent(name))) != nil { removed += 1 }
			}
			if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
			UserDefaults(suiteName: SharedMainViewModel.appGroupName)?.removePersistentDomain(forName: SharedMainViewModel.appGroupName)
			UserDefaults.standard.set(true, forKey: "securelink_old_logs_removed")
			DispatchQueue.main.async { done() }
		}
	}
}

/// Digits, delete and OK – used by the lock screen and when setting the PIN up
struct PinPadView: View {
	let title: String
	let error: String?
	let onSubmit: (String) -> Void
	@State private var pin = ""

	var body: some View {
		VStack(spacing: 14) {
			Text(title).default_text_style_white_600(styleSize: 17)
			Text(String(repeating: "●", count: pin.count) + String(repeating: "○", count: max(0, 4 - pin.count)))
				.font(.system(size: 28)).foregroundColor(.white).frame(height: 36)
			if let error = error { Text(error).default_text_style_white(styleSize: 14) }
			ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "OK"]], id: \.self) { row in
				HStack(spacing: 22) {
					ForEach(row, id: \.self) { key in
						Button(action: { press(key) }, label: {
							Text(key).font(.system(size: 26, weight: .semibold)).foregroundColor(Color.orangeMain500)
								.frame(width: 72, height: 72).background(Color.white).clipShape(Circle())
						})
					}
				}
			}
		}
		.padding(.top, 10)
	}

	private func press(_ key: String) {
		switch key {
		case "⌫": if !pin.isEmpty { pin.removeLast() }
		case "OK": if !pin.isEmpty { onSubmit(pin); pin = "" }
		default: if pin.count < 8 { pin += key }
		}
	}
}


/// Turning the SecureLink PIN lock on (normal PIN twice, emergency PIN twice) or off (normal PIN) – from About
struct PinSetupView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var step = 0          // 0 intro, 1 normal, 2 normal again, 3 emergency, 4 emergency again; 10 = turning off
	@State private var normal = ""
	@State private var emergency = ""
	@State private var error: String?
	let turningOff: Bool

	var body: some View {
		ZStack {
			Color.orangeMain500.ignoresSafeArea()
			VStack(spacing: 16) {
				if step == 0 && !turningOff {
					Text("securelink_pin_setup_title").default_text_style_white_700(styleSize: 22)
					Text("securelink_pin_setup_text").default_text_style_white(styleSize: 15)
						.multilineTextAlignment(.leading).padding(.horizontal, 24)
					Button(action: { step = 1 }, label: {
						Text("securelink_pin_setup_start").default_text_style_600(styleSize: 18).frame(height: 35).frame(maxWidth: 240)
					}).padding(.vertical, 8).background(Color.white).cornerRadius(60)
				} else {
					PinPadView(title: NSLocalizedString(titleKey, comment: ""), error: error) { pin in submit(pin) }
				}
				Button(action: { dismiss() }, label: {
					Text("Zrušit").default_text_style_white_600(styleSize: 16)
				}).padding(.top, 8)
			}
		}
		.onAppear { if turningOff { step = 10 } }
	}

	private var titleKey: String {
		switch step {
		case 1: return "securelink_pin_new"
		case 2: return "securelink_pin_new_again"
		case 3: return "securelink_pin_emergency"
		case 4: return "securelink_pin_emergency_again"
		default: return "securelink_pin_enter"
		}
	}

	private func submit(_ pin: String) {
		error = nil
		switch step {
		case 1:
			guard SecureLinkPin.valid(pin) else { error = NSLocalizedString("securelink_pin_rules", comment: ""); return }
			normal = pin; step = 2
		case 2:
			guard pin == normal else { error = NSLocalizedString("securelink_pin_mismatch", comment: ""); step = 1; return }
			step = 3
		case 3:
			guard SecureLinkPin.valid(pin) else { error = NSLocalizedString("securelink_pin_rules", comment: ""); return }
			guard pin != normal else { error = NSLocalizedString("securelink_pin_same", comment: ""); return }
			emergency = pin; step = 4
		case 4:
			guard pin == emergency else { error = NSLocalizedString("securelink_pin_mismatch", comment: ""); step = 3; return }
			if SecureLinkPin.set(normal: normal, emergency: emergency) {
				Log.info("[AppLock] SecureLink PIN lock switched on")
				dismiss()
			} else { error = NSLocalizedString("securelink_pin_rules", comment: ""); step = 1 }
		default:   // turning off: the normal PIN only (the emergency PIN here would be a trap – it is refused)
			if SecureLinkPin.check(pin) == .normal {
				SecureLinkPin.disable()
				Log.info("[AppLock] SecureLink PIN lock switched off")
				dismiss()
			} else { error = NSLocalizedString("securelink_pin_wrong", comment: "") }
		}
	}
}


/// "SecureLink PIN lock: on/off" in About – a view of its own (About's body was already too big for the type checker)
struct PinLockRow: View {
	@State private var showSetup = false
	@State private var on = SecureLinkPin.isEnabled

	var body: some View {
		Button {
			showSetup = true
		} label: {
			HStack {
				Image("password")
					.renderingMode(.template)
					.resizable()
					.foregroundStyle(Color.orangeMain500)
					.frame(width: 30, height: 30)
				VStack {
					Text("securelink_pin_row_title")
						.default_text_style_700(styleSize: 14)
						.frame(maxWidth: .infinity, alignment: .leading)
					Text(LocalizedStringKey(on ? "securelink_pin_row_on" : "securelink_pin_row_off"))
						.default_text_style(styleSize: 14)
						.frame(maxWidth: .infinity, alignment: .leading)
				}
				.padding(.horizontal, 5)
			}
		}
		.sheet(isPresented: $showSetup, onDismiss: { on = SecureLinkPin.isEnabled }) {
			PinSetupView(turningOff: on)
		}
	}
}
