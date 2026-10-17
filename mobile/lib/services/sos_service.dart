import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_type.dart';

class SosService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<Position>? _posSub;
  DateTime? _lastWrite;

  Map<String, dynamic> _locMap(Position p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracy': p.accuracy,
        'timestamp': Timestamp.now(),
      };

  /// Creates the incident. If there is no internet, the write is kept by
  /// Firestore and sent automatically when the phone is online ("queued").
  Future<({String id, bool queued})> createIncident({
    required EmergencyType type,
    required String source, // 'button' or 'voice'
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You are not signed in.');

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    final ref = _db.collection('incidents').doc();
    final data = <String, dynamic>{
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Unknown',
      'emergencyType': type.id,
      'status': 'initiated',
      'priority': 'high',
      'triggerSource': source,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLocation': pos == null ? null : _locMap(pos),
      'liveKitRoomName': 'sos_${ref.id}',
      'assignedResponderId': null,
      'assignedDepartmentId': null,
    };

    var queued = false;
    try {
      await ref.set(data).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      queued = true;
    }

    startTracking(ref.id);
    return (id: ref.id, queued: queued);
  }

  /// Sends location updates at most once every 10 seconds, only while the
  /// app is open and an incident is active.
  void startTracking(String incidentId) {
    stopTracking();
    _lastWrite = null;
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((p) {
      final now = DateTime.now();
      if (_lastWrite != null && now.difference(_lastWrite!).inSeconds < 10) {
        return;
      }
      _lastWrite = now;
      _db.collection('incidents').doc(incidentId).update({
        'lastLocation': _locMap(p),
        'updatedAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }, onError: (_) {});
  }

  void stopTracking() {
    _posSub?.cancel();
    _posSub = null;
  }

  Future<void> cancelIncident(String incidentId) async {
    try {
      await _db.collection('incidents').doc(incidentId).update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Saved locally; will sync when online.
    }
  }
}