// Minimal reproduction: on Windows, the render pipelines that flutter_scene
// compiles are compiled again at every launch of the application.
//
// The app builds a tiny lit scene, then warms it up three times, each time
// with one more feature (lit materials, sun shadows, ambient occlusion), and
// measures how long each warm-up takes. It then warms the last configuration
// again, to show that the cost is paid once per process.
//
// Every run appends its timings to a log file in the system temp directory,
// so that two consecutive launches can be compared.
//
//   flutter run -d windows --release
//   flutter run -d windows --release --dart-define=AUTO_EXIT=true

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Closes the app once the measurements are written (for scripted runs).
const _autoExit = bool.fromEnvironment('AUTO_EXIT');

void main() => runApp(const ReproApp());

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const ReproPage(),
  );
}

class ReproPage extends StatefulWidget {
  const ReproPage({super.key});

  @override
  State<ReproPage> createState() => _ReproPageState();
}

class _ReproPageState extends State<ReproPage> {
  final _lines = <String>[];
  Scene? _scene;
  bool _isDone = false;

  static final _logFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}pipeline_cache_repro.log',
  );

  @override
  void initState() {
    super.initState();
    // after the first frame, so that the engine and its surface exist
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _note(String line) {
    debugPrint(line);
    setState(() => _lines.add(line));
  }

  Future<void> _measure() async {
    try {
      final total = Stopwatch()..start();
      await Scene.initializeStaticResources();
      _note('static resources: ${total.elapsedMilliseconds} ms');

      final scene = Scene();
      final bounds = _populate(scene);
      final views = [RenderView(camera: PerspectiveCamera.framing(bounds))];

      Future<void> warm(String label) async {
        final clock = Stopwatch()..start();
        await scene.warmUp(views, includeOffscreen: true);
        _note('$label: ${clock.elapsedMilliseconds} ms');
      }

      _light(scene, hasShadows: false, hasOcclusion: false);
      await warm('1. lit materials');

      _light(scene, hasShadows: true, hasOcclusion: false);
      await warm('2. + directional shadows');

      _light(scene, hasShadows: true, hasOcclusion: true);
      await warm('3. + ambient occlusion');

      // Same configuration, same process: the pipelines are there already.
      await warm('4. same as 3, again');

      _note('total: ${total.elapsedMilliseconds} ms');
      final stamp = DateTime.now().toIso8601String();
      _logFile.writeAsStringSync(
        '--- launch at $stamp (${Platform.operatingSystemVersion})\n${_lines.join('\n')}\n',
        mode: FileMode.append,
      );
      _note('written to ${_logFile.path}');
      setState(() {
        _scene = scene;
        _isDone = true;
      });
      if (_autoExit) exit(0);
    } on Object catch (e, s) {
      _note('FAILED: $e');
      debugPrintStack(stackTrace: s);
      if (_autoExit) exit(1);
    }
  }

  /// A floor and a few boxes and spheres, all with the standard lit material.
  static vm.Aabb3 _populate(Scene scene) {
    PhysicallyBasedMaterial material(double r, double g, double b, double roughness) =>
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(r, g, b, 1)
          ..roughnessFactor = roughness
          ..metallicFactor = 0;

    scene.add(
      Node(
        name: 'floor',
        mesh: Mesh(PlaneGeometry(width: 12, depth: 12), material(0.8, 0.8, 0.8, 0.9)),
      ),
    );
    for (var i = 0; i < 9; i++) {
      final x = (i % 3 - 1) * 3.0;
      final z = (i ~/ 3 - 1) * 3.0;
      final isBox = i.isEven;
      scene.add(
        Node(
          name: 'item $i',
          mesh: Mesh(
            isBox ? CuboidGeometry(vm.Vector3(1.2, 1.2, 1.2)) : SphereGeometry(radius: 0.7),
            material(0.2 + 0.08 * i, 0.5, 0.9 - 0.08 * i, 0.5),
          ),
          localTransform: vm.Matrix4.translationValues(x, 0.7, z),
        ),
      );
    }
    return vm.Aabb3.minMax(vm.Vector3(-6, 0, -6), vm.Vector3(6, 2, 6));
  }

  static void _light(Scene scene, {required bool hasShadows, required bool hasOcclusion}) {
    scene
      ..directionalLight = DirectionalLight(
        direction: vm.Vector3(-0.4, -1, -0.3),
        castsShadow: hasShadows,
      )
      ..environmentSettings = EnvironmentSettings(ambientOcclusionEnabled: hasOcclusion);
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 380,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pipeline compile times, this launch',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final line in _lines) Text(line),
                  const SizedBox(height: 12),
                  if (!_isDone) const LinearProgressIndicator(),
                  if (_isDone)
                    const Text('Close the app and launch it again: steps 1 to 3 cost the same.'),
                ],
              ),
            ),
          ),
          Expanded(child: scene == null ? const SizedBox.shrink() : SceneView(scene)),
        ],
      ),
    );
  }
}
