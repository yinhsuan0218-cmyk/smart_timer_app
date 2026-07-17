import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'service_page.dart';

class ZonePage extends StatefulWidget {
  const ZonePage({super.key});

  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage> {
  late DatabaseReference _zonesRef;
  String? uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser?.uid;
    
    if (uid != null) {
      _zonesRef = FirebaseDatabase.instance.ref('users/$uid/zones');
    } else {
      _zonesRef = FirebaseDatabase.instance.ref('zones');
    }
  }

  // 新增區域
  void addZone() {
    final TextEditingController nameController = TextEditingController();
    
    void submit() {
      if (nameController.text.isNotEmpty) {
        // 💡 這裡在建立節點時，同時塞入預設的溫度數值
        _zonesRef.push().set({
          'name': nameController.text.trim(),
          'temperature': 0.0, // ESP32 或感測器尚未回傳前的初始溫度
          'power': 'safe', // 預設耗電狀態
          'energy': 0.0, // ⚡ 預設電能數據
        });
        Navigator.pop(context);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('新增區域', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          textInputAction: TextInputAction.done, 
          onSubmitted: (_) => submit(),         
          decoration: const InputDecoration(labelText: '區域名稱', hintText: '例如：客廳、主臥室'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: submit, 
            child: const Text('新增', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 60, 24, 20),
                child: Text(
                  'My Zones',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                ),
              ),
              Expanded(
                child: StreamBuilder(
                  stream: _zonesRef.onValue,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Center(child: Text("連線錯誤"));
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.black));

                    List<Map<String, dynamic>> zoneList = [];
                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                      final rawData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                      rawData.forEach((key, value) {
                        final zone = Map<String, dynamic>.from(value);
                        zone['id'] = key;
                        zoneList.add(zone);
                      });
                    }

                    if (zoneList.isEmpty) {
                      return const Center(child: Text("還沒有建立區域，按右下角新增", style: TextStyle(color: Colors.grey)));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: zoneList.length,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final zone = zoneList[index];
                        return _buildZoneItem(zone);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 30, right: 24,
            child: FloatingActionButton.extended(
              onPressed: addZone,
              label: const Text('新增區域', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add_location_alt, color: Colors.black),
              backgroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  // 長條形的區域卡片
  Widget _buildZoneItem(Map<String, dynamic> zone) {
    String name = zone['name'] ?? '未命名';
    String id = zone['id'];
    
    // 💡 修正後的安全寫法：防止舊資料缺少 temperature 欄位導致崩潰
    double temp = double.tryParse(zone['temperature']?.toString() ?? '0.0') ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Dismissible(
        key: Key(id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          return await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('刪除 $name?'),
              content: const Text('這會一併刪除該區域內的所有裝置！\n確定要繼續嗎？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("刪除全部", style: TextStyle(color: Colors.red))),
              ],
            ),
          );
        },
        onDismissed: (_) {
          _zonesRef.child(id).remove();
        },
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red[100], 
            borderRadius: BorderRadius.circular(20)
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.red),
        ),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => ServicePage(
                  zoneId: id, 
                  zoneName: name,
                  mqttTopic: 'users/$uid/zones/$id/commands', 
                )
              )
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100], 
                  shape: BoxShape.circle
                ),
                child: const Icon(Icons.meeting_room_outlined, color: Colors.black87),
              ),
              title: Text(
                name, 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
              ),
              subtitle: Text("目前溫度: $temp°C", style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
