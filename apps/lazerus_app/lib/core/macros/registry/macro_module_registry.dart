import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../modifiers/color/color_modifier.dart';
import '../modifiers/color_brightness_combine/color_brightness_combine_modifier.dart';
import '../modifiers/strobe/strobe_modifier.dart';
import '../sinks/lighting_target_sink.dart';
import '../triggers/microphone/microphone_mono_audio_trigger.dart';
import '../triggers/microphone/microphone_pcm_session.dart';
import '../triggers/multiband_eq/multiband_eq_trigger.dart';

/// The macro modules installed in this app build.
///
/// This is the only place that imports more than one concrete module. The
/// modules themselves remain independent and communicate solely through the
/// typed graph contract.
final macroModuleRegistryProvider = Provider<MacroModuleRegistry>((ref) {
  final microphone = MicrophoneMonoAudioTriggerFactory();
  ref.onDispose(() {
    unawaited(microphone.dispose());
  });
  return createMacroModuleRegistry(microphone: microphone);
});

/// Latest live microphone-capture state for the registered macro source.
///
/// This provider exposes status only, never PCM frames. The source factory
/// remains the owner of its session and is disposed with the registry.
final microphoneCaptureStatusProvider = StreamProvider<MicrophoneCaptureStatus>(
  (ref) {
    final factory = ref.watch(
      macroModuleRegistryProvider,
    )[MicrophoneMonoAudioTriggerFactory.moduleKind];
    return factory is MicrophoneMonoAudioTriggerFactory
        ? factory.statuses
        : Stream<MicrophoneCaptureStatus>.empty();
  },
);

/// Creates a registry suitable for runtime construction and tests.
MacroModuleRegistry createMacroModuleRegistry({
  MicrophoneMonoAudioTriggerFactory? microphone,
  MultibandEqTriggerFactory? multibandEq,
}) => MacroModuleRegistry()
  ..register(microphone ?? MicrophoneMonoAudioTriggerFactory())
  ..register(multibandEq ?? MultibandEqTriggerFactory())
  ..register(ColorModifierFactory())
  ..register(ColorBrightnessCombineModifierFactory())
  ..register(StrobeModifierFactory())
  ..register(LightingTargetSinkFactory());
