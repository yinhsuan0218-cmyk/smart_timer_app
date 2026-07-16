import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// 必須是全域頂層函式，用於處理背景推播
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("收到背景通知: ${message.messageId}");
}

class PushNotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 初始化通知設定
  static Future<void> initialize() async {
    // 1. 請求實體手機的通知權限
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('使用者已授權通知');
    }

    // 2. 註冊背景推播監聽
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. 設定 Android 的高優先度通知管道
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // 管道 ID
      '高重要性通知', // 顯示給使用者的管道名稱
      description: '此管道用於顯示緊急警報與重要系統通知。',
      importance: Importance.max, // 最高的 Importance 才能在螢幕上方彈出橫幅
      playSound: true,
    );

    // 4. 初始化本機通知套件
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); 
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    // ✅ 修正：v20+ 版本的 initialize 方法必須使用「具名參數」
    await _localNotificationsPlugin.initialize(
      settings: initializationSettings, // 使用 settings: 具名參數
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // 處理使用者點擊上方彈出橫幅後的行為
        print("使用者點擊了通知: ${response.payload}");
      },
    );

    // 創建 Android 管道
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 5. 監聽前台推播（當使用者正在使用 App 時，強制在上方彈出橫幅）
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null) {
        // ✅ 修正：v20+ 版本的 show 方法，所有參數皆改為「具名參數」
        _localNotificationsPlugin.show(
          id: notification.hashCode,                      // 具名參數 id
          title: notification.title,                      // 具名參數 title
          body: notification.body,                        // 具名參數 body
          notificationDetails: NotificationDetails(       // 具名參數 notificationDetails (注意：舊版叫 details)
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high, // 高優先度
              playSound: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: message.data.toString(),               // 具名參數 payload
        );
      }
    });

    // 取得這台裝置的 FCM Token
    String? token = await _fcm.getToken();
    print("FCM Device Token: $token");
  }
}
