import 'package:flutter/widgets.dart';

import '../state/settings.dart';
import 'strings.dart';

const String kAppVersion = '0.11.0';

/// Makes settings (language, effects) available to every widget and rebuilds
/// dependents when they change.
class AppScope extends InheritedNotifier<SettingsController> {
  const AppScope(
      {super.key, required SettingsController settings, required super.child})
      : super(notifier: settings);

  static SettingsController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static SettingsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
}

extension AppContext on BuildContext {
  String tr(String key, [Map<String, Object?> args = const {}]) =>
      trLang(AppScope.maybeOf(this)?.lang ?? 'en', key, args);

  /// full | balanced | lite
  String get effects => AppScope.maybeOf(this)?.effects ?? 'balanced';
  bool get reducedEffects => effects == 'lite';
  bool get fullEffects => effects == 'full';
}

String trLang(String lang, String key, Map<String, Object?> args) =>
    tr(lang, key, args);
