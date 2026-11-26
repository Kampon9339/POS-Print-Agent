import 'dart:async';
import 'dart:io';
import '../../platform/macos/macos_printer_adapter.dart';
import '../../platform/windows/windows_printer_adapter.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/printer_model.dart';

/// Represents a discovered printer candidate before or after registration.
class DiscoveredPrinterCandidate {
  final String name;
  final PrinterConnectionType connectionType;
  final PrinterProtocol protocol;
  final String? host;
  final int? port;
  final String? osDriverName;
  final bool isDefaultInOs;
  final bool isAvailable;

  const DiscoveredPrinterCandidate({
    required this.name,
    required this.connectionType,
    required this.protocol,
    this.host,
    this.port,
    this.osDriverName,
    this.isDefaultInOs = false,
    this.isAvailable = true,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'connectionType': connectionType.value,
    'connectionTypeLabel': connectionType.thaiLabel,
    'protocol': protocol.value,
    'protocolLabel': protocol.label,
    'host': host,
    'port': port,
    'osDriverName': osDriverName,
    'isDefaultInOs': isDefaultInOs,
    'isAvailable': isAvailable,
  };
}

/// Discovers OS, USB, and controlled-subnet LAN/Wi-Fi printers.
class PrinterDiscoveryService {
  final MacosPrinterAdapter macosAdapter;
  final WindowsPrinterAdapter windowsAdapter;

  const PrinterDiscoveryService({
    this.macosAdapter = const MacosPrinterAdapter(),
    this.windowsAdapter = const WindowsPrinterAdapter(),
  });

  /// Discovers printers registered in the operating system (including USB printers).
  Future<List<DiscoveredPrinterCandidate>> discoverOsAndUsbPrinters() async {
    final results = <String, DiscoveredPrinterCandidate>{};

    List<DiscoveredOsPrinter> nativeList = const [];
    if (Platform.isMacOS) {
      nativeList = await macosAdapter.listPrinters();
    } else if (Platform.isWindows) {
      nativeList = await windowsAdapter.listPrinters();
    }

    for (final p in nativeList) {
      results[p.name.toLowerCase()] = DiscoveredPrinterCandidate(
        name: p.name,
        connectionType:
            p.isUsb ? PrinterConnectionType.usb : PrinterConnectionType.os,
        protocol: PrinterProtocol.osDriver,
        osDriverName: p.name,
        isDefaultInOs: p.isDefault,
        isAvailable: p.isAvailable,
      );
    }

    return results.values.toList();
  }

  /// Probes a single IP address across standard network printer ports
  /// (9100 RAW TCP, 631 IPP, 515 LPR).
  Future<List<DiscoveredPrinterCandidate>> probeSingleHost(
    String host, {
    List<int> ports = const [
      AppConstants.defaultRawTcpPort,
      AppConstants.defaultIppPort,
      AppConstants.defaultLprPort,
    ],
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final cleanHost = host.trim();
    if (cleanHost.isEmpty) return const [];

    final found = <DiscoveredPrinterCandidate>[];
    for (final port in ports) {
      Socket? socket;
      try {
        socket = await Socket.connect(cleanHost, port, timeout: timeout);
        final protocol = _protocolForPort(port);
        found.add(
          DiscoveredPrinterCandidate(
            name: 'LAN Printer ($cleanHost:$port)',
            connectionType: PrinterConnectionType.lan,
            protocol: protocol,
            host: cleanHost,
            port: port,
            isAvailable: true,
          ),
        );
      } catch (_) {
        // Port not open on this host
      } finally {
        try {
          socket?.destroy();
        } catch (_) {}
      }
    }
    return found;
  }

  /// Controlled subnet discovery on a specified `/24` prefix (e.g. `192.168.1`)
  /// and bounded host range (`startHost`..`endHost`) to avoid indiscriminate network scanning.
  Future<List<DiscoveredPrinterCandidate>> discoverControlledSubnet({
    required String subnetPrefix,
    int startHost = 1,
    int endHost = 60,
    int port = AppConstants.defaultRawTcpPort,
    Duration timeout = const Duration(milliseconds: 350),
  }) async {
    final prefix = subnetPrefix.trim().replaceAll(RegExp(r'\.$'), '');
    final parts = prefix.split('.');
    if (parts.length != 3) {
      throw ArgumentError(
        'subnetPrefix must be a 3-octet IPv4 prefix such as "192.168.1".',
      );
    }

    final clampedStart = startHost.clamp(1, 254);
    final clampedEnd = endHost.clamp(clampedStart, 254);
    final candidates = <DiscoveredPrinterCandidate>[];
    const batchSize = 20;

    for (var i = clampedStart; i <= clampedEnd; i += batchSize) {
      final batchEnd =
          (i + batchSize - 1) < clampedEnd ? (i + batchSize - 1) : clampedEnd;
      final futures = <Future<List<DiscoveredPrinterCandidate>>>[];
      for (var hostOctet = i; hostOctet <= batchEnd; hostOctet++) {
        final ip = '$prefix.$hostOctet';
        futures.add(probeSingleHost(ip, ports: [port], timeout: timeout));
      }
      final batchResults = await Future.wait(futures);
      for (final list in batchResults) {
        candidates.addAll(list);
      }
    }

    return candidates;
  }

  PrinterProtocol _protocolForPort(int port) {
    switch (port) {
      case AppConstants.defaultIppPort:
        return PrinterProtocol.ipp;
      case AppConstants.defaultLprPort:
        return PrinterProtocol.lpr;
      default:
        return PrinterProtocol.rawTcp;
    }
  }
}
