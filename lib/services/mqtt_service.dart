import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:math';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart'; // ★ 新增：為了更新 Firebase
import 'package:firebase_database/firebase_database.dart'; // ★ 新增：為了更新 Firebase

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;

  Future<void> connect() async {
    String clientId = 'smart_timer_app_${Random().nextInt(100000)}';
    
    client = MqttServerClient('broker.hivemq.com', clientId);
    client!.port = 1883;
    client!.useWebSocket = false; 
    client!.logging(on: false); // 關閉底層 log 保持終端機乾淨
    client!.keepAlivePeriod = 20;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean(); 
        
    client!.connectionMessage = connMess;

    try {
      print('🌐 準備連線到 MQTT Broker...');
      await client!.connect();
    } catch (e) {
      print('❌ MQTT 連線發生例外錯誤: $e');
      client!.disconnect();
    }

    if (client!.connectionStatus != null && 
        client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('✅ MQTT 連線成功！Broker: broker.hivemq.com');
      
      // ★★★ 新增：裝上耳朵！訂閱硬體狀態頻道 ★★★
      _subscribeToHardwareStatus();

    } else {
      print('❌ MQTT 連線失敗，狀態: ${client!.connectionStatus?.state}');
      client!.disconnect();
    }
  }

  // ★ 監聽硬體回報的專屬函式
  void _subscribeToHardwareStatus() {
    const statusTopic = 'smart_timer/status';
    client!.subscribe(statusTopic, MqttQos.atLeastOnce);
    print('👂 開始監聽硬體狀態頻道: $statusTopic');

    // 只要有訊息進來，就會觸發這個 listen
    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      
      print('📥 [收到硬體回報] 頻道: ${c[0].topic} | 內容: $payload');

      if (c[0].topic == statusTopic) {
        _handleHardwareStatusUpdate(payload);
      }
    });
  }

  // ★ 處理硬體傳來的 JSON，並同步到 Firebase
  Future<void> _handleHardwareStatusUpdate(String payload) async {
    try {
      final data = jsonDecode(payload);
      final deviceId = data['device_id'];
      final zoneId = data['zone_id'];
      final isActive = data['is_active'];

      if (deviceId != null && zoneId != null && isActive != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;

        // 直接更新 Firebase，App 畫面就會因為 StreamBuilder 自動更新！
        final ref = FirebaseDatabase.instance.ref('users/$uid/zones/$zoneId/devices/$deviceId');
        await ref.update({
          'is_active': isActive,
        });
        print('🔄 已成功將硬體狀態同步至 Firebase！ (設備: $deviceId, 狀態: $isActive)');
      } else {
        print('⚠️ 硬體回報的 JSON 格式缺少必要欄位');
      }
    } catch (e) {
      print('❌ 解析硬體回報失敗: $e');
    }
  }

  void publish(String topic, String message) {
    if (client == null || client!.connectionStatus!.state != MqttConnectionState.connected) {
      print('⚠️ MQTT 尚未連線，嘗試重新連線...');
      connect().then((_) {
        if (client!.connectionStatus!.state == MqttConnectionState.connected) {
          _publishMessage(topic, message);
        }
      });
      return;
    }
    _publishMessage(topic, message);
  }

  void _publishMessage(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 [發送指令] 頻道: $topic | 內容: $message');
  }
}