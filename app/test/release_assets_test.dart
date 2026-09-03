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
    expect(ci['permissions']['contents'], 'read');
    expect(workflow('release.yml')['permissions']['contents'], 'read');
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
