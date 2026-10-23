import 'dart:math' as math;

import 'package:lazerus_core/lazerus_core.dart';

const int hueCalibrationSchemaVersion = 1;

/// One fixed X/Y point on a hue-correction curve.
///
/// Both values are normalized over the protocol's supported hue interval.
class HueCalibrationAnchor {
  const HueCalibrationAnchor({required this.input, required this.output})
    : assert(input >= 0 && input <= 1),
      assert(output >= 0 && output <= 1);

  final double input;
  final double output;

  Map<String, Object> toJson() => <String, Object>{
    'input': input,
    'output': output,
  };

  static HueCalibrationAnchor? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final input = value['input'];
    final output = value['output'];
    if (input is! num || output is! num) {
      return null;
    }
    final normalizedInput = input.toDouble();
    final normalizedOutput = output.toDouble();
    if (!normalizedInput.isFinite ||
        !normalizedOutput.isFinite ||
        normalizedInput < 0 ||
        normalizedInput > 1 ||
        normalizedOutput < 0 ||
        normalizedOutput > 1) {
      return null;
    }
    return HueCalibrationAnchor(
      input: normalizedInput,
      output: normalizedOutput,
    );
  }
}

/// A protocol-scoped, piecewise-linear mapping from desired hue to command hue.
///
/// The curve is monotonic so it cannot make a colour interval fold back onto
/// itself. Saturation and value are deliberately preserved.
class HueCalibrationProfile {
  HueCalibrationProfile({
    required this.id,
    required this.name,
    required this.protocolId,
    required this.hueStartDegrees,
    required this.hueEndDegrees,
    required Iterable<HueCalibrationAnchor> anchors,
  }) : anchors = List<HueCalibrationAnchor>.unmodifiable(
         _validateAnchors(anchors),
       ) {
    if (id.trim().isEmpty || name.trim().isEmpty || protocolId.trim().isEmpty) {
      throw ArgumentError(
        'A calibration profile needs an id, name and protocol.',
      );
    }
    if (!hueStartDegrees.isFinite ||
        !hueEndDegrees.isFinite ||
        hueEndDegrees <= hueStartDegrees) {
      throw ArgumentError('Hue bounds must be finite and increasing.');
    }
  }

  final String id;
  final String name;
  final String protocolId;
  final double hueStartDegrees;
  final double hueEndDegrees;
  final List<HueCalibrationAnchor> anchors;

  factory HueCalibrationProfile.identity({
    required String id,
    required String name,
    required String protocolId,
    required double hueStartDegrees,
    required double hueEndDegrees,
  }) {
    return HueCalibrationProfile(
      id: id,
      name: name,
      protocolId: protocolId,
      hueStartDegrees: hueStartDegrees,
      hueEndDegrees: hueEndDegrees,
      anchors: const <HueCalibrationAnchor>[
        HueCalibrationAnchor(input: 0, output: 0),
        HueCalibrationAnchor(input: 1, output: 1),
      ],
    );
  }

  HueCalibrationProfile copyWith({
    String? id,
    String? name,
    String? protocolId,
    double? hueStartDegrees,
    double? hueEndDegrees,
    Iterable<HueCalibrationAnchor>? anchors,
  }) {
    return HueCalibrationProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      protocolId: protocolId ?? this.protocolId,
      hueStartDegrees: hueStartDegrees ?? this.hueStartDegrees,
      hueEndDegrees: hueEndDegrees ?? this.hueEndDegrees,
      anchors: anchors ?? this.anchors,
    );
  }

  /// Maps a normalized desired hue using linear interpolation between anchors.
  double mapNormalizedHue(double input) {
    final clamped = input.clamp(0.0, 1.0).toDouble();
    for (var index = 1; index < anchors.length; index++) {
      final left = anchors[index - 1];
      final right = anchors[index];
      if (clamped <= right.input) {
        final span = right.input - left.input;
        final ratio = span == 0 ? 0.0 : (clamped - left.input) / span;
        return left.output + (right.output - left.output) * ratio;
      }
    }
    return anchors.last.output;
  }

  /// Converts an app colour into the corrected protocol colour.
  ///
  /// Unsupported neutral colours and hues outside this profile's declared
  /// interval are left unchanged. The current Lotus UI never intentionally
  /// creates those colours, but this guard keeps the mapper safe for callers.
  RgbColor mapColor(RgbColor color) {
    final hsv = _Hsv.fromRgb(color);
    if (hsv.saturation <= 0.0001 || hsv.value <= 0.0001) {
      return color;
    }
    if (hsv.hue < hueStartDegrees || hsv.hue > hueEndDegrees) {
      return color;
    }
    final input =
        (hsv.hue - hueStartDegrees) / (hueEndDegrees - hueStartDegrees);
    final correctedHue =
        hueStartDegrees +
        (hueEndDegrees - hueStartDegrees) * mapNormalizedHue(input);
    return _Hsv(
      hue: correctedHue,
      saturation: hsv.saturation,
      value: hsv.value,
    ).toRgb();
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'protocolId': protocolId,
    'hueStartDegrees': hueStartDegrees,
    'hueEndDegrees': hueEndDegrees,
    'anchors': anchors.map((anchor) => anchor.toJson()).toList(),
  };

  static HueCalibrationProfile? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final id = value['id'];
    final name = value['name'];
    final protocolId = value['protocolId'];
    final hueStart = value['hueStartDegrees'];
    final hueEnd = value['hueEndDegrees'];
    final rawAnchors = value['anchors'];
    if (id is! String ||
        name is! String ||
        protocolId is! String ||
        hueStart is! num ||
        hueEnd is! num ||
        rawAnchors is! List<Object?>) {
      return null;
    }
    final anchors = rawAnchors
        .map(HueCalibrationAnchor.fromJson)
        .whereType<HueCalibrationAnchor>()
        .toList(growable: false);
    if (anchors.length != rawAnchors.length) {
      return null;
    }
    try {
      return HueCalibrationProfile(
        id: id,
        name: name,
        protocolId: protocolId,
        hueStartDegrees: hueStart.toDouble(),
        hueEndDegrees: hueEnd.toDouble(),
        anchors: anchors,
      );
    } on ArgumentError {
      return null;
    }
  }

  static List<HueCalibrationAnchor> _validateAnchors(
    Iterable<HueCalibrationAnchor> source,
  ) {
    final anchors = source.toList(growable: false)
      ..sort((left, right) => left.input.compareTo(right.input));
    if (anchors.length < 2 ||
        anchors.first.input != 0 ||
        anchors.first.output != 0 ||
        anchors.last.input != 1 ||
        anchors.last.output != 1) {
      throw ArgumentError('The curve must retain fixed 0 and 1 endpoints.');
    }
    for (var index = 1; index < anchors.length; index++) {
      final previous = anchors[index - 1];
      final current = anchors[index];
      if (current.input <= previous.input || current.output < previous.output) {
        throw ArgumentError('Anchors must have increasing input and output.');
      }
    }
    return anchors;
  }
}

