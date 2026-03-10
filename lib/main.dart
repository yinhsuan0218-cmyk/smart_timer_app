import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart'; // <- 條件 import 會自動選 Web 或 Mobile
import 'pages/zone_page.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 如果你的資料庫不在美國，通常需要這樣寫
FirebaseDatabase.instance.databaseURL = "https://smart-timer-app-7da95-default-rtdb.firebaseio.com/";
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
