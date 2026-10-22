import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/app_providers.dart';
import 'services/push_service.dart';
import 'ui/widgets/store_intro.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  // Notifications on the phone (and which one opened the app, if any).
  await PushService.init();

  runApp(const ProviderScope(child: AxisTeamApp()));
}

class AxisTeamApp extends ConsumerWidget {
  const AxisTeamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final bright = ref.watch(effectiveBrightColorsProvider);
    final light =
        themeMode == ThemeMode.light ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.light);
    if (AppTheme.brightColors != bright || AppTheme.isLightTheme != light) {
      AppTheme.brightColors = bright;
      AppTheme.isLightTheme = light;
      // Repaint everything so widgets that read the palette directly update.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void rebuild(Element e) {
          e.markNeedsBuild();
          e.visitChildren(rebuild);
        }

        if (context.mounted) (context as Element).visitChildren(rebuild);
      });
    }
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Axis Team',
      theme: AppTheme.lightTheme(bright: bright),
      darkTheme: AppTheme.darkTheme(bright: bright),
      themeMode: themeMode,
      routerConfig: router,
      // After sign-in: the store's blueprint intro over the loading app.
      builder: (context, child) =>
          StoreIntroGate(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
    );
  }
}
