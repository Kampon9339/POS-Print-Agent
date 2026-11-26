import 'package:flutter/services.dart';
import '../logging/app_logger.dart';

/// Platform abstraction for Desktop System Tray / macOS Menu Bar integration
/// and safe application shutdown.
class SystemTrayService {
  static const MethodChannel _channel = MethodChannel(
    'com.pos.printagent/tray',
  );

  final AppLogger logger;
  final Future<void> Function() onQuitRequested;
  final void Function()? onShowWindowRequested;

  SystemTrayService({
    required this.logger,
    required this.onQuitRequested,
    this.onShowWindowRequested,
  });

  Future<void> initialize({required String statusText}) async {
    try {
      _channel.setMethodCallHandler(_handleNativeCall);
      await _channel.invokeMethod<void>('initTray', {
        'title': 'POS Print',
        'status': statusText,
      });
    } catch (_) {
      // Ignored in headless test environments or when channel is not registered
    }
  }

  Future<void> updateStatus(String statusText) async {
    try {
      await _channel.invokeMethod<void>('updateTrayStatus', {
        'status': statusText,
      });
    } catch (_) {}
  }

  Future<void> hideToTray() async {
    try {
      await _channel.invokeMethod<void>('hideWindow');
      logger.info(
        'SystemTray',
        'Main window hidden to tray; Local API remains active',
      );
    } catch (_) {}
  }

  Future<void> showMainWindow() async {
    try {
      await _channel.invokeMethod<void>('showWindow');
      onShowWindowRequested?.call();
    } catch (_) {}
  }

  Future<void> requestSafeExit() async {
    logger.info('SystemTray', 'Safe exit requested');
    await onQuitRequested();
    try {
      await _channel.invokeMethod<void>('terminateApp');
    } catch (_) {}
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onTrayShowWindow':
        onShowWindowRequested?.call();
        break;
      case 'onTrayQuitApp':
        await requestSafeExit();
        break;
    }
  }
}
