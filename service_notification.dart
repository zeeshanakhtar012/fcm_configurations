import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
import '../model/notification.dart';
import '../screens/screen_notifications.dart';
import '../utils/fcm_utils.dart';
import '../utils/log_utils.dart';
import '../utils/storage_utils.dart';

// Top-level background message handler
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  appLog("Background Message Payload: ${message.toMap()}");
  if (message.messageId != null &&
      NotificationService.processedMessageIds.contains(message.messageId)) {
    appLog("Duplicate background message ignored: ${message.messageId}");
    return;
  }

  if (message.messageId != null) {
    NotificationService.processedMessageIds.add(message.messageId!);
  }

  if (message.notification != null || message.data.isNotEmpty) {
    final notification = message.notification ??
        RemoteNotification(
          title: message.data['title'] ?? 'Data Notification',
          body: message.data['body'] ?? 'New data received',
        );
    final notificationModel = NotificationModel(
      title: notification.title ?? 'No Title',
      body: notification.body ?? 'No Body',
      timestamp: message.sentTime ?? DateTime.now(),
      data: message.data,
      messageId: message.messageId,
    );
    await NotificationService.saveNotificationToFirestore(notificationModel);
    appLog("Background notification processed successfully");
  } else {
    appLog("Received background message without notification or data");
  }
}

class NotificationService {
  static final Set<String> processedMessageIds = {};
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await FCMUtils().initializeFCM();
    _setupFirebaseMessaging();
    await _checkInitialMessage();
    appLog('NotificationService initialized');
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
      defaultPresentList: true,
      defaultPresentBanner: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'CustomSamplePush',
          actions: [
            DarwinNotificationAction.plain(
              'id_1',
              'Open',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
          options: {DarwinNotificationCategoryOption.customDismissAction},
        ),
      ],
    );

    InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      // settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        appLog("Notification tapped with payload: ${response.payload}");
        Get.to(() => ScreenNotifications());
      }, settings: settings,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'test_notification',
      'test',
      description: 'test notifications',
      importance: Importance.high,
      playSound: true,
      enableVibration: false,
      ledColor: Colors.red,
      showBadge: true,
    );

    final androidPlugin =
        _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);

    final List<AndroidNotificationChannel>? channels =
        await androidPlugin?.getNotificationChannels();
    final channelExists = channels?.any(
      (c) => c.id == 'test_notification' && c.importance == Importance.high,
    );
    if (channelExists != true) {
      appLog("Recreating notification channel due to incorrect configuration");
      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  void _setupFirebaseMessaging() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      appLog("Foreground Message Received: ${message.messageId}");
      if (message.messageId != null &&
          processedMessageIds.contains(message.messageId)) {
        appLog("Duplicate foreground message ignored: ${message.messageId}");
        return;
      }

      if (message.messageId != null) {
        processedMessageIds.add(message.messageId!);
      }

      if (message.notification != null) {
        _showNotification(message);
        final notification = NotificationModel(
          title: message.notification!.title ?? 'No Title',
          body: message.notification!.body ?? 'No Body',
          timestamp: message.sentTime ?? DateTime.now(),
          data: message.data,
          messageId: message.messageId,
          imageUrl: message.data['image'] ??
              message.data['imageUrl'] ??
              message.notification?.apple?.imageUrl ??
              message.notification?.android?.imageUrl,
        );
        saveNotificationToFirestore(notification);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      appLog(
          "Notification Opened (Background): ${message.notification?.title}");
      Get.to(() => ScreenNotifications());
    });
  }

  Future<void> _showNotification(RemoteMessage message) async {
    try {
      final int id = DateTime.now().millisecondsSinceEpoch % 1000000;
      final String? imageUrl = message.data['image'] ??
          message.data['imageUrl'] ??
          message.notification?.apple?.imageUrl ??
          message.notification?.android?.imageUrl;

      String? imagePath;
      if (imageUrl != null) {
        imagePath =
            await _downloadAndSaveImage(imageUrl, 'notification_image_$id');
      }

      AndroidNotificationDetails androidDetails;
      DarwinNotificationDetails iosDetails;

      if (Platform.isAndroid) {
        if (imagePath != null) {
          androidDetails = AndroidNotificationDetails(
            'test_notification',
            'test',
            channelDescription: 'test notifications',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigPictureStyleInformation(
              FilePathAndroidBitmap(imagePath),
              largeIcon: FilePathAndroidBitmap(imagePath),
              contentTitle: message.notification?.title ?? 'test notification',
              htmlFormatContentTitle: false,
              summaryText: null,
            ),
            playSound: true,
            enableVibration: false,
            autoCancel: true,
            showWhen: true,
            visibility: NotificationVisibility.public,
            ledColor: Colors.red,
            ledOnMs: 200,
            ledOffMs: 200,
            icon: '@mipmap/ic_launcher',
          );
        } else {
          androidDetails = _createDefaultAndroidDetails(message);
        }
      } else {
        androidDetails = _createDefaultAndroidDetails(message);
      }

      iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentList: true,
        presentBanner: true,
        threadIdentifier: 'test_notification',
        categoryIdentifier: 'CustomSamplePush',
        attachments: imagePath != null
            ? [DarwinNotificationAttachment(imagePath)]
            : null,
        interruptionLevel: InterruptionLevel.active,
      );

      final NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        id: id,
        title: message.notification?.title ?? 'test notification',
        body: message.notification?.body ?? 'No Body',
        notificationDetails: platformDetails,
        payload: message.data.toString(),
      );
    } catch (error) {
      appLog("Error displaying notification: $error");
    }
  }

  AndroidNotificationDetails _createDefaultAndroidDetails(
      RemoteMessage message) {
    return AndroidNotificationDetails(
      'test_notification',
      'test',
      channelDescription: 'test notifications',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        message.notification?.body ?? 'No Body',
        htmlFormatBigText: false,
        contentTitle: message.notification?.title ?? 'test notification',
        htmlFormatContentTitle: false,
        summaryText: null,
      ),
      playSound: true,
      enableVibration: false,
      autoCancel: true,
      showWhen: true,
      visibility: NotificationVisibility.public,
      ledColor: Colors.red,
      ledOnMs: 200,
      ledOffMs: 200,
      icon: '@mipmap/ic_launcher',
    );
  }

  Future<String?> _downloadAndSaveImage(
      String imageUrl, String fileName) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        log("Image saved to: $filePath");
        return filePath;
      } else {
        appLog("Failed to download image: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      appLog("Error downloading image: $e");
      return null;
    }
  }

  static Future<void> saveNotificationToFirestore(
      NotificationModel notification) async {
    try {
      final userId = await StorageUtils.getUserId();
      if (userId == null) {
        appLog("User ID is null. Cannot save notification.");
        return;
      }
      final userIdStr = userId.toString();
      final collectionRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc(userIdStr)
          .collection('userNotifications');

      final notificationData = notification.toMap();
      notificationData['timestamp'] =
          Timestamp.fromDate(notification.timestamp);
      await collectionRef.doc(notification.messageId).set(notificationData);
      appLog(
          "Notification saved to Firestore under user ID $userId: ${notification.toMap()}");
    } catch (e) {
      appLog("Error saving notification to Firestore: $e");
    }
  }

  Future<void> _checkInitialMessage() async {
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      appLog(
          "App opened via terminated state notification: ${initialMessage.data}");
      Get.to(() => ScreenNotifications());
    }
  }
}
