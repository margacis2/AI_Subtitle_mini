import 'package:go_router/go_router.dart';

import '../features/about/presentation/about_screen.dart';
import '../features/batch_queue/presentation/batch_queue_screen.dart';
import '../features/diagnostics/presentation/diagnostics_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/language_packs/presentation/language_packs_screen.dart';
import '../features/media_import/presentation/new_project_screen.dart';
import '../features/model_library/presentation/model_library_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/subtitle_editor/presentation/subtitle_editor_screen.dart';
import '../features/translation/presentation/translate_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/new-project',
      builder: (context, state) => const NewProjectScreen(),
    ),
    GoRoute(
      path: '/editor/:id',
      builder: (context, state) {
        final projectId = state.pathParameters['id'] ?? '';
        return SubtitleEditorScreen(projectId: projectId);
      },
    ),
    GoRoute(
      path: '/translate',
      builder: (context, state) => const TranslateScreen(),
    ),
    GoRoute(
      path: '/models',
      builder: (context, state) => const ModelLibraryScreen(),
    ),
    GoRoute(
      path: '/language-packs',
      builder: (context, state) => const LanguagePacksScreen(),
    ),
    GoRoute(
      path: '/batch-queue',
      builder: (context, state) => const BatchQueueScreen(),
    ),
    GoRoute(
      path: '/diagnostics',
      builder: (context, state) => const DiagnosticsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const AboutScreen(),
    ),
  ],
);
