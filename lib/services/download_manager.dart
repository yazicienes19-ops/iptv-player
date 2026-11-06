import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'personal_library.dart';

enum DownloadStatus { queued, downloading, paused, done, failed }

enum DownloadKind {
  /// Film oder Folge: die Datei des Anbieters wird komplett geladen.
  vod,

  /// Mitschnitt eines Live-Senders, solange er im Player läuft.
  recording,
}

/// Ein Download oder eine Aufnahme. Enthält die Stream-URL (mit Zugangsdaten),
/// darum liegt das Verzeichnis im Schlüsselbund, nicht in einer Klartextdatei.
class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.kind,
    required this.channel,
    required this.playlistId,
    required this.title,
    required this.fileName,
    required this.createdAt,
    this.subtitle,
    this.poster,
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total,
    this.error,
    this.finishedAt,
    this.recordedFor,
    this.segments,
    this.note,
  });

  final String id;
  final DownloadKind kind;
  final Channel channel;
  final String? playlistId;
  final String title;

  /// z. B. „Staffel 2 · Folge 5“ oder der Sendername bei Aufnahmen.
  final String? subtitle;
  final String? poster;
  final String fileName;
  final DownloadStatus status;
  final int received;
  final int? total;
  final String? error;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final Duration? recordedFor;

  /// Wird in so vielen Teilen gleichzeitig geladen (`null` = eine Verbindung).
  final int? segments;

  /// Warum mit dieser Verbindungszahl geladen wird (z. B. Anbieterlimit), für die Anzeige.
  final String? note;

  bool get isDone => status == DownloadStatus.done;
  bool get isActive => status == DownloadStatus.downloading;
  double? get fraction => total == null || total! <= 0 ? null : (received / total!).clamp(0.0, 1.0);

  DownloadItem copyWith({
    DownloadStatus? status,
    int? received,
    int? Function()? total,
    String? Function()? error,
    DateTime? finishedAt,
    Duration? recordedFor,
    int? Function()? segments,
    String? Function()? note,
  }) => DownloadItem(
    id: id,
    kind: kind,
    channel: channel,
    playlistId: playlistId,
    title: title,
    subtitle: subtitle,
    poster: poster,
    fileName: fileName,
    createdAt: createdAt,
    status: status ?? this.status,
    received: received ?? this.received,
    total: total != null ? total() : this.total,
    error: error != null ? error() : this.error,
    finishedAt: finishedAt ?? this.finishedAt,
    recordedFor: recordedFor ?? this.recordedFor,
    segments: segments != null ? segments() : this.segments,
    note: note != null ? note() : this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'channel': channel.toJson(),
    'playlistId': playlistId,
    'title': title,
    'subtitle': subtitle,
    'poster': poster,
    'fileName': fileName,
    'status': status.name,
    'received': received,
    'total': total,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'recordedForMs': recordedFor?.inMilliseconds,
    'seg': segments,
    'note': note,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
    id: json['id'] as String,
    kind: DownloadKind.values.asNameMap()[json['kind']] ?? DownloadKind.vod,
    channel: Channel.fromJson((json['channel'] as Map).cast<String, dynamic>()),
    playlistId: json['playlistId'] as String?,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    poster: json['poster'] as String?,
    fileName: json['fileName'] as String,
    status: DownloadStatus.values.asNameMap()[json['status']] ?? DownloadStatus.paused,
    received: json['received'] as int? ?? 0,
    total: json['total'] as int?,
    error: json['error'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
    recordedFor: json['recordedForMs'] == null ? null : Duration(milliseconds: json['recordedForMs'] as int),
    segments: json['seg'] as int?,
    note: json['note'] as String?,
  );
}

/// Liest und schreibt das Download-Verzeichnis (in der App: Schlüsselbund).
abstract class DownloadIndexStore {
  Future<String?> read();
  Future<void> write(String json);
}

class MemoryDownloadIndexStore implements DownloadIndexStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

/// Schlüssel eines Downloads: Playlist plus derselbe Schlüssel wie beim Fortsetzen.
String downloadIdFor(String? playlistId, Channel channel) => '${playlistId ?? '-'}|${personalItemKey(channel)}';

/// Dateiendung aus der Stream-URL; unbekannte Endungen werden zu `.mp4`.
String downloadExtension(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  const known = {'mp4', 'mkv', 'avi', 'mov', 'm4v', 'ts', 'webm', 'mpg', 'mpeg', 'wmv', 'flv'};
  return known.contains(ext) ? ext : 'mp4';
}

/// Lesbarer, für alle Dateisysteme gültiger Dateiname mit kurzer Eindeutigkeit.
String safeFileName(String title, String unique, String ext) {
  var base = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (base.length > 80) base = base.substring(0, 80).trim();
  if (base.isEmpty || base.startsWith('.')) base = 'Video$base';
  final hash = unique.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  return '$base [$hash].$ext';
}

/// HLS-Wiedergabelisten (m3u8) bestehen aus vielen Teilstücken und lassen sich so nicht laden.
bool isDownloadable(Channel channel) {
  if (channel.type == ContentType.live || !channel.isPlayable) return false;
  final path = (Uri.tryParse(channel.streamUrl)?.path ?? channel.streamUrl).toLowerCase();
  return !path.endsWith('.m3u8') && !path.endsWith('.m3u');
}

typedef DownloadListener = void Function(List<DownloadItem> items);

/// Lädt nacheinander (die meisten Anbieter erlauben nur 1–2 Verbindungen),
/// setzt abgebrochene Downloads per HTTP-Range fort und hält das Verzeichnis aktuell.
class DownloadEngine {
  DownloadEngine({
    required this.dio,
    required this.directory,
    required this.store,
    required this.onChange,
    this.beforeRequest,
    this.connectionBudget,
    this.minSegmentedSize = 64 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Dio dio;
  final Future<Directory> Function() directory;
  final DownloadIndexStore store;
  final DownloadListener onChange;

  /// z. B. VPN-Kill-Switch; wirft, wenn gerade nichts geladen werden darf.
  final Future<void> Function()? beforeRequest;

  /// Wie viele Verbindungen ein Download gleichzeitig nutzen darf (Anbieterlimit minus
  /// laufende Streams). Ohne Angabe nur eine.
  /// `null` heißt: Der Anbieter nennt kein Limit.
  final Future<int?> Function()? connectionBudget;
  final DateTime Function() _now;

  /// Höchstens so viele Teile; mehr bringt selten etwas und fällt Anbietern auf.
  static const maxSegments = 4;

  /// Kleinere Dateien lohnen das Aufteilen nicht.
  final int minSegmentedSize;

  List<DownloadItem> _items = const [];
  List<DownloadItem> get items => _items;

  String? _activeId;
  CancelToken? _cancel;

  /// Was beim Abbrechen mit dem aktiven Download passieren soll.
  DownloadStatus? _cancelReason;
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  /// Schlägt das Lesen fehl (z. B. Schlüsselbund-Abfrage abgelehnt), wird beim nächsten
  /// Zugriff erneut gelesen statt bis zum Neustart blockiert zu bleiben. Nie mit leerer
  /// Liste weitermachen: Sie würde das gespeicherte Verzeichnis überschreiben.
  Future<void> load() => _loading ??= _load().catchError((Object error, StackTrace stack) {
    _loading = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _load() async {
    try {
      final raw = await store.read();
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items = [
          for (final json in list)
            () {
              final item = DownloadItem.fromJson(json);
              // Beim letzten Beenden unterbrochen: Downloads weiterladen, Aufnahmen abschließen.
              if (item.status == DownloadStatus.downloading) {
                return item.kind == DownloadKind.recording
                    ? item.copyWith(status: DownloadStatus.done, finishedAt: item.finishedAt ?? _now())
                    : item.copyWith(status: DownloadStatus.queued);
              }
              return item;
            }(),
        ];
      }
    } on FormatException {
      _items = const [];
    } on TypeError {
      _items = const [];
    }
    _loaded = true;
    _emit();
    unawaited(_pump());
  }

  DownloadItem? byId(String id) => _items.where((i) => i.id == id).firstOrNull;

  Future<File> fileOf(DownloadItem item) async => File('${(await directory()).path}/${item.fileName}');

  Future<void> enqueue(
    Channel channel, {
    String? playlistId,
    required String title,
    String? subtitle,
    String? poster,
  }) async {
    await load();
    if (!isDownloadable(channel)) return;
    final id = downloadIdFor(playlistId, channel);
    final existing = byId(id);
    if (existing != null) {
      if (existing.status == DownloadStatus.failed || existing.status == DownloadStatus.paused) {
        await resume(id);
      }
      return;
    }
    final item = DownloadItem(
      id: id,
      kind: DownloadKind.vod,
      channel: channel,
      playlistId: playlistId,
      title: title,
      subtitle: subtitle,
      poster: poster,
      fileName: safeFileName([title, ?subtitle].join(' - '), id, downloadExtension(channel.streamUrl)),
      createdAt: _now(),
    );
    _items = [..._items, item];
    _emit();
    await _persist();
    unawaited(_pump());
  }

  Future<void> pause(String id) async {
    final item = byId(id);
    if (item == null || item.kind == DownloadKind.recording) return;
    if (_activeId == id) {
      _cancelReason = DownloadStatus.paused;
      _cancel?.cancel();
    } else if (item.status == DownloadStatus.queued) {
      _update(id, (i) => i.copyWith(status: DownloadStatus.paused));
      await _persist();
    }
  }

  Future<void> resume(String id) async {
    final item = byId(id);
    if (item == null || item.isDone || item.isActive || item.kind == DownloadKind.recording) return;
    _update(id, (i) => i.copyWith(status: DownloadStatus.queued, error: () => null));
    await _persist();
    unawaited(_pump());
  }

  /// Entfernt Eintrag und Datei (auch halbfertige Teile).
  Future<void> remove(String id) async {
    final item = byId(id);
    if (item == null) return;
    if (_activeId == id) {
      _cancelReason = DownloadStatus.failed;
      _cancel?.cancel();
    }
    _items = [
      for (final i in _items)
        if (i.id != id) i,
    ];
    _emit();
    await _persist();
    final file = await fileOf(item);
    for (final f in [file, File('${file.path}.part'), for (var i = 0; i < maxSegments; i++) _segmentFile(file, i)]) {
      try {
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Datei wird evtl. noch abgespielt; der Eintrag ist trotzdem weg.
      }
    }
  }

  // --- Aufnahmen -------------------------------------------------------------------

  /// Legt eine laufende Aufnahme an und liefert den Zielpfad für den Player.
  Future<(String id, String path)> beginRecording(Channel channel, {String? playlistId, String? poster}) async {
    await load();
    final started = _now();
    final stamp =
        '${started.year}-${_two(started.month)}-${_two(started.day)} ${_two(started.hour)}.${_two(started.minute)}';
    final id = 'rec|${started.microsecondsSinceEpoch}|${channel.id}';
    final item = DownloadItem(
      id: id,
      kind: DownloadKind.recording,
      channel: channel,
      playlistId: playlistId,
      title: channel.name,
      subtitle:
          'Aufnahme vom ${_two(started.day)}.${_two(started.month)}.${started.year}, ${_two(started.hour)}:${_two(started.minute)} Uhr',
      poster: poster,
      fileName: safeFileName('Aufnahme ${channel.name} $stamp', id, 'mkv'),
      createdAt: started,
      status: DownloadStatus.downloading,
    );
    _items = [..._items, item];
    _emit();
    await _persist();
    return (id, (await fileOf(item)).path);
  }

  Future<void> updateRecordingSize(String id) async {
    final item = byId(id);
    if (item == null) return;
    final file = await fileOf(item);
    final size = await file.exists() ? await file.length() : 0;
    if (size != item.received) _update(id, (i) => i.copyWith(received: size));
  }

  Future<void> finishRecording(String id, {String? error}) async {
    final item = byId(id);
    if (item == null) return;
    final file = await fileOf(item);
    final size = await file.exists() ? await file.length() : 0;
    final finished = _now();
    if (size == 0) {
      // Nichts angekommen: keinen leeren Eintrag behalten.
      await remove(id);
      return;
    }
    _update(
      id,
      (i) => i.copyWith(
        status: DownloadStatus.done,
        received: size,
        total: () => size,
        error: () => error,
        finishedAt: finished,
        recordedFor: finished.difference(i.createdAt),
      ),
    );
    await _persist();
  }

  // --- Lade-Schleife ---------------------------------------------------------------

  Future<void> _pump() async {
    if (!_loaded || _activeId != null) return;
    final next = _items.where((i) => i.status == DownloadStatus.queued && i.kind == DownloadKind.vod).firstOrNull;
    if (next == null) return;
    _activeId = next.id;
    _cancelReason = null;
    _update(next.id, (i) => i.copyWith(status: DownloadStatus.downloading, error: () => null));
    await _persist();
    try {
      await _download(next);
    } finally {
      _activeId = null;
      _cancel = null;
      await _persist();
      unawaited(_pump());
    }
  }

  static File _segmentFile(File target, int i) => File('${target.path}.part$i');

  Future<void> _download(DownloadItem item) async {
    final target = await fileOf(item);
    final part = File('${target.path}.part');
    try {
      await target.parent.create(recursive: true);
      await beforeRequest?.call();
      final cancel = CancelToken();
      _cancel = cancel;
      var segments = item.segments;
      // Ein angefangener Einzel-Download wird auch so zu Ende geladen.
      if (segments == null && !await part.exists()) {
        segments = await _planSegments(item, cancel);
        if (segments != null) await _persist();
      }
      final current = byId(item.id) ?? item;
      if (segments != null && segments > 1 && current.total != null) {
        await _downloadSegmented(current, target, segments, cancel);
      } else {
        await _downloadSingle(current, target, part, cancel);
      }
    } on DioException catch (e) {
      // Nur vom Nutzer abgebrochen zählt als Pause/Löschen; der Kill-Switch bricht ebenfalls ab.
      if (CancelToken.isCancel(e) && _cancelReason != null) {
        if (_cancelReason == DownloadStatus.paused) {
          _update(item.id, (i) => i.copyWith(status: DownloadStatus.paused));
        }
        return; // Beim Löschen ist der Eintrag schon weg.
      }
      _fail(item.id, _describe(e));
    } on _DownloadError catch (e) {
      _fail(item.id, e.message);
    } on FileSystemException catch (e) {
      _fail(item.id, 'Speichern fehlgeschlagen: ${e.osError?.message ?? e.message}');
    } catch (e) {
      // Kill-Switch und Ähnliches: verständliche Meldung statt Absturz der Schleife.
      _fail(item.id, '$e');
    }
  }

  static void _checkVideo(Response<ResponseBody> response) {
    final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
    if (contentType.startsWith('text/') || contentType.contains('json')) {
      throw const _DownloadError('Der Anbieter hat statt einer Videodatei eine Fehlerseite geliefert.');
    }
  }

  /// Fragt das freie Verbindungsbudget ab und prüft mit einem 1-Byte-Abruf, ob der
  /// Anbieter Teilabrufe (HTTP-Range) kann. Liefert die Teilezahl oder `null` für einen Strom.
  Future<int?> _planSegments(DownloadItem item, CancelToken cancel) async {
    int? reported;
    try {
      reported = await connectionBudget?.call();
    } catch (_) {
      reported = null;
    }
    void explain(String note) => _update(item.id, (i) => i.copyWith(note: () => note));
    if (reported == null) {
      explain('1 Verbindung: Der Anbieter nennt kein Verbindungslimit.');
      return null;
    }
    final budget = reported.clamp(1, maxSegments);
    if (budget < 2) {
      explain(
        reported <= 0
            ? '1 Verbindung: Alle Verbindungen deines Kontos sind gerade belegt.'
            : '1 Verbindung: Dein Konto erlaubt gerade nur eine freie Verbindung.',
      );
      return null;
    }
    final probe = await dio.get<ResponseBody>(
      item.channel.streamUrl,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-0'},
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    _checkVideo(probe);
    await probe.data?.stream.drain<void>();
    final total = int.tryParse(
      RegExp(r'/(\d+)$').firstMatch(probe.headers.value('content-range') ?? '')?.group(1) ?? '',
    );
    if (probe.statusCode != 206 || total == null) {
      explain('1 Verbindung: Der Anbieter erlaubt kein Laden in Teilen.');
      return null;
    }
    if (total < minSegmentedSize) return null;
    _update(item.id, (i) => i.copyWith(total: () => total, segments: () => budget, note: () => null));
    return budget;
  }

  Future<void> _downloadSegmented(DownloadItem item, File target, int count, CancelToken cancel) async {
    final total = item.total!;
    final size = (total / count).ceil();
    final ranges = [
      for (var i = 0; i < count; i++)
        if (i * size < total) (i * size, ((i + 1) * size).clamp(0, total) - 1),
    ];
    final got = [
      for (var i = 0; i < ranges.length; i++)
        await _segmentFile(target, i).exists() ? await _segmentFile(target, i).length() : 0,
    ];
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    void emit({bool force = false}) {
      final now = DateTime.now();
      if (!force && now.difference(lastEmit) < const Duration(milliseconds: 400)) return;
      lastEmit = now;
      final received = got.fold<int>(0, (sum, n) => sum + n);
      _update(item.id, (i) => i.copyWith(received: received));
    }

    emit(force: true);

    Future<void> fetch(int index) async {
      final (start, end) = ranges[index];
      final length = end - start + 1;
      if (got[index] >= length) return;
      final response = await dio.get<ResponseBody>(
        item.channel.streamUrl,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=${start + got[index]}-$end'},
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      _checkVideo(response);
      if (response.statusCode != 206) {
        throw const _DownloadError('Der Anbieter liefert keine Teilstücke mehr. Bitte erneut versuchen.');
      }
      final sink = _segmentFile(target, index).openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.data!.stream) {
          _throwIfCancelled(cancel, response);
          sink.add(chunk);
          got[index] += chunk.length;
          emit();
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (got[index] < length) {
        throw const _DownloadError(
          'Die Verbindung wurde vor dem Ende getrennt. Weiterladen setzt an derselben Stelle fort.',
        );
      }
    }

    // Alle Teile gleichzeitig. Meldet der Anbieter „zu viele Verbindungen“, kommen diese
    // Teile danach einzeln dran, statt den Download abzubrechen.
    final limited = <int>[];
    await Future.wait([
      for (var i = 0; i < ranges.length; i++)
        () async {
          try {
            await fetch(i);
          } on DioException catch (e) {
            if (!CancelToken.isCancel(e) && _isConnectionLimit(e)) {
              limited.add(i);
              return;
            }
            if (!cancel.isCancelled) cancel.cancel();
            rethrow;
          } catch (_) {
            if (!cancel.isCancelled) cancel.cancel();
            rethrow;
          }
        }(),
    ]);
    for (final i in limited..sort()) {
      await fetch(i);
    }
    emit(force: true);

    // Teile zu einer Datei zusammensetzen: an Teil 0 anhängen und umbenennen.
    final first = _segmentFile(target, 0);
    final sink = first.openWrite(mode: FileMode.append);
    try {
      for (var i = 1; i < ranges.length; i++) {
        await sink.addStream(_segmentFile(target, i).openRead());
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (await first.length() != total) {
      throw const _DownloadError('Die Teile ergeben nicht die ganze Datei. Bitte löschen und neu laden.');
    }
    for (var i = 1; i < ranges.length; i++) {
      await _segmentFile(target, i).delete();
    }
    if (await target.exists()) await target.delete();
    await first.rename(target.path);
    _update(
      item.id,
      (i) => i.copyWith(status: DownloadStatus.done, received: total, total: () => total, finishedAt: _now()),
    );
  }

  /// Dio beendet einen schon laufenden Datenstrom beim Abbrechen nicht immer; das Verlassen
  /// der Schleife schließt die Verbindung sofort.
  static void _throwIfCancelled(CancelToken cancel, Response<ResponseBody> response) {
    if (cancel.isCancelled) {
      throw DioException.requestCancelled(requestOptions: response.requestOptions, reason: cancel.cancelError);
    }
  }

  /// Typische Antworten, wenn das Konto schon alle erlaubten Verbindungen nutzt.
  static bool _isConnectionLimit(DioException e) => const {403, 429, 458, 503, 509}.contains(e.response?.statusCode);

  Future<void> _downloadSingle(DownloadItem item, File target, File part, CancelToken cancel) async {
    var start = await part.exists() ? await part.length() : 0;
    final response = await dio.get<ResponseBody>(
      item.channel.streamUrl,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: {if (start > 0) 'Range': 'bytes=$start-'},
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    _checkVideo(response);
    if (start > 0 && response.statusCode != 206) start = 0; // Kein Fortsetzen möglich: von vorne.
    final length = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
    final rangeTotal = RegExp(r'/(\d+)$').firstMatch(response.headers.value('content-range') ?? '')?.group(1);
    final total = int.tryParse(rangeTotal ?? '') ?? (length == null ? null : start + length);

    final sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
    var received = start;
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    _update(item.id, (i) => i.copyWith(received: received, total: () => total));
    try {
      await for (final chunk in response.data!.stream) {
        _throwIfCancelled(cancel, response);
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastEmit) > const Duration(milliseconds: 400)) {
          lastEmit = now;
          _update(item.id, (i) => i.copyWith(received: received));
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total != null && received < total) {
      throw const _DownloadError(
        'Die Verbindung wurde vor dem Ende getrennt. Weiterladen setzt an derselben Stelle fort.',
      );
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    _update(
      item.id,
      (i) => i.copyWith(status: DownloadStatus.done, received: received, total: () => received, finishedAt: _now()),
    );
  }

  void _fail(String id, String message) =>
      _update(id, (i) => i.copyWith(status: DownloadStatus.failed, error: () => message));

  static String _describe(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return 'Zugriff verweigert ($code). Läuft gerade ein anderer Stream? Viele Anbieter erlauben nur eine Verbindung.';
    }
    if (code == 404) return 'Datei beim Anbieter nicht gefunden (404).';
    if (e.error != null && e.type == DioExceptionType.cancel) return '${e.error}';
    if (code != null) return 'Der Anbieter antwortet mit Fehler $code.';
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout => 'Zeitüberschreitung. Weiterladen setzt an derselben Stelle fort.',
      DioExceptionType.connectionError => 'Keine Verbindung zum Anbieter.',
      _ => e.message ?? 'Download fehlgeschlagen.',
    };
  }

  void _update(String id, DownloadItem Function(DownloadItem) change) {
    _items = [for (final i in _items) i.id == id ? change(i) : i];
    _emit();
  }

  void _emit() => onChange(_items);

  Future<void> _persist() {
    final json = jsonEncode([for (final i in _items) i.toJson()]);
    return _writes = _writes.then((_) => store.write(json)).catchError((Object _) {});
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _DownloadError implements Exception {
  const _DownloadError(this.message);

  final String message;
}
