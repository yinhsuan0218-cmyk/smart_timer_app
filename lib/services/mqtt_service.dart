import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  final client =
      MqttServerClient('test.mosquitto.org', 'flutter_client');

  Future<void> connect() async {
    client.port = 1883;
    client.keepAlivePeriod = 20;

    client.onConnected = () => print('MQTT Connected');

    await client.connect();
  }

  void publish(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void subscribe(String topic, Function(String) onMessage) {
    client.subscribe(topic, MqttQos.atLeastOnce);
    client.updates!.listen((events) {
      final msg = events.first.payload as MqttPublishMessage;
      onMessage(MqttPublishPayload.bytesToStringAsString(
          msg.payload.message));
    });
  }
}
