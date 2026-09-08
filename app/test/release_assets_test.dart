import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final root = Directory.current.parent;
  Map workflow(String name) =>
      loadYaml(File('${root.path}/.github/workflows/$name').readAsStringSync())
          as Map;

  test('every pushed change creates a versioned Windows and Android release', () {
    final release = workflow('release.yml');
    final triggers = release['on'] as Map;
    final jobs = release['jobs'] as Map;

    expect(triggers.keys, unorderedEquals(['push', 'workflow_dispatch']));
    expect(triggers['push']['branches'], ['**']);
    expect(triggers['push']['tags'], isNull);
    expect(jobs.keys, unorderedEquals(['version', 'windows', 'android', 'publish']));
    expect(jobs['windows']['needs'], 'version');
    expect(jobs['android']['needs'], 'version');
    expect(jobs['windows']['runs-on'], 'windows-latest');
    expect(jobs['android']['runs-on'], 'ubuntu-latest');
    expect(jobs['publish']['needs'], unorderedEquals(['version', 'windows', 'android']));
    expect(release['permissions']['contents'], 'write');
    expect(release['concurrency']['group'], 'openote-release');
    expect(release['concurrency']['cancel-in-progress'], false);
  });

  test('the Windows package has the injected app version and native core', () {
    final steps = workflow('release.yml')['jobs']['windows']['steps'] as List;
    final build = steps.singleWhere((s) => s['name'] == 'Build the Windows app');
    expect(build['run'], contains('--build-name='));
    expect(build['run'], contains('--dart-define=OPENOTE_VERSION='));
    expect(build['run'], contains('OPENOTE_REPOSITORY=Kingdaniel4747/openote'));

    final packer = File('${root.path}/packaging/windows/build-installer.ps1')
        .readAsStringSync();
    expect(packer, contains("'onote_core.dll'"));
    expect(packer, contains(r'Remove-Item -LiteralPath $taskStage'));
  });

  test('the Android package requires protected signing secrets', () {
    final steps = workflow('release.yml')['jobs']['android']['steps'] as List;
    final signing = steps.singleWhere(
        (s) => s['name'] == 'Configure the protected Android signing key');
    final env = signing['env'] as Map;
    expect(env.keys, containsAll([
      'KEYSTORE_BASE64',
      'KEYSTORE_PASSWORD',
      'KEY_ALIAS',
      'KEY_PASSWORD',
    ]));
    expect(signing['run'], contains('Missing Android signing secrets'));

    final gradle = File('${root.path}/scanner/android/app/build.gradle.kts')
        .readAsStringSync();
    expect(gradle, contains('openoteRelease'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test('the public release verifies and attaches both packages', () {
    final steps = workflow('release.yml')['jobs']['publish']['steps'] as List;
    final verify = steps.singleWhere((s) => s['name'] == 'Verify packages');
    expect(verify['run'], contains('windows-x64-setup.exe'));
    expect(verify['run'], contains('openote-scanner-'));
    final publish = steps.singleWhere((s) => s['name'] == 'Publish the release');
    expect(publish['with']['draft'], false);
    expect(publish['with']['target_commitish'], r'${{ github.sha }}');
  });

  test('Windows writing services use standard C++20 coroutines', () {
    final runner = File('windows/runner/CMakeLists.txt').readAsStringSync();
    expect(
        runner, contains(r'target_compile_features(${BINARY_NAME} PRIVATE cxx_std_20)'));
    expect(runner, isNot(contains('/await')));
    expect(runner,
        isNot(contains('_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS')));
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