/// Persisted calibration profiles and the device-to-profile assignment map.
class DeviceCalibrationConfiguration {
  DeviceCalibrationConfiguration({
    Iterable<HueCalibrationProfile> profiles = const <HueCalibrationProfile>[],
    Map<String, String> assignments = const <String, String>{},
  }) : profiles = List<HueCalibrationProfile>.unmodifiable(profiles),
       assignments = Map<String, String>.unmodifiable(
         _validAssignments(profiles, assignments),
       ) {
    final ids = this.profiles.map((profile) => profile.id).toSet();
    if (ids.length != this.profiles.length) {
      throw ArgumentError('Calibration profile ids must be unique.');
    }
  }

  final List<HueCalibrationProfile> profiles;
  final Map<String, String> assignments;

  const DeviceCalibrationConfiguration._empty()
    : profiles = const <HueCalibrationProfile>[],
      assignments = const <String, String>{};

  static const empty = DeviceCalibrationConfiguration._empty();

  HueCalibrationProfile? profileForDevice(String appDeviceId) {
    final id = assignments[appDeviceId];
    if (id == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  DeviceCalibrationConfiguration copyWith({
    Iterable<HueCalibrationProfile>? profiles,
    Map<String, String>? assignments,
  }) {
    return DeviceCalibrationConfiguration(
      profiles: profiles ?? this.profiles,
      assignments: assignments ?? this.assignments,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': hueCalibrationSchemaVersion,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
    'assignments': assignments,
  };

  static DeviceCalibrationConfiguration? fromJson(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value['schemaVersion'] != hueCalibrationSchemaVersion ||
        value['profiles'] is! List<Object?> ||
        value['assignments'] is! Map<Object?, Object?>) {
      return null;
    }
    final rawProfiles = value['profiles']! as List<Object?>;
    final profiles = rawProfiles
        .map(HueCalibrationProfile.fromJson)
        .whereType<HueCalibrationProfile>()
        .toList(growable: false);
    if (profiles.length != rawProfiles.length) {
      return null;
    }
    final assignments = <String, String>{};
    for (final entry
        in (value['assignments']! as Map<Object?, Object?>).entries) {
      if (entry.key is String && entry.value is String) {
        assignments[entry.key as String] = entry.value as String;
      } else {
        return null;
      }
    }
    try {
      return DeviceCalibrationConfiguration(
        profiles: profiles,
        assignments: assignments,
      );
    } on ArgumentError {
      return null;
    }
  }

  static Map<String, String> _validAssignments(
    Iterable<HueCalibrationProfile> profiles,
    Map<String, String> assignments,
  ) {
    final ids = profiles.map((profile) => profile.id).toSet();
    return Map<String, String>.fromEntries(
      assignments.entries.where((entry) => ids.contains(entry.value)),
    );
  }
}

class _Hsv {
  const _Hsv({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  factory _Hsv.fromRgb(RgbColor color) {
    final red = color.red / 255;
    final green = color.green / 255;
    final blue = color.blue / 255;
    final maximum = math.max(red, math.max(green, blue));
    final minimum = math.min(red, math.min(green, blue));
    final delta = maximum - minimum;
    if (delta == 0) {
      return _Hsv(hue: 0, saturation: 0, value: maximum);
    }
    final hue = switch (maximum) {
      _ when maximum == red => 60 * (((green - blue) / delta) % 6),
      _ when maximum == green => 60 * (((blue - red) / delta) + 2),
      _ => 60 * (((red - green) / delta) + 4),
    };
    return _Hsv(
      hue: hue < 0 ? hue + 360 : hue,
      saturation: maximum == 0 ? 0 : delta / maximum,
      value: maximum,
    );
  }

  RgbColor toRgb() {
    final normalizedHue = hue % 360;
    final chroma = value * saturation;
    final second = chroma * (1 - ((normalizedHue / 60) % 2 - 1).abs());
    final match = value - chroma;
    final (red, green, blue) = switch (normalizedHue) {
      < 60 => (chroma, second, 0.0),
      < 120 => (second, chroma, 0.0),
      < 180 => (0.0, chroma, second),
      < 240 => (0.0, second, chroma),
      < 300 => (second, 0.0, chroma),
      _ => (chroma, 0.0, second),
    };
    return RgbColor(
      ((red + match) * 255).round().clamp(0, 255).toInt(),
      ((green + match) * 255).round().clamp(0, 255).toInt(),
      ((blue + match) * 255).round().clamp(0, 255).toInt(),
    );
  }
}
