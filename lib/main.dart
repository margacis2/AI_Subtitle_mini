import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'domain/services/job_scheduler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JobScheduler().recoverOrphanedJobs();
  } catch (_) {}
  runApp(
    const ProviderScope(
      child: AISubMiniApp(),
    ),
  );
}
