import 'package:flutter/widgets.dart';

class AppLanguage extends InheritedWidget {
  const AppLanguage({
    super.key,
    required this.isThai,
    required this.onToggle,
    required super.child,
  });

  final bool isThai;
  final Future<void> Function(BuildContext) onToggle;

  static AppLanguage? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguage>();

  @override
  bool updateShouldNotify(AppLanguage oldWidget) => isThai != oldWidget.isThai;
}

extension AppTranslation on BuildContext {
  String tr(String thai, String english) =>
      (AppLanguage.of(this)?.isThai ?? true) ? thai : english;
}
