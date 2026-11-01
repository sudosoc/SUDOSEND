import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/scope.dart';
import 'platform/desktop.dart';
import 'state/app_controller.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop: a second launch ("Send to SUDOSEND", "Open with…") passes its
  // files to the running window instead of starting another instance.
  if (isDesktop && await SingleInstance.handOff(args)) exit(0);
  final controller = AppController(initialArgs: args)..init();
  runApp(SudoSendApp(controller: controller));
}

class SudoSendApp extends StatelessWidget {
  const SudoSendApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: controller.settings,
      child: ListenableBuilder(
        listenable: controller.settings,
        builder: (context, _) {
          final lang = controller.settings.lang;
          return MaterialApp(
            title: 'SUDOSEND',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(arabic: lang == 'ar'),
            locale: Locale(lang),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: HomeScreen(controller: controller),
          );
        },
      ),
    );
  }
}
