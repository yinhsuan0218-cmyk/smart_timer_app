import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'zone_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signIn(BuildContext context) async {
    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithPopup(GoogleAuthProvider());

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ZonePage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登入失敗: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('使用 Google 登入 (Web)'),
          onPressed: () => signIn(context),
        ),
      ),
    );
  }
}
