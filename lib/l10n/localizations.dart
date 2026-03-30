import 'package:flutter/widgets.dart';

import 'app_strings.dart';
import 'strings_en.dart';
import 'strings_zh.dart';

const String kLanguageKey = 'language';

/// Returns the [AppStrings] for the given language preference.
/// [lang] must be 'auto', 'zh', or 'en'.
AppStrings resolveStrings(String lang) {
  if (lang == 'zh') return AppStringsZh();
  if (lang == 'en') return AppStringsEn();
  // auto: follow system locale
  final code =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return code.startsWith('zh') ? AppStringsZh() : AppStringsEn();
}

/// Global language notifier.
/// Update [appLocale.value] to switch the app language at runtime.
final ValueNotifier<AppStrings> appLocale =
    ValueNotifier(resolveStrings('auto'));

/// Global timezone notifier.
/// null = use device system timezone.
/// int  = minutes offset from UTC (e.g. 480 = UTC+8).
final ValueNotifier<int?> appTimezone = ValueNotifier<int?>(null);

/// InheritedWidget that provides [AppStrings] to the widget tree.
/// Wrap the root widget with this and call [AppL10n.of(context)] anywhere below.
class AppL10n extends InheritedWidget {
  const AppL10n({
    super.key,
    required this.strings,
    required super.child,
  });

  final AppStrings strings;

  /// Access the current [AppStrings] from any widget.
  static AppStrings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppL10n>()!.strings;

  @override
  bool updateShouldNotify(AppL10n old) => strings != old.strings;
}
