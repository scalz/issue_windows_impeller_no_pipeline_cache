# issue_windows_impeller_no_pipeline_cache

Minimal reproduction: on Windows, the render pipelines that `flutter_scene`
compiles through Flutter GPU are compiled again at every launch.

Related to [flutter/flutter#191860](https://github.com/flutter/flutter/issues/191860)
(no persisted GL programs with Impeller on ANGLE) and to the program cache
proposed in [flutter/flutter#193419](https://github.com/flutter/flutter/pull/193419).

## What it does

The app builds a scene of ten primitives with the standard lit material and
calls `Scene.warmUp` three times, each time with one more feature, then once
more with the last configuration. Each step only pays for what the previous
ones did not compile.

## Running it

```bash
flutter run -d windows --release
```

Close the window and run it again: steps 1 to 3 cost the same. Each launch
appends its timings to `%TEMP%\pipeline_cache_repro.log`.

For a scripted run that closes by itself:

```bash
flutter build windows --release --dart-define=AUTO_EXIT=true
```

```bash
build/windows/x64/runner/Release/issue_windows_impeller_no_pipeline_cache.exe
```

## Results

Release builds, Ryzen 5 2600, Radeon RX 580 (driver 31.0.21923.11000),
Windows 11 25H2. Three consecutive launches of the same build.

Stable 3.47.6 (engine 692136cb65):

| Step                               | Launch 1 | Launch 2 | Launch 3 |
| ---------------------------------- | --------:| --------:| --------:|
| 1. lit materials                   | 1840 ms  | 1928 ms  | 1862 ms  |
| 2. + directional shadows           | 5935 ms  | 6589 ms  | 5859 ms  |
| 3. + ambient occlusion             | 15751 ms | 15643 ms | 16118 ms |
| 4. same as 3, again (same process) | 9 ms     | 6 ms     | 2 ms     |
| Total                              | 23.5 s   | 24.2 s   | 23.8 s   |

`main` channel, 3.49.0-1.0.pre-418:

| Step                               | Launch 1 | Launch 2 | Launch 3 |
| ---------------------------------- | --------:| --------:| --------:|
| 1. lit materials                   | 3119 ms  | 3090 ms  | 3084 ms  |
| 2. + directional shadows           | 4637 ms  | 4580 ms  | 4616 ms  |
| 3. + ambient occlusion             | 12413 ms | 12121 ms | 12411 ms |
| 4. same as 3, again (same process) | 1 ms     | 1 ms     | 1 ms     |
| Total                              | 20.5 s   | 20.1 s   | 20.5 s   |

Steps 1 to 3 build 3, 2 and 4 pipelines (counted on stable through
`flutter_scene`'s pipeline cache). Two programs carry most of the time: the
lit fragment shader with shadows (`StandardLeanFragment`, step 2) and its
full variant, used once ambient occlusion is on (`StandardFragment`, step 3).

## What differs from a new project

- `lib/main.dart`: the reproduction.
- `pubspec.yaml`: `flutter_scene: 0.24.3` and `vector_math`.
- `windows/runner/main.cpp`: one line, `project.set_enable_flutter_gpu(true);`.
