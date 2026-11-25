import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/ink_eraser.dart';
import 'package:openote/ink/handwriting_profile.dart';
import 'package:openote/ink/ink_codec.dart';
import 'package:openote/model/models.dart';

Stroke sample({double y = 48, double width = 40}) => Stroke(
    tool: 'pen',
    colorHex: 'auto',
    size: 2.5,
    strokeStart: 0,
    x: [20, 20 + width],
    y: [y, 112],
    p: [.3, .7],
    tx: [.1, .2],
    ty: [.2, .3],
    t: [0, 40]);

void main() {
  void complete(HandwritingProfile profile) {
    for (final character in profile.pendingCharacters) {
      profile.addSample(character, [sample()]);
    }
  }

  test('requires own samples and reports exact missing characters', () {
    final profile = HandwritingProfile();
    expect(() => profile.generate('a'), throwsStateError);
    profile.addSample('a', [sample()]);
    expect(profile.isComplete, isFalse);
    expect(profile.pendingCharacters.first, 'b');
    expect(profile.learnedCharacters, 1);
    expect(profile.missing('aa A ä\n\t!'), {'A', 'ä', '!'});
    expect(() => profile.generate('ab'), throwsStateError);
    expect(() => profile.generate('a'), throwsStateError,
        reason:
            'even known text stays locked until the whole setup is complete');
    complete(profile);
    expect(profile.isComplete, isTrue);
    expect(() => profile.generate('é'), throwsStateError);
    expect(profile.generate('a').single.tool, 'ballpoint');
  });

  test('variants survive JSON and retain pen data without sharing arrays', () {
    final original = sample();
    final profile = HandwritingProfile()..addSample('ä', [original]);
    complete(profile);
    original.x[0] = 99;
    final restored =
        HandwritingProfile.fromJson(jsonDecode(jsonEncode(profile.toJson())));
    expect(restored.samples['ä']!.single.single.x.first, 20);
    final generated = restored.generate('ää',
        origin: const Offset(100, 200), height: 32, color: '#FF0000', size: 6);
    expect(generated[0].x, [100, 120]);
    expect(generated[0].y, [224, 256]);
    expect(generated[0].p, [.5, .5]);
    expect(restored.samples['ä']!.single.single.p, [.3, .7],
        reason:
            'legacy sensor data survives even though it no longer varies width');
    expect(generated[0].tx, [.1, .2]);
    expect(generated[0].t, [0, 40]);
    expect(generated[0].colorHex, '#FF0000');
    expect(generated[0].size, 6);
    expect(generated[0].id, isNot(generated[1].id));
    generated[0].x[0] = 900;
    expect(restored.samples['ä']!.single.single.x.first, 20);
  });

  test('cycles recorded variants and preserves descender placement', () {
    final profile = HandwritingProfile()
      ..addSample('g', [sample(y: 80)])
      ..addSample('g', [sample(y: 144)]);
    complete(profile);
    final ink = profile.generate('ggg', height: 64);
    expect(ink.map((s) => s.y.first), [80, 144, 80]);
  });

  test('word wrap, explicit newlines and spacing preserve writing size', () {
    final profile = HandwritingProfile()..addSample('a', [sample()]);
    complete(profile);
    final wrapped = profile.generate('aa aa', height: 32, width: 60);
    expect(wrapped[0].y, wrapped[1].y);
    expect(wrapped[2].y.first, greaterThan(wrapped[0].y.first));
    expect(wrapped[2].x.first, wrapped[0].x.first);
    final newline = profile.generate('a\r\na', height: 32);
    expect(newline[1].y.first - newline[0].y.first, 120);
    final compact = profile.generate('a a', wordSpacing: .5);
    final spaced = profile.generate('a a', wordSpacing: 2);
    expect(spaced[1].x.first, greaterThan(compact[1].x.first));
    expect(
        () => profile.generate('a', height: double.nan), throwsArgumentError);
  });

  test('line spacing below one reduces baseline distance without shrinking ink',
      () {
    final profile = HandwritingProfile();
    complete(profile);
    final normal = profile.generate('a\na', lineSpacing: 1);
    final tight = profile.generate('a\na', lineSpacing: .5);
    expect(tight[0].y, normal[0].y);
    expect(tight[1].y.first - tight[0].y.first,
        (normal[1].y.first - normal[0].y.first) / 2);
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => profile.generate('a', lineSpacing: invalid),
          throwsArgumentError);
    }
  });

  test('generated paths can be partially erased and encoded as normal ink', () {
    final profile = HandwritingProfile()..addSample('a', [sample()]);
    complete(profile);
    final stroke = profile.generate('a', height: 64).single;
    final parts =
        eraseStroke(stroke, const Offset(20, 80), const Offset(20, 80), 5);
    expect(parts, hasLength(2));
    expect(parts!.every((s) => s.p.length == s.x.length), isTrue);
    expect(profile.samples['a']!.single.single.x, [20, 60]);
    // The regular codec accepts generated paths, including erased fragments.
    final bytes = InkCodec.encode(parts, originX: 0, originY: 0);
    expect(bytes, isNotEmpty);
  });

  test('malformed samples do not destroy valid profile entries', () {
    final valid = sample().toJson();
    final profile = HandwritingProfile.fromJson({
      'v': 1,
      'samples': {
        'a': [
          [valid],
          ['broken']
        ],
        'b': [
          [sample(width: double.infinity).toJson()]
        ],
        'empty': [[]],
      }
    });
    expect(profile.samples.keys, ['a']);
    expect(profile.samples['a'], hasLength(1));
  });

  test('chosen variants can be replaced and removed without evicting others',
      () {
    final profile = HandwritingProfile();
    for (var i = 0; i < 5; i++) {
      expect(profile.saveVariant('a', [sample(y: 50.0 + i)]), isTrue);
    }
    final ids = profile.samples['a']!.map((v) => v.single.id).toList();
    expect(profile.saveVariant('a', [sample(y: 90)]), isFalse);
    expect(profile.samples['a']!.map((v) => v.single.id), ids);
    expect(profile.saveVariant('a', [sample(y: 80)], index: 1), isTrue);
    expect(profile.samples['a']![0].single.id, ids[0]);
    expect(profile.samples['a']![2].single.id, ids[2]);
    expect(profile.samples['a']![1].single.y.first, 80);
    profile.removeVariant('a', 3);
    final restored =
        HandwritingProfile.fromJson(jsonDecode(jsonEncode(profile.toJson())));
    expect(restored.samples['a'], hasLength(4));
    expect(restored.samples['a']!.last.single.id, ids[4]);
    expect(restored.samples['a']![1].single.y.first, 80);
  });
}
