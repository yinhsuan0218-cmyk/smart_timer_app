import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart'; 
import 'pages/zone_page.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'services/mqtt_service.dart';
import 'dart:async'; 

// 宣告一個全域變數，用來儲存訂閱，防止重複登入時重複監聽
StreamSubscription? _globalTempSubscription;

// 💡 用來記錄全域設備的「上一次開關狀態」，避免重複洗通知
// 結構為: { "zoneId_deviceId": true/false }
final Map<String, bool> _lastDeviceStates = {};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  FirebaseDatabase.instance.databaseURL = "https://smart-timer-app-7da95-default-rtdb.firebaseio.com/";
  
  // 自動化核心：監聽 Auth 狀態
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      print("[全域監聽] 使用者已登入, 開始啟動溫度與設備狀態追蹤. UID: ${user.uid}");
      startGlobalTemperatureListener(user.uid);
    } else {
      print("[全域監聽] 使用者未登入或已登出, 關閉監聽並清空快照.");
      _globalTempSubscription?.cancel();
      _globalTempSubscription = null;
      _lastDeviceStates.clear(); // 清空狀態快照
    }
  });

  runApp(const SmartTimerApp());
}

class SmartTimerApp extends StatelessWidget {
  const SmartTimerApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 全域追蹤與防護監聽函數
void startGlobalTemperatureListener(String uid) {
  _globalTempSubscription?.cancel();

  final FirebaseDatabase db = FirebaseDatabase.instance;
  final MqttService mqttService = MqttService();
  mqttService.connect(); 

  _globalTempSubscription = db.ref('users/$uid/zones').onValue.listen((event) async {
    if (event.snapshot.value == null) return;
    
    final zonesData = event.snapshot.value as Map<dynamic, dynamic>;
    
    for (var entry in zonesData.entries) {
      final String zoneId = entry.key.toString();
      final zone = Map<String, dynamic>.from(entry.value as Map);
      final String zoneName = zone['name'] ?? '未命名區域';
      
      // 1. 🌡️ 溫度防護與自動斷電核心邏輯
      double currentTemp = double.tryParse(zone['temperature']?.toString() ?? '0.0') ?? 0.0;

      if (currentTemp >= 80.0) {
        bool isAlreadyShutdown = zone['is_danger_triggered'] ?? false;
        if (!isAlreadyShutdown) {
          print("🚨 警報！區域【$zoneName】過熱 (${currentTemp}°C)，啟動緊急斷電！");
          await db.ref('users/$uid/zones/$zoneId').update({'is_danger_triggered': true});
          
          final devicesRef = db.ref('users/$uid/zones/$zoneId/devices');
          final devicesSnapshot = await devicesRef.get();
          
          if (devicesSnapshot.exists && devicesSnapshot.value != null) {
            final devicesData = devicesSnapshot.value as Map<dynamic, dynamic>;
            devicesData.forEach((deviceId, _) {
              devicesRef.child(deviceId).update({'is_active': false});
              mqttService.publishCommand('users/$uid/zones/$zoneId/commands', "$deviceId:OFF");
            });
          }

          await db.ref('users/$uid/notifications').push().set({
            'zoneId': zoneId,
            'title': '🚨 危險！溫度過高自動斷電',
            'content': '區域【$zoneName】環境溫度已達 ${currentTemp.toStringAsFixed(1)}°C！系統已強制切斷所有裝置電源！',
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'danger',
            'status': 'unread', 
          });
        }
      } else {
        if (zone['is_danger_triggered'] == true) {
          await db.ref('users/$uid/zones/$zoneId').update({'is_danger_triggered': false});
          print("✅ 區域【$zoneName】溫度已冷卻降回安全線 (${currentTemp}°C)。");
        }
      }

      // 2. 🔌 設備狀態變更追蹤監聽邏輯 (手動/硬體/排程變更皆適用)
      if (zone['devices'] != null) {
        final devicesMap = Map<dynamic, dynamic>.from(zone['devices'] as Map);
        
        devicesMap.forEach((deviceId, deviceValue) async {
          final device = Map<String, dynamic>.from(deviceValue as Map);
          bool currentActive = device['is_active'] ?? false;
          
          // 使用 區域ID + 設備ID 作為唯快照唯一 Key
          String stateKey = "${zoneId}_$deviceId";
          
          // 檢查快照內是否存有此設備的上一次狀態
          if (_lastDeviceStates.containsKey(stateKey)) {
            bool? lastActive = _lastDeviceStates[stateKey];
            
            // 💡 關鍵比對：如果目前的狀態與上一次記錄不同，代表開關被切換了！
            if (lastActive != currentActive) {
              String statusText = currentActive ? "開啟" : "關閉";
              String emoji = currentActive ? "🟢" : "🔴";
              
              print("💡 [全域通知] 設備狀態變更偵測：$zoneName -> $deviceId 變更為 $statusText");
              
              // 推送開關變更通知紀錄到 Firebase 資料庫
              await db.ref('users/$uid/notifications').push().set({
                'zoneId': zoneId,
                'deviceId': deviceId,
                'title': '$emoji 設備狀態變更',
                'content': '區域【$zoneName】中的裝置【$deviceId】已被 $statusText。',
                'timestamp': DateTime.now().toIso8601String(),
                'type': 'info',
                'status': 'unread',
              });
            }
          }
          
          // 更新或初始化該設備的狀態快照
          _lastDeviceStates[stateKey] = currentActive;
        });
      }
    }
  });
}
