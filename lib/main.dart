import 'package:flutter/material.dart';
import 'shared/constants/app_constants.dart';
import 'shared/services/service_locator.dart';
import 'ui/app_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AgentServiceContainer.initializeProduction();

  if (args.contains('--minimized')) {
    await services.systemTrayService.hideToTray();
  }

  runApp(PosPrintAgentApp(services: services));
}

/// Root Flutter widget for the POS Print Agent Desktop Application.
class PosPrintAgentApp extends StatelessWidget {
  final AgentServiceContainer services;

  const PosPrintAgentApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: AppShell(services: services),
    );
  }
}
