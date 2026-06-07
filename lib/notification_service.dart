import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart';    
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'raha_channel_id',
      'تنبيهات تطبيق راحة',
      description: 'إشعارات تحديث حالة الطلبات والعروض',
      importance: Importance.max,
      showBadge: true,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("تم الضغط على الإشعار: ${response.payload}");
      },
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // تشغيل مستمع تحديث التوكن عند تهيئة الخدمة
    listenToTokenRefresh();
  }

  // دالة لمراقبة تحديث التوكن وحفظه فوراً في Firestore
  static void listenToTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'fcmToken': newToken,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          });
          debugPrint("FCM Token Refreshed and updated in Firestore ✅");
        } catch (e) {
          debugPrint("Error updating refreshed token: $e");
        }
      }
    });
  }

  static Future<String?> getDeviceToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint("Error getting device token: $e");
      return null;
    }
  }

  static Future<void> showNotification(String title, String body, {String targetSection = 'all'}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'raha_channel_id',
      'تنبيهات تطبيق راحة',
      channelDescription: 'إشعارات تحديث حالة الطلبات والعروض',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      channelShowBadge: true,
      number: 1,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformDetails,
      payload: 'notification_record',
    );

    await _saveNotificationRecord(title, body, targetSection);
  }

  static Future<void> _saveNotificationRecord(String title, String body, String targetSection) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .add({
          'title': title,
          'body': body,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'targetSection': targetSection,
        });
      }
    } catch (e) {
      debugPrint("خطأ في حفظ سجل الإشعار: $e");
    }
  }
}
