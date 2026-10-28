import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController()..init();
  runApp(SudoSendApp(controller: controller));
}

class SudoSendApp extends StatelessWidget {
  const SudoSendApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SUDOSEND',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(controller: controller),
    );
  }
}
