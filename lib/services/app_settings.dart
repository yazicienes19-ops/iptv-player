import 'package:shared_preferences/shared_preferences.dart';

/// Vorlagen für die User-Agent-Tarnung.
enum UserAgentPreset {
  vlc('VLC', 'VLC/3.0.20 LibVLC/3.0.20'),
  smarters('IPTV Smarters', 'IPTVSmartersPlayer'),
  appleTv('Apple TV', 'AppleCoreMedia/1.0.0.21A342 (Apple TV; U; CPU OS 17_0 like Mac OS X)'),
  custom('Benutzerdefiniert', '');

  const UserAgentPreset(this.label, this.value);

  final String label;
  final String value;
}

/// Nicht-geheime Einstellungen; sie dürfen in SharedPreferences liegen.
class AppSettings {
  const AppSettings({this.killSwitch = false, this.userAgentPreset = UserAgentPreset.vlc, this.customUserAgent = ''});

  final bool killSwitch;
  final UserAgentPreset userAgentPreset;
  final String customUserAgent;

  /// Der tatsächlich gesendete User-Agent. Ein leeres Feld bei
  /// „Benutzerdefiniert“ fällt auf VLC zurück, damit nie der Dart-Standard rausgeht.
  String get userAgent {
    if (userAgentPreset != UserAgentPreset.custom) return userAgentPreset.value;
    final custom = customUserAgent.trim();
    return custom.isEmpty ? UserAgentPreset.vlc.value : custom;
  }

  AppSettings copyWith({bool? killSwitch, UserAgentPreset? userAgentPreset, String? customUserAgent}) => AppSettings(
    killSwitch: killSwitch ?? this.killSwitch,
    userAgentPreset: userAgentPreset ?? this.userAgentPreset,
    customUserAgent: customUserAgent ?? this.customUserAgent,
  );

  static const _killSwitchKey = 'settings.killSwitch.v1';
  static const _presetKey = 'settings.userAgentPreset.v1';
  static const _customKey = 'settings.customUserAgent.v1';

  factory AppSettings.load(SharedPreferences prefs) => AppSettings(
    killSwitch: prefs.getBool(_killSwitchKey) ?? false,
    userAgentPreset: UserAgentPreset.values.asNameMap()[prefs.getString(_presetKey)] ?? UserAgentPreset.vlc,
    customUserAgent: prefs.getString(_customKey) ?? '',
  );

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setBool(_killSwitchKey, killSwitch);
    await prefs.setString(_presetKey, userAgentPreset.name);
    await prefs.setString(_customKey, customUserAgent);
  }
}
