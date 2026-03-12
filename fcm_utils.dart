import 'dart:io' show Platform;

import 'package:balochtransport/constants/api_endpoints.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_utils.dart';

class FCMUtils {
  static final FCMUtils _instance = FCMUtils._internal();
  factory FCMUtils() => _instance;
  FCMUtils._internal();

  static const _tokenKey = 'device_token';
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  String? _deviceToken;

  /// ----------------------------------------------------------
  /// PERMISSIONS
  /// ----------------------------------------------------------
  Future<bool> checkAndRequestPermissions() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      appLog('Current permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        appLog('✅ Notification permission already granted (full authorization)');
        return true;
      }

      // Request EXPLICIT permission (not provisional)
      appLog('Requesting notification permissions...');
      final newSettings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false, // Request explicit permission
      );

      final granted = newSettings.authorizationStatus == AuthorizationStatus.authorized;

      appLog('Notification permission result: ${newSettings.authorizationStatus}');
      appLog('Permission granted: $granted');

      return granted;
    } catch (e) {
      appLog('Permission error: $e');
      return false;
    }
  }

  /// ----------------------------------------------------------
  /// INITIALIZE FCM (ANDROID + IOS)
  /// ----------------------------------------------------------
  Future<void> initializeFCM() async {
    try {
      appLog('🚀 Starting FCM initialization...');

      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        appLog('❌ FCM init aborted: permission denied');
        return;
      }

      appLog('✅ Permissions granted, proceeding with FCM setup');

      await _loadStoredToken();
      await _fetchAndSaveTokenIfNeeded();
      _listenForTokenRefresh();
      await _subscribeToDefaultTopic();

      appLog('✅ FCM initialization complete');
    } catch (e) {
      appLog('❌ FCM initialization error: $e');
    }
  }

  /// ----------------------------------------------------------
  /// TOKEN FETCHING AND SAVING
  /// ----------------------------------------------------------
  Future<void> _fetchAndSaveTokenIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      appLog('Fetching FCM token...');
      if (Platform.isIOS) {
        await Future.delayed(const Duration(seconds: 2));
        appLog('iOS: Waited for APNS token registration');
      }

      final token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        appLog('FCM token is null or empty!');
        if (Platform.isIOS) {
          appLog('⚠️  iOS Debug Checklist:');
          appLog('   1. Check Xcode console for "APNs token received"');
          appLog('   2. Verify APNS credentials in Firebase Console');
          appLog('   3. Ensure running on real device (not simulator)');
          appLog('   4. Check Bundle ID matches Firebase project');
        }
        return;
      }

      if (_deviceToken == token) {
        appLog('ℹ️  FCM token unchanged: $token');
        return;
      }

      _deviceToken = token;
      await prefs.setString(_tokenKey, token);
      appLog('✅ New FCM token saved: $token');
    } catch (e) {
      appLog('❌ Error fetching FCM token: $e');
      // Don't rethrow - allow app to continue without token
    }
  }

  /// ----------------------------------------------------------
  /// TOKEN HANDLING
  /// ----------------------------------------------------------
  Future<void> _loadStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceToken = prefs.getString(_tokenKey);
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        appLog('Loaded stored FCM token: $_deviceToken');
      }
    } catch (e) {
      appLog('❌ Error loading stored token: $e');
    }
  }

  void _listenForTokenRefresh() {
    try {
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (_deviceToken == newToken) {
            appLog('Refreshed token is same as existing, ignoring');
            return;
          }
          _deviceToken = newToken;
          await prefs.setString(_tokenKey, newToken);
          appLog('✅ FCM token refreshed & saved: $newToken');
          await _subscribeToDefaultTopic();
        } catch (e) {
          appLog('❌ Error handling token refresh: $e');
        }
      }, onError: (error) {
        appLog('❌ Token refresh listener error: $error');
      });
    } catch (e) {
      appLog('❌ Error setting up token refresh listener: $e');
    }
  }

  /// ----------------------------------------------------------
  /// TOPIC MANAGEMENT
  /// ----------------------------------------------------------
  Future<void> _subscribeToDefaultTopic() async {
    try {
      await _messaging.subscribeToTopic(ApiEndpoint.pushTopic);
      appLog('✅ Subscribed to topic: ${ApiEndpoint.pushTopic}');
    } catch (e) {
      appLog('❌ Topic subscription error: $e');
    }
  }

  Future<void> unsubscribeFromDefaultTopic() async {
    try {
      await _messaging.unsubscribeFromTopic(ApiEndpoint.pushTopic);
      appLog('✅ Unsubscribed from topic: ${ApiEndpoint.pushTopic}');
    } catch (e) {
      appLog('❌ Topic unsubscribe error: $e');
    }
  }

  /// ----------------------------------------------------------
  /// PUBLIC ACCESS
  /// ----------------------------------------------------------
  Future<String?> getDeviceToken() async {
    try {
      // Return cached token if available
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        appLog('Returning cached FCM token: $_deviceToken');
        return _deviceToken;
      }

      // Try loading from storage
      await _loadStoredToken();
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        appLog('Returning stored FCM token: $_deviceToken');
        return _deviceToken;
      }

      // Try fetching fresh token
      appLog('No cached token found → attempting to fetch from FCM');

      if (Platform.isIOS) {
        // On iOS, wait a bit for APNS token
        await Future.delayed(const Duration(seconds: 1));
      }

      final freshToken = await _messaging.getToken().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          appLog('⚠️ FCM token fetch timeout - continuing without token');
          return null;
        },
      );

      if (freshToken == null || freshToken.isEmpty) {
        appLog('⚠️ FCM returned null/empty token - app will continue without push notifications');
        return null;
      }

      // Save the fresh token
      _deviceToken = freshToken;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, freshToken);
      appLog('✅ Fetched & saved new FCM token: $freshToken');

      // Subscribe to topic in background (don't await)
      _subscribeToDefaultTopic();

      return _deviceToken;
    } catch (e) {
      appLog('❌ Error getting device token: $e');
      appLog('⚠️ App will continue without FCM token');
      return null;
    }
  }

  /// ----------------------------------------------------------
  /// PERMISSION CHECK ON APP OPEN
  /// ----------------------------------------------------------
  Future<void> checkPermissionOnAppOpen() async {
    try {
      await checkAndRequestPermissions();
    } catch (e) {
      appLog('Error checking permission on app open: $e');
    }
  }
}
