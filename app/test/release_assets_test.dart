import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final root = Directory.current.parent;
  Map workflow(String name) =>
      loadYaml(File('${root.path}/.github/workflows/$name').readAsStringSync())
          as Map;

  test('only Windows is automatic; Linux requires an explicit manual choice',
      () {
    final release = workflow('release.yml');
    final jobs = release['jobs'] as Map;
    expect(jobs.keys, unorderedEquals(['windows', 'linux']));
    expect((release['on'] as Map).keys,
        unorderedEquals(['push', 'workflow_dispatch']));
    expect(jobs['windows']['uses'], './.github/workflows/ci.yml');
    expect(jobs['windows']['with']['publish'], true);
    expect(release['on']['push']['tags'], isNull);
    expect(release['concurrency']['cancel-in-progress'], false);
    expect(release['concurrency']['queue'], 'max');
    expect(release['concurrency']['group'], isNot(contains('github.ref')));
    expect(jobs['linux']['if'],
        "github.event_name == 'workflow_dispatch' && inputs.platform == 'linux'");
    final choice = release['on']['workflow_dispatch']['inputs']['platform'];
    expect(choice['default'], 'windows');
    expect(choice['options'], ['windows', 'linux']);
    expect(jobs['linux']['needs'], isNull,
        reason: 'Linux is independent of Windows');
  });

  test('reusable Windows build tests and uploads only a setup EXE', () {
    final ci = workflow('ci.yml');
    expect((ci['on'] as Map).keys,
        unorderedEquals(['workflow_call', 'workflow_dispatch']));
    final jobs = ci['jobs'] as Map;
    expect(jobs.keys, ['windows']);
    expect(jobs['windows']['runs-on'], 'windows-latest');
    final steps = jobs['windows']['steps'] as List;
    expect(
        steps.any((s) => s['run'] == 'flutter test --reporter github'), true);
    expect(steps.any((s) => s['run'] == 'cargo test --all-targets'), true);
    expect(steps.any((s) => s['run'] == 'cargo deny check licenses'), true);
    final upload =
        steps.singleWhere((s) => s['uses'] == 'actions/upload-artifact@v4');
    expect(upload['with']['path'], 'openote-*-windows-x64-setup.exe');
    expect(ci['permissions']['contents'], 'write');
    expect(workflow('release.yml')['permissions']['contents'], 'write');
    final publish = steps
        .singleWhere((s) => s['name'] == 'Publish versioned Windows release');
    expect(publish['if'], 'inputs.publish');
    expect(publish['run'], contains('gh release create'));
    expect(publish['run'], contains(r'--target $env:GITHUB_SHA'));
    expect(publish['run'], isNot(contains('--clobber')));
    expect(steps.indexOf(publish), greaterThan(steps.indexOf(upload)));
    final build = steps.singleWhere((s) => s['name'] == 'Build Windows');
    expect(build['run'], contains(r'--build-name=$env:VERSION'));
    expect(
        build['run'], contains(r'--dart-define=OPENOTE_VERSION=$env:VERSION'));
    expect(build['run'], contains('--dart-define=OPENOTE_REPOSITORY='));
  });

  test('Windows package cache avoids the hidden AppData path', () {
    final steps = workflow('ci.yml')['jobs']['windows']['steps'] as List;
    final flutter =
        steps.singleWhere((s) => s['uses'] == 'subosito/flutter-action@v2');
    expect(flutter['with']['pub-cache-path'],
        r'${{ runner.temp }}/openote-pub-cache');
  });

  test('Windows writing services use standard C++20 coroutines', () {
    final runner = File('windows/runner/CMakeLists.txt').readAsStringSync();
    expect(
        runner,
        contains(
            r'target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)'));
    expect(runner, isNot(contains('/await')));
    expect(
        runner,
        isNot(
            contains('_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS')));
    final writing =
        File('windows/runner/writing_services.cpp').readAsStringSync();
    final standardHeader = writing.indexOf('#include <coroutine>');
    expect(standardHeader, greaterThanOrEqualTo(0));
    expect(standardHeader, lessThan(writing.indexOf('#include <winrt/')));
  });

  test('Windows and Linux targets remain, Apple target is removed', () {
    expect(File('windows/CMakeLists.txt').existsSync(), true);
    expect(File('linux/CMakeLists.txt').existsSync(), true);
    expect(Directory('macos').existsSync(), false);
    final metadata = loadYaml(File('.metadata').readAsStringSync());
    final platforms =
        (metadata['migration']['platforms'] as List).map((p) => p['platform']);
    expect(platforms, unorderedEquals(['root', 'windows', 'linux']));
  });
}
