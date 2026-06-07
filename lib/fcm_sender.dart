import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

class FcmSender {
  // المسار الجديد المختصر
  static const String _assetPath = 'assets/service-account.json';

  static Future<String> getAccessToken() async {
    final serviceAccountJson = await rootBundle.loadString(_assetPath);
    final accountCredentials = auth.ServiceAccountCredentials.fromJson(serviceAccountJson);
    
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client = await auth.clientViaServiceAccount(accountCredentials, scopes);
    return client.credentials.accessToken.data;
  }

  static Future<void> sendNotification(String deviceToken, String title, String body) async {
    try {
      // قراءة محتوى الملف لاستخراج معرف المشروع (Project ID)
      final String serviceAccountContent = await rootBundle.loadString(_assetPath);
      final Map<String, dynamic> accountData = jsonDecode(serviceAccountContent);
      final String projectId = accountData['project_id'];

      final String accessToken = await getAccessToken();

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'message': {
            'token': deviceToken,
            'notification': {
              'title': title,
              'body': body,
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'high_importance_channel', // تأكد من مطابقة اسم القناة في تطبيقك
                'icon': 'launch_background',
                'sound': 'default',
              },
            },
            'data': {
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              'status': 'done',
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        print("تم إرسال الإشعار بنجاح ✅");
      } else {
        print("فشل الإرسال. الكود: ${response.statusCode}, السبب: ${response.body}");
      }
    } catch (e) {
      print("خطأ فني أثناء الإرسال: $e");
    }
  }
}
