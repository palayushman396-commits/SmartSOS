import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSOS'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome, ${user.displayName ?? user.email}',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text('UID: ${user.uid}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 24),
            const Text('SOS button comes in Phase 4'),
          ],
        ),
      ),
    );
  }
}