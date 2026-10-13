import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pure_live/core/utils/latest_async_value_queue.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

/// Holds Android CPU/Wi-Fi resources only while user-initiated background
/// playback is active. The foreground media service remains the primary
/// process-lifetime mechanism.
class BackgroundPlaybackService {
  static const _channel = MethodChannel('pure_live/background_playback');
  static bool sleepSessionActive = false;
  static bool audioOnlySessionActive = false;
  static bool? _appliedKeepAlive;
  static bool _initializedChannel = false;
  static final LatestAsyncValueQueue<bool> _keepAliveTransitions = LatestAsyncValueQueue<bool>(_applyKeepAlive);

  static void ensureInitialized() {
    if (_initializedChannel || !Platform.isAndroid) return;
    _initializedChannel = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        final inPip = (call.arguments is Map) ? (call.arguments['inPip'] as bool? ?? false) : false;
        GlobalPlayerService.instance.player.isInPip.value = inPip;
      }
    });
  }

  static Future<void> setKeepAlive(bool enabled) async {
    ensureInitialized();
    if (!Platform.isAndroid) return;
    if (!_keepAliveTransitions.isRunning && _appliedKeepAlive == enabled) return;
    await _keepAliveTransitions.submit(enabled);
  }

  static Future<void> setPipAutoEnter(bool enabled) async {
    ensureInitialized();
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setPipAutoEnter', {'enabled': enabled});
    } catch (_) {}
  }

  static Future<void> _applyKeepAlive(bool enabled) async {
    if (_appliedKeepAlive == enabled) return;
    try {
      await _channel.invokeMethod<void>('setKeepAlive', {'enabled': enabled});
      _appliedKeepAlive = enabled;
    } on PlatformException {
      // Older installations do not expose this channel yet.
      _appliedKeepAlive = enabled;
    }
  }
}
