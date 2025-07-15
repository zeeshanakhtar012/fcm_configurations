fcm_utils

A robust and reusable Flutter package for seamless Firebase Cloud Messaging (FCM) integration, designed to ensure reliable FCM token handling across iOS (including simulators) and Android. Built with native platform channels (MethodChannel) for consistent token retrieval and management.
🚀 Features

Reliable Token Retrieval: Guarantees a valid FCM token for both real devices and iOS simulators.
Local Token Storage: Uses SharedPreferences for efficient token caching and reuse.
Native iOS Integration: Leverages MethodChannel to communicate FCM tokens from Swift to Dart.
Topic Subscription: Supports subscription to default (all_users) or custom topics.
Simulator-Friendly: Fully functional on iOS simulators for streamlined testing.
Permission Management: Handles notification permission requests and checks.
Clean Architecture: Easily integrates into modular Flutter architectures.


Note: This package uses platform channels to bridge native iOS (Swift) and Flutter, ensuring full control and visibility of FCM tokens in your Dart code.

📋 Installation
Add the following dependencies to your pubspec.yaml:
dependencies:
  firebase_messaging: ^14.0.0
  shared_preferences: ^2.0.0

Ensure Firebase is initialized in your main.dart before using fcm_utils:
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

📱 Usage
1. Initialize FCM
Call initializeFCM in your app's initialization logic (e.g., in a controller or main function):
import 'package:fcm_utils/fcm_utils.dart';

Future<void> initApp() async {
  await FCMUtils().initializeFCM();
}

This method:

Requests notification permissions.
Fetches or retrieves the cached FCM token.
Saves the token locally using SharedPreferences.
Subscribes the device to the all_users topic (or a custom topic).

2. Retrieve the Device Token
Access the FCM token anywhere in your app:
final token = await FCMUtils().getDeviceToken();
print('FCM Token: $token');

3. iOS Native Integration
For iOS, configure AppDelegate.swift to forward FCM tokens to Flutter via a MethodChannel. Refer to the example iOS configuration section or open an issue on the GitHub repository for a complete Swift snippet.
4. Folder Structure
Recommended structure for clean integration:
lib/
  └── utils/
       └── fcm_utils.dart

🧪 Testing on iOS Simulators
This package is optimized for iOS simulator testing, enabling full FCM token lifecycle verification without requiring a physical device. Simply initialize FCMUtils as described, and tokens will be generated and managed seamlessly.
🔧 iOS Configuration
To enable FCM on iOS:

Configure Firebase in your Xcode project (see Firebase iOS Setup).
Set up a MethodChannel in AppDelegate.swift to forward FCM tokens to Flutter.
Contact the package maintainer via a GitHub issue for a sample Swift implementation.

📅 Future Enhancements

Support for background and terminated-state push notification handling.
Comprehensive example project showcasing advanced use cases.
Android-specific platform channel fallback (if required).
Additional documentation for native Swift and Kotlin integration.

🤝 Contributing
Contributions are welcome! Please:

Fork the repository.
Create a feature branch (git checkout -b feature/awesome-feature).
Commit your changes (git commit -m 'Add awesome feature').
Push to the branch (git push origin feature/awesome-feature).
Open a pull request.

Report issues or suggest features on the GitHub Issues page.
📜 License
This project is licensed under the MIT License.
🌟 Support
If you find this package helpful, please give it a ⭐ on GitHub and share
