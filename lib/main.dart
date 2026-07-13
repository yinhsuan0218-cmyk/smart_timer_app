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

// 用來記錄全域設備的「上一次開關狀態」，避免重複洗通知
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
      _lastDeviceStates.clear(); 
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
      
      // -------------------------------------------------------------
      // 1. 🌡️ 溫度防護與自動斷電核心邏輯
      // -------------------------------------------------------------
      double currentTemp = double.tryParse(zone['temperature']?.toString() ?? '0.0') ?? 0.0;

      // 取得目前的狀態旗標（預設為 false）
      bool isDangerTriggered = zone['is_danger_triggered'] ?? false;
      bool isWarmTriggered = zone['is_warm_triggered'] ?? false;

      // --- 狀況 A：高於或等於 80.0°C (Danger 嚴重警報 + 斷電) ---
      if (currentTemp >= 80.0) {
        if (!isDangerTriggered) {
          print("🚨 警報！區域【$zoneName】過熱 (${currentTemp}°C)，啟動緊急斷電！");
          
          // 標記 Danger 觸發
          await db.ref('users/$uid/zones/$zoneId').update({
            'is_danger_triggered': true,
            'is_warm_triggered': false, // 升級為 Danger 時，清除 Warm 標記
          });
          
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
      } 
      // --- 狀況 B：介於 60.0°C 至 80.0°C 之間 (Warm 警告，僅提醒不中斷電源) ---
      else if (currentTemp >= 60.0 && currentTemp < 80.0) {
        if (!isWarmTriggered) {
          print("⚠️ 警告！區域【$zoneName】溫度偏高 (${currentTemp}°C)，發送黃色預警。");
          
          // 標記 Warm 觸發，並確保 Danger 旗標為 false
          await db.ref('users/$uid/zones/$zoneId').update({
            'is_warm_triggered': true,
            'is_danger_triggered': false,
          });

          await db.ref('users/$uid/notifications').push().set({
            'zoneId': zoneId,
            'title': '⚠️ 警告！溫度異常偏高',
            'content': '區域【$zoneName】環境溫度已達 ${currentTemp.toStringAsFixed(1)}°C。請留意高負載電器使用狀況。',
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'warn', 
            'status': 'unread', 
          });
        }
      } 
      // --- 狀況 C：降至 60.0°C 以下 (安全範圍，發布復原通知) ---
      else {
        if (isDangerTriggered || isWarmTriggered) {
          print("✅ 區域【$zoneName】溫度已冷卻降回安全線 (${currentTemp}°C)。");
          
          // 解除所有溫度警報狀態旗標
          await db.ref('users/$uid/zones/$zoneId').update({
            'is_danger_triggered': false,
            'is_warm_triggered': false,
          });
          
          await db.ref('users/$uid/notifications').push().set({
            'zoneId': zoneId,
            'title': '✅ 安全！環境溫度已恢復正常',
            'content': '區域【$zoneName】環境溫度已冷卻降至 ${currentTemp.toStringAsFixed(1)}°C。目前已解除危險管制，設備可以重新開啟使用。',
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'success', 
            'status': 'unread', 
          });
        }
      }

      // -------------------------------------------------------------
      // 2. ⚡ 耗電狀態防護與異常通知邏輯
      // -------------------------------------------------------------
      String powerState = zone['power'] ?? 'safe';
      bool isWasteTriggered = zone['is_waste_triggered'] ?? false;

      if (powerState == 'waste') {
        if (!isWasteTriggered) {
          await db.ref('users/$uid/zones/$zoneId').update({'is_waste_triggered': true});

          await db.ref('users/$uid/notifications').push().set({
            'zoneId': zoneId,
            'title': '🔌 偵測到異常耗電提醒',
            'content': '區域【$zoneName】目前有不合適的耗電情形。建議前往確認或關閉閒置裝置。',
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'warn', // 💡 改為 'warn' 讓前端顯示黃色/橘色
            'status': 'unread', 
            'zone_name': zoneName,
          });
        }
      } else {
        if (isWasteTriggered) {
          await db.ref('users/$uid/zones/$zoneId').update({'is_waste_triggered': false});

          await db.ref('users/$uid/notifications').push().set({
            'zoneId': zoneId,
            'title': '🌱 耗電狀態已恢復正常',
            'content': '區域【$zoneName】的用電情況已回到一般正常範圍。',
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'success', // 💡 改為 'success' 讓前端顯示安全綠
            'status': 'unread', 
            'zone_name': zoneName,
          });
        }
      }
    }
  });
}
