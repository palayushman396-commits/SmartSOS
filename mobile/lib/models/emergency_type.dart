import 'package:flutter/material.dart';

enum EmergencyType {
  police('police', 'Police', Icons.local_police, Color(0xFF1565C0)),
  women('women', 'Women Safety', Icons.woman, Color(0xFFAD1457)),
  child('child', 'Child Safety', Icons.child_care, Color(0xFFEF6C00)),
  fire('fire', 'Fire', Icons.local_fire_department, Color(0xFFD84315)),
  ambulance('ambulance', 'Ambulance', Icons.medical_services, Color(0xFF2E7D32));

  const EmergencyType(this.id, this.label, this.icon, this.color);

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  static EmergencyType fromId(String? id) => EmergencyType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => EmergencyType.police,
      );
}