import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'service_page.dart';

class ZonePage extends StatefulWidget {
  const ZonePage({super.key});

  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage> {
  final DatabaseReference _zonesRef = FirebaseDatabase.instance.ref('zones');

  // 新增區域
  void addZone() {
    final TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增區域'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '區域名稱', hintText: '例如：客廳、主臥室'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                _zonesRef.push().set({
                  'name': nameController.text.trim(),
                });
                Navigator.pop(context);
              }
            },
            child: const Text('新增'),
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
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

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
                      return const Center(child: Text("還沒有建立區域，按右下角新增"));
                    }

                    // ★★★ 改成 ListView，跟裝置列表一樣 ★★★
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
              label: const Text('新增區域'),
              icon: const Icon(Icons.add_location_alt),
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ★★★ 長條形的區域卡片 (包含滑動刪除功能) ★★★
  Widget _buildZoneItem(Map<String, dynamic> zone) {
    String name = zone['name'] ?? '未命名';
    String id = zone['id'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Dismissible(
        key: Key(id),
        direction: DismissDirection.endToStart,
        // 刪除確認
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
              MaterialPageRoute(builder: (_) => ServicePage(zoneId: id, zoneName: name))
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              // 稍微加一點陰影讓它浮起來
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              // 左側圖示：區域 icon
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100], 
                  shape: BoxShape.circle
                ),
                child: const Icon(Icons.meeting_room_outlined, color: Colors.black87),
              ),
              // 中間標題
              title: Text(
                name, 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
              ),
              subtitle: const Text("點擊管理裝置", style: TextStyle(fontSize: 12, color: Colors.grey)),
              // 右側箭頭
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}