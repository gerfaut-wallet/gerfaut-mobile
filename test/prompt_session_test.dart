import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/lock.dart';

/// The phone's prompt, played by the test: each prompt put up waits for
/// the test to say how it ended.
class _Phone {
  final List<Completer<PromptEnd>> prompts = [];

  Future<PromptEnd> attempt() {
    final prompt = Completer<PromptEnd>();
    prompts.add(prompt);
    return prompt.future;
  }

  void end(PromptEnd end) => prompts.last.complete(end);
}

/// A session asked for with the app in front, its prompt up: the app
/// lost the focus to it, as it does on a phone.
({_Phone phone, PromptSession session, List<BiometricOutcome> answers})
_asked() {
  final phone = _Phone();
  final session = PromptSession(phone.attempt);
  final answers = <BiometricOutcome>[];
  unawaited(session.run().then(answers.add));
  session.lifecycle(AppLifecycleState.inactive);
  return (phone: phone, session: session, answers: answers);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a strong biometric answers, once', () async {
    final s = _asked();
    s.phone.end(PromptEnd.passed);
    await _settle();
    expect(s.answers, [BiometricOutcome.passed]);
    // Whatever comes after changes nothing, and asks nothing again.
    s.session.lifecycle(AppLifecycleState.resumed);
    s.session.lifecycle(AppLifecycleState.paused);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.answers, [BiometricOutcome.passed]);
    expect(s.session.attempts, 1);
  });

  test('the prompt\'s own Cancel refuses at once, for good', () async {
    final s = _asked();
    s.phone.end(PromptEnd.refused);
    await _settle();
    expect(s.answers, [BiometricOutcome.refused]);
    s.session.lifecycle(AppLifecycleState.paused);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.session.attempts, 1);
  });

  test('a cancel followed by the focus back is the user\'s: refused', () async {
    // Back, or a touch outside the prompt: the app gets its focus back
    // and nothing left.
    final s = _asked();
    s.phone.end(PromptEnd.cancelled);
    await _settle();
    expect(s.answers, isEmpty);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.answers, [BiometricOutcome.refused]);
    // Never back: a later trip away and return asks nothing.
    s.session.lifecycle(AppLifecycleState.paused);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.session.attempts, 1);
  });

  test('a cancel coming after the focus is back is the user\'s too', () async {
    final s = _asked();
    s.session.lifecycle(AppLifecycleState.resumed);
    s.phone.end(PromptEnd.cancelled);
    await _settle();
    expect(s.answers, [BiometricOutcome.refused]);
  });

  test('the home gesture of Android 16 brings the prompt back', () async {
    // The cancel comes first, reported as the user's, then the app goes.
    final s = _asked();
    s.phone.end(PromptEnd.cancelled);
    await _settle();
    s.session.lifecycle(AppLifecycleState.hidden);
    s.session.lifecycle(AppLifecycleState.paused);
    await _settle();
    expect(s.answers, isEmpty);
    expect(s.session.attempts, 1);

    s.session.lifecycle(AppLifecycleState.hidden);
    s.session.lifecycle(AppLifecycleState.inactive);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.session.attempts, 2);
    expect(s.answers, isEmpty);
    s.phone.end(PromptEnd.passed);
    await _settle();
    expect(s.answers, [BiometricOutcome.passed]);
  });

  test('a system cancel after the app went brings the prompt back', () async {
    // Older Androids: the app goes first, then the prompt is cancelled.
    final s = _asked();
    s.session.lifecycle(AppLifecycleState.hidden);
    s.phone.end(PromptEnd.cancelled);
    await _settle();
    expect(s.answers, isEmpty);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.session.attempts, 2);
    // Turned down this time: answered, and never back.
    s.phone.end(PromptEnd.refused);
    await _settle();
    expect(s.answers, [BiometricOutcome.refused]);
    s.session.lifecycle(AppLifecycleState.paused);
    s.session.lifecycle(AppLifecycleState.resumed);
    await _settle();
    expect(s.session.attempts, 2);
  });

  test('a prompt that could not open comes back with the app', () async {
    // The activity had saved its state: it was leaving, even before the
    // app heard of it.
    for (final heardFirst in [true, false]) {
      final s = _asked();
      if (heardFirst) s.session.lifecycle(AppLifecycleState.paused);
      s.phone.end(PromptEnd.unshown);
      await _settle();
      expect(s.answers, isEmpty, reason: 'heard first: $heardFirst');
      if (!heardFirst) s.session.lifecycle(AppLifecycleState.paused);
      s.session.lifecycle(AppLifecycleState.resumed);
      await _settle();
      expect(s.session.attempts, 2, reason: 'heard first: $heardFirst');
      s.phone.end(PromptEnd.passed);
      await _settle();
      expect(s.answers, [BiometricOutcome.passed]);
    }
  });

  test('a missing or changed key is said as it is', () async {
    for (final (end, outcome) in [
      (PromptEnd.missing, BiometricOutcome.missing),
      (PromptEnd.reset, BiometricOutcome.reset),
    ]) {
      final s = _asked();
      s.phone.end(end);
      await _settle();
      expect(s.answers, [outcome]);
    }
  });

  test('an app that goes away for good refuses what was waiting', () async {
    final s = _asked();
    s.phone.end(PromptEnd.cancelled);
    await _settle();
    s.session.lifecycle(AppLifecycleState.detached);
    await _settle();
    expect(s.answers, [BiometricOutcome.refused]);
  });

  test('a prompt the platform fails on refuses', () async {
    final session = PromptSession(() => Future.error(StateError('no')));
    expect(await session.run(), BiometricOutcome.refused);
  });

  test('a prompt that ends after the answer changes nothing', () async {
    final s = _asked();
    s.session.lifecycle(AppLifecycleState.detached);
    await _settle();
    s.phone.end(PromptEnd.passed);
    await _settle();
    expect(s.answers, [BiometricOutcome.refused]);
  });

  test('the platform\'s words are read', () {
    expect(PromptEnd.parse('passed'), PromptEnd.passed);
    expect(PromptEnd.parse('missing'), PromptEnd.missing);
    expect(PromptEnd.parse('reset'), PromptEnd.reset);
    expect(PromptEnd.parse('unshown'), PromptEnd.unshown);
    expect(PromptEnd.parse('error:10'), PromptEnd.cancelled);
    expect(PromptEnd.parse('error:5'), PromptEnd.cancelled);
    // The prompt's own Cancel, a lockout, anything else: refused.
    for (final other in [
      'error:13',
      'error:7',
      'busy',
      'gone',
      'refused',
      null,
    ]) {
      expect(PromptEnd.parse(other), PromptEnd.refused, reason: '$other');
    }
  });
}
