import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:math';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;

  Future<void> connect() async {
    // 如果已經連線中，就不要重複執行
    if (client?.connectionStatus?.state == MqttConnectionState.connected) return;

    String clientId = 'smart_timer_app_${Random().nextInt(100000)}';
    
    client = MqttServerClient('broker.hivemq.com', clientId);
    client!.port = 1883;
    client!.useWebSocket = false; 
    client!.logging(on: false); 
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
      _subscribeToHardwareStatus();
    } else {
      print('❌ MQTT 連線失敗');
      client!.disconnect();
    }
  }

  // ★ 補上這個方法，解決 ServicePage 的報錯 ★
  void publishCommand(String topic, String message) {
    _doPublish(topic, message);
  }

  // 保留原本的 publish 方法名稱，內容同樣導向 _doPublish
  void publish(String topic, String message) {
    _doPublish(topic, message);
  }

  // 統一處理發送邏輯
  void _doPublish(String topic, String message) {
    if (client == null || client!.connectionStatus!.state != MqttConnectionState.connected) {
      print('⚠️ MQTT 尚未連線，正在嘗試自動連線...');
      connect().then((_) {
        if (client?.connectionStatus?.state == MqttConnectionState.connected) {
          _sendRaw(topic, message);
        }
      });
      return;
    }
    _sendRaw(topic, message);
  }

  void _sendRaw(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 [發送指令] 頻道: $topic | 內容: $message');
  }

  // --- 硬體回報監聽部分 (維持原樣) ---

  void _subscribeToHardwareStatus() {
    const statusTopic = 'smart_timer/status';
    client!.subscribe(statusTopic, MqttQos.atLeastOnce);
    print('👂 開始監聽硬體狀態頻道: $statusTopic');

    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      
      print('📥 [收到硬體回報] 頻道: ${c[0].topic} | 內容: $payload');

      if (c[0].topic == statusTopic) {
        _handleHardwareStatusUpdate(payload);
      }
    });
  }

  Future<void> _handleHardwareStatusUpdate(String payload) async {
    try {
      final data = jsonDecode(payload);
      final deviceId = data['device_id'];
      final zoneId = data['zone_id'];
      final isActive = data['is_active'];

      if (deviceId != null && zoneId != null && isActive != null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;

        final ref = FirebaseDatabase.instance.ref('users/$uid/zones/$zoneId/devices/$deviceId');
        await ref.update({
          'is_active': isActive,
        });
        print('🔄 已成功將硬體狀態同步至 Firebase！ (設備: $deviceId, 狀態: $isActive)');
      }
    } catch (e) {
      print('❌ 解析硬體回報失敗: $e');
    }
  }
}