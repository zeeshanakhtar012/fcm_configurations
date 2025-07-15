import 'dart:developer';
import 'dart:io' show Platform;
import 'package:balochtransport/constants/api_endpoints.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FCMUtils {
  static final FCMUtils _instance = FCMUtils._internal();
  factory FCMUtils() => _instance;
  FCMUtils._internal();

  String? _deviceToken;
  static const platform = MethodChannel('com.test_fcm/notifications');

  Future<bool> checkAndRequestPermissions() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        log('Notification permission granted: ${settings.authorizationStatus}');
        return true;
      } else {
        log('Notification permission denied or not set: ${settings.authorizationStatus}');
        final newSettings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: true,
        );
        if (newSettings.authorizationStatus == AuthorizationStatus.authorized ||
            newSettings.authorizationStatus == AuthorizationStatus.provisional) {
          log('Notification permission granted after re-prompt: ${newSettings.authorizationStatus}');
          return true;
        } else {
          log('Notification permission still denied: ${newSettings.authorizationStatus}');
          return false;
        }
      }
    } catch (e) {
      log('Error checking or requesting notification permissions: $e');
      return false;
    }
  }

  Future<void> initializeFCM() async {
    try {
      final hasPermission = await checkAndRequestPermissions();
      if (!hasPermission) {
        log('Skipping FCM initialization due to denied permissions');
        return;
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('device_token');

      if (storedToken != null && storedToken.isNotEmpty) {
        _deviceToken = storedToken;
        log('Device token retrieved from SharedPreferences: $storedToken');
        await FirebaseMessaging.instance.subscribeToTopic('all_users');
        log('Subscribed to topic: all_users');
        return;
      }

      if (Platform.isAndroid) {
        await _saveDeviceToken();
      } else if (Platform.isIOS) {
        platform.setMethodCallHandler((call) async {
          if (call.method == 'onFCMToken') {
            final token = call.arguments as String?;
            if (token != null && token.isNotEmpty) {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              final existingToken = prefs.getString('device_token');
              if (existingToken == token) {
                log('FCM token unchanged for iOS, skipping save: $token');
                _deviceToken = token;
              } else {
                _deviceToken = token;
                await prefs.setString('device_token', token);
                log('Received and saved FCM token from iOS via platform channel: $token');
              }
              await FirebaseMessaging.instance.subscribeToTopic('${ApiEndpoint.pushTopic}');
              log('Subscribed to topic: all_users (iOS)');
            } else {
              log('Received null/invalid FCM token from iOS');
            }
          }
          return null;
        });
        log('Waiting for FCM token via platform channel on iOS');
      } else {
        log('Unsupported platform: ${Platform.operatingSystem}');
      }
      await FirebaseMessaging.instance.subscribeToTopic('${ApiEndpoint.pushTopic}');
      log('Subscribed to topic: all_users');
    } catch (e) {
      log('FCM initialization error: $e');
    }
  }

  Future<void> _saveDeviceToken() async {
    try {
      if (!Platform.isAndroid) {
        log('Skipping _saveDeviceToken for non-Android platform: ${Platform.operatingSystem}');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final existingToken = prefs.getString('device_token');

      if (existingToken != null && existingToken.isNotEmpty) {
        _deviceToken = existingToken;
        log('Token already exists: $existingToken');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _deviceToken = token;
        await prefs.setString('device_token', token);
        log('Saved FCM token for Android: $token');
      } else {
        log('FCM token is null; skipping save');
      }
    } catch (e) {
      log('Error saving device token: $e');
    }
  }

  Future<String?> getDeviceToken() async {
    if (_deviceToken == null) {
      final prefs = await SharedPreferences.getInstance();
      _deviceToken = prefs.getString('device_token');
      log('Retrieved device token from SharedPreferences: $_deviceToken');
    }
    return _deviceToken;
  }

  Future<void> checkPermissionOnAppOpen() async {
    try {
      await checkAndRequestPermissions();
    } catch (e) {
      log('Error checking permission on app open: $e');
    }
  }
}