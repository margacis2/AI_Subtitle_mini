import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagAsync = ref.watch(diagnosticsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device & System Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(diagnosticsProvider),
          ),
        ],
      ),
      body: diagAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading diagnostics: $err')),
        data: (diag) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // HARDWARE & CHIPSET
              _buildSectionHeader(theme, 'CPU & HARDWARE ACCELERATION', Icons.memory_rounded),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _row('Device Model', '${diag.manufacturer} ${diag.deviceModel}'),
                      _row('Operating System', diag.osVersion),
                      _row('CPU Architecture', diag.cpuArchitecture),
                      _row('CPU Cores', '${diag.cpuCoreCount} Cores active'),
                      _row(
                        'ARM NEON Acceleration',
                        diag.hasNeonAcceleration ? 'Enabled (Optimized SIMD)' : 'Standard Vector fallback',
                        highlight: diag.hasNeonAcceleration,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // MEMORY & BATTERY
              _buildSectionHeader(theme, 'BATTERY & THERMAL ADVISORY', Icons.battery_charging_full_rounded),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _row('Battery Level', '${diag.batteryLevel}%'),
                      _row('Charging State', diag.batteryState.name.toUpperCase()),
                      _row('Thermal Status', diag.thermalStatus, isWarning: diag.batteryLevel < 20),
                      _row('Memory Status', diag.ramTelemetry),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // NATIVE ENGINES
              _buildSectionHeader(theme, 'ON-DEVICE INFERENCE ENGINES', Icons.speed_rounded),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _row('Speech Engine', 'whisper.cpp (C++ Native FFI)'),
                      _row('Quantization', 'GGML 4-bit / 8-bit / 16-bit Quantized'),
                      _row('Translation Engine', 'ONNX Runtime Mobile (M2M-100 / Marian)'),
                      _row('Media Transcoder', 'FFmpeg Kit (pcm_s16le 16kHz mono)'),
                      _row('Database Engine', 'SQLite 3 (WAL mode enabled)'),
                      _row('Network Status', 'Local Processing Guarantee (No uploads)'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String val, {bool highlight = false, bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.grey))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              val,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isWarning
                    ? Colors.orangeAccent
                    : (highlight ? Colors.green : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
