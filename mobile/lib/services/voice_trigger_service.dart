import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceTriggerService {
  static const List<String> keywords = [
    'help me',
    'save me',
    'bachao',
    'बचाओ',
    'emergency',
    'sos',
  ];

  final SpeechToText _speech = SpeechToText();
  bool _enabled = false;
  bool _paused = false;
  bool _starting = false;
  void Function()? _onTrigger;
  void Function(String)? _onError;

  bool get isEnabled => _enabled;

  Future<bool> start({
    required void Function() onTrigger,
    void Function(String)? onError,
  }) async {
    _onTrigger = onTrigger;
    _onError = onError;
    final ok = await _speech.initialize(
      onStatus: _onStatus,
      onError: (e) => _handleError(e.errorMsg),
    );
    if (!ok) return false;
    _enabled = true;
    _paused = false;
    _listen();
    return true;
  }

  Future<void> _listen() async {
    if (!_enabled || _paused || _starting || _speech.isListening) return;
    _starting = true;
    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords.toLowerCase();
          if (keywords.any(text.contains)) {
            _paused = true;
            _speech.cancel();
            _onTrigger?.call();
          }
        },
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 8),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (_) {
      // Retried by the status/error handlers.
    } finally {
      _starting = false;
    }
  }

  void _onStatus(String status) {
    if (_enabled && !_paused && (status == 'done' || status == 'notListening')) {
      Future.delayed(const Duration(milliseconds: 700), _listen);
    }
  }

  void _handleError(String message) {
    if (message.contains('permission')) {
      stop();
      _onError?.call('Microphone permission was denied.');
      return;
    }
    if (_enabled && !_paused) {
      Future.delayed(const Duration(seconds: 2), _listen);
    }
  }

  void pause() {
    _paused = true;
    _speech.cancel();
  }

  void resume() {
    if (!_enabled) return;
    _paused = false;
    _listen();
  }

  void stop() {
    _enabled = false;
    _paused = false;
    _speech.cancel();
  }
}