import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_type.dart';
import '../models/incident_status.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../services/voice_trigger_service.dart';

class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _sos = SosService();
  final _voice = VoiceTriggerService();

  EmergencyType _selected = EmergencyType.police;
  LocationState _locState = LocationState.denied;
  bool _voiceOn = false;
  bool _sending = false;
  bool _countdownOpen = false;

  String? _incidentId;
  Map<String, dynamic>? _incident;
  bool _pendingSync = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _incidentSub;
  Timer? _ticker;

  bool get _hasActive => _incidentId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLocation();
    _restoreActiveIncident();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.stop();
    _incidentSub?.cancel();
    _ticker?.cancel();
    _sos.stopTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocation();
      if (_voiceOn && !_hasActive) _voice.resume();
    } else if (state == AppLifecycleState.paused) {
      _voice.pause(); // never listen while the app is in the background
    }
  }

  Future<void> _refreshLocation() async {
    final s = await LocationService.check();
    if (mounted) setState(() => _locState = s);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restoreActiveIncident() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('incidents')
          .where('userId', isEqualTo: widget.user.uid)
          .where('status', whereIn: activeStatuses)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty && mounted) _attachToIncident(q.docs.first.id);
    } catch (_) {}
  }

  void _attachToIncident(String id) {
    setState(() => _incidentId = id);
    _voice.pause();
    _sos.startTracking(id);
    _incidentSub?.cancel();
    _incidentSub = FirebaseFirestore.instance
        .collection('incidents')
        .doc(id)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      setState(() {
        _incident = data;
        _pendingSync = snap.metadata.hasPendingWrites;
      });
      final status = data['status'] as String? ?? '';
      if (isTerminal(status)) _finishIncident(status);
    });
  }

  void _finishIncident(String status) {
    _incidentSub?.cancel();
    _incidentSub = null;
    _sos.stopTracking();
    setState(() {
      _incidentId = null;
      _incident = null;
      _pendingSync = false;
    });
    _snack('SOS ${statusLabel(status).toLowerCase()}. Location sharing stopped.');
    if (_voiceOn) _voice.resume();
  }

  Future<void> _startSos(String source) async {
    if (_hasActive || _sending || _countdownOpen) return;
    _countdownOpen = true;
    _voice.pause();

    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CountdownDialog(type: _selected, fromVoice: source == 'voice'),
    );
    _countdownOpen = false;

    if (go != true) {
      if (_voiceOn) _voice.resume();
      return;
    }

    setState(() => _sending = true);
    try {
      final state = await LocationService.check(request: true);
      if (mounted) setState(() => _locState = state);

      final res = await _sos.createIncident(type: _selected, source: source);
      if (!mounted) return;
      _attachToIncident(res.id);

      if (res.queued) {
        _snack('No connection. Your SOS is saved and will be sent as soon as you are online.');
      } else if (state != LocationState.ready) {
        _snack('SOS sent, but your location is unavailable.');
      } else {
        _snack('SOS sent to the SmartSOS control room.');
      }
    } catch (e) {
      _snack('Could not send SOS. Please try again.');
      if (_voiceOn) _voice.resume();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancelSos() async {
    final id = _incidentId;
    if (id == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this SOS?'),
        content: const Text('Responders will be told you no longer need help.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep SOS active')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel SOS')),
        ],
      ),
    );
    if (yes == true) await _sos.cancelIncident(id);
  }

  Future<void> _toggleVoice(bool on) async {
    if (!on) {
      _voice.stop();
      setState(() => _voiceOn = false);
      return;
    }
    final agree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on voice trigger?'),
        content: const Text(
          'While this is on and the app is open, the microphone listens for '
          'trigger words such as "help me" or "bachao". Speech is recognised '
          'by your phone\'s speech service (usually Google). SmartSOS does not '
          'record or send your voice until an SOS is started. The app shows '
          'a banner while it is listening.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn on')),
        ],
      ),
    );
    if (agree != true) return;

    final ok = await _voice.start(
      onTrigger: () => _startSos('voice'),
      onError: (m) {
        _snack(m);
        if (mounted) setState(() => _voiceOn = false);
      },
    );
    if (!ok) {
      _snack('Voice trigger unavailable. Allow microphone access and check that Google speech services are installed.');
      return;
    }
    setState(() => _voiceOn = true);
    if (_hasActive) _voice.pause();
  }

  void _logout() {
    if (_hasActive) {
      _snack('Cancel or finish your active SOS before logging out.');
      return;
    }
    AuthService().logout();
  }

  String _ago(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartSOS'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Hi, ${widget.user.displayName ?? 'there'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(_hasActive
                ? 'Your SOS is active.'
                : 'Choose the type of emergency, then press SOS.'),
            const SizedBox(height: 12),
            _locationRow(),
            const SizedBox(height: 16),
            if (!_hasActive) ...[
              _typeGrid(),
              const SizedBox(height: 24),
            ],
            Center(child: _sosButton()),
            const SizedBox(height: 24),
            if (_hasActive) _activeCard(),
            _voiceCard(),
          ],
        ),
      ),
    );
  }

  Widget _locationRow() {
    final ready = _locState == LocationState.ready;
    return Row(
      children: [
        Icon(ready ? Icons.location_on : Icons.location_off,
            color: ready ? Colors.green : Colors.orange),
        const SizedBox(width: 8),
        Expanded(child: Text(LocationService.describe(_locState))),
        if (!ready)
          TextButton(
            onPressed: () async {
              if (_locState == LocationState.serviceOff) {
                await Geolocator.openLocationSettings();
              } else if (_locState == LocationState.deniedForever) {
                await Geolocator.openAppSettings();
              } else {
                await LocationService.check(request: true);
              }
              _refreshLocation();
            },
            child: const Text('Fix'),
          ),
      ],
    );
  }

  Widget _typeGrid() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: EmergencyType.values.map((t) {
        final selected = t == _selected;
        return Semantics(
          button: true,
          selected: selected,
          label: '${t.label} emergency',
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _selected = t),
            child: Container(
              decoration: BoxDecoration(
                color: selected ? t.color : t.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.color, width: selected ? 3 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.icon, size: 34, color: selected ? Colors.white : t.color),
                  const SizedBox(height: 6),
                  Text(
                    t.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sosButton() {
    final active = _hasActive;
    final color = active ? Colors.orange.shade800 : Colors.red.shade700;
    return Semantics(
      button: true,
      label: active ? 'SOS is active' : 'Send SOS for ${_selected.label}',
      child: GestureDetector(
        onTap: (_sending || active) ? null : () => _startSos('button'),
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: _sending
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        active ? 'SOS\nACTIVE' : 'SOS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      if (!active)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _selected.label,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _activeCard() {
    final status = (_incident?['status'] as String?) ?? 'initiated';
    final type = EmergencyType.fromId(_incident?['emergencyType'] as String?);
    final loc = _incident?['lastLocation'] as Map<String, dynamic>?;
    final ts = (loc?['timestamp'] as Timestamp?)?.toDate();
    final age = ts == null ? null : DateTime.now().difference(ts);
    final stale = age != null && age.inSeconds > 60;
    final accuracy = (loc?['accuracy'] as num?)?.round();

    String locText;
    if (loc == null) {
      locText = 'No location available yet';
    } else {
      locText = 'Last location update: ${age == null ? 'just now' : _ago(age)}'
          '${accuracy == null ? '' : ' (±$accuracy m)'}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(type.icon, color: type.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${type.label} · ${statusLabel(status)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Icon(_pendingSync ? Icons.cloud_off : Icons.cloud_done,
                  size: 18, color: _pendingSync ? Colors.orange : Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_pendingSync
                    ? 'Waiting for connection to send'
                    : 'Synced with control room'),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(stale ? Icons.warning_amber : Icons.my_location,
                  size: 18, color: stale ? Colors.orange : Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(stale ? '$locText. Location may be outdated.' : locText),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Location is shared while this app stays open. '
              'Live audio/video is not available yet.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cancelSos,
                icon: const Icon(Icons.close),
                label: const Text('Cancel SOS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceCard() {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(_voiceOn ? Icons.mic : Icons.mic_off,
                color: _voiceOn ? Colors.red : null),
            title: const Text('Voice trigger'),
            subtitle: Text(_voiceOn
                ? 'Listening while the app is open for: '
                    '${VoiceTriggerService.keywords.take(4).join(', ')}'
                : 'Say a trigger word to start SOS hands-free. Works only while the app is open.'),
            value: _voiceOn,
            onChanged: _toggleVoice,
          ),
        ],
      ),
    );
  }
}

class _CountdownDialog extends StatefulWidget {
  final EmergencyType type;
  final bool fromVoice;
  const _CountdownDialog({required this.type, required this.fromVoice});

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int _left = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Sending ${widget.type.label} SOS'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_left',
              style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            widget.fromVoice
                ? 'Trigger word heard. Tap Cancel if this was a mistake.'
                : 'Tap Cancel if this was a mistake.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('SEND NOW'),
        ),
      ],
    );
  }
}