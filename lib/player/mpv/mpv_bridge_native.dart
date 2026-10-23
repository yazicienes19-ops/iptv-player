import 'package:media_kit/media_kit.dart';

Future<void> mpvCommand(Player player, List<String> args) async {
  final platform = player.platform;
  if (platform is NativePlayer) await platform.command(args);
}

Future<void> mpvSetProperty(Player player, String name, String value) async {
  final platform = player.platform;
  if (platform is NativePlayer) await platform.setProperty(name, value);
}

Future<String?> mpvGetProperty(Player player, String name) async {
  final platform = player.platform;
  return platform is NativePlayer ? platform.getProperty(name) : null;
}
