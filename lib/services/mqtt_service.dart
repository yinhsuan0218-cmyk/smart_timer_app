import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:math';

class MqttService {
  // 單例模式：確保整個 App 共用同一個 MQTT 連線
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;

  // 初始化並連線到 Broker
  Future<void> connect() async {
    String clientId = 'smart_timer_app_${Random().nextInt(100000)}';
    
    // ★ 1. 回歸最純粹的 HiveMQ TCP 連線 (不需要 ws://)
    client = MqttServerClient('broker.hivemq.com', clientId);
    client!.port = 1883;
    client!.useWebSocket = false; // 關閉 WebSocket
    client!.logging(on: true);    // ★ 打開 Log，看清楚連線過程
    client!.keepAlivePeriod = 20;

    // ★ 2. 移除有毒的遺言設定，給它一個最乾淨的連線封包
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean(); // 每次連線都當作全新的開始
        
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
    } else {
      print('❌ MQTT 連線失敗，狀態: ${client!.connectionStatus?.state}');
      client!.disconnect();
    }
  }

  // 發布訊息的功能 (也就是你 schedule_page 呼叫的那個)
  void publish(String topic, String message) {
    // 如果還沒連線，就先自動連線再發送
    if (client == null || client!.connectionStatus!.state != MqttConnectionState.connected) {
      print('⚠️ MQTT 尚未連線，正在嘗試重新連線並發送...');
      connect().then((_) {
        if (client!.connectionStatus!.state == MqttConnectionState.connected) {
          _publishMessage(topic, message);
        }
      });
      return;
    }
    
    // 已經連線就直接發送
    _publishMessage(topic, message);
  }

  // 實際執行發送的內部方法
  void _publishMessage(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 已成功發布 MQTT 訊息！');
    print('📍 頻道 (Topic): $topic');
    print('📜 內容 (Message): $message');
  }
}