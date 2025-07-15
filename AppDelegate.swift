import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()

        // Set Firebase Messaging delegate
        Messaging.messaging().delegate = self

        // Request notification permissions
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional]
            UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
                if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
            }
        } else {
            let settings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }

        // Register for remote notifications
        application.registerForRemoteNotifications()

        // Register Flutter plugins
        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Handle APNs token registration
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    // Handle APNs registration failure
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            if let flutterEngine = (window?.rootViewController as? FlutterViewController)?.engine {
                let channel = FlutterMethodChannel(name: "com.test_fcm/notifications", binaryMessenger: flutterEngine.binaryMessenger)
                channel.invokeMethod("onFCMToken", arguments: token) { result in
                    if let error = result as? FlutterError {
                        print("Failed to send FCM token to Flutter: \(error.message ?? "Unknown error")")
                    }
                }
            } else {
                // Fallback: Store token and try sending later
                UserDefaults.standard.set(token, forKey: "pendingFCMToken")
            }
        }
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        // Check for pending FCM token and send it if Flutter is ready
        if let pendingToken = UserDefaults.standard.string(forKey: "pendingFCMToken"),
           let flutterEngine = (window?.rootViewController as? FlutterViewController)?.engine {
            let channel = FlutterMethodChannel(name: "com.test_fcm/notifications", binaryMessenger: flutterEngine.binaryMessenger)
            channel.invokeMethod("onFCMToken", arguments: pendingToken) { result in
                if result == nil || result is FlutterError {
                    print("Failed to send pending FCM token to Flutter")
                } else {
                    UserDefaults.standard.removeObject(forKey: "pendingFCMToken")
                }
            }
        }
    }
}
