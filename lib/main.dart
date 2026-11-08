import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'firebase_options.dart';

final db = FirebaseFirestore.instance;
final notif = FlutterLocalNotificationsPlugin();
Future<void> initNotif() async {
  await notif.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings()));
  await notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
}

void notify(String t) => notif.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
    'Manhunt',
    t,
    const NotificationDetails(
      android: AndroidNotificationDetails('alerts', 'Upozornění', importance: Importance.max, priority: Priority.high, playSound: true, enableVibration: true),
      iOS: DarwinNotificationDetails(),
    ));
late String uid;
double d(x) => (x as num).toDouble();
const palette = <Color>[Colors.green, Colors.blue, Colors.orange, Colors.purple, Colors.pink, Colors.cyan, Colors.red, Colors.yellow];
const icons = ['🏃', '🕵️', '🧟', '🦊', '🐺', '🐱', '👻', '🦅', '🚀', '🔥'];
Widget colorDots(int sel, void Function(int)? onTap) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < palette.length; i++)
        GestureDetector(
          onTap: onTap == null ? null : () => onTap(i),
          child: Container(margin: const EdgeInsets.all(4), width: 28, height: 28, decoration: BoxDecoration(color: palette[i], shape: BoxShape.circle, border: Border.all(color: sel == i ? Colors.white : Colors.transparent, width: 3))),
        ),
    ]);

InputDecoration deco(String l, [IconData? i]) => InputDecoration(
      labelText: l,
      prefixIcon: i == null ? null : Icon(i),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initNotif();
  uid = (await FirebaseAuth.instance.signInAnonymously()).user!.uid;
  runApp(MaterialApp(
    title: 'Manhunt',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00E676), brightness: Brightness.dark)),
    home: const Home(),
  ));
}

Future<Position> getPos() async {
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw 'Poloha není povolena';
  return Geolocator.getCurrentPosition();
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final name = TextEditingController(), code = TextEditingController();
  String mode = 'classic';
  bool busy = false;
  String icon = '🏃';
  int colorIdx = 0;

  void snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> go(Future<String> Function() f) async {
    if (name.text.trim().isEmpty) return snack('Zadej jméno');
    setState(() => busy = true);
    try {
      final c = await f();
      await db.collection('games/$c/players').doc(uid).set({'name': name.text.trim(), 'icon': icon, 'color': colorIdx}, SetOptions(merge: true));
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(code: c)));
    } catch (e) {
      snack('$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<String> create() async {
    final p = await getPos();
    final c = '${1000 + Random().nextInt(9000)}';
    await db.collection('games').doc(c).set({
      'mode': mode, 'status': 'lobby', 'host': uid, 'lat': p.latitude, 'lng': p.longitude,
      'radius': 500, 'headStart': 120, 'interval': 120, 'duration': 3600, 'catchDist': 25, 'startedAt': 0, 'zoneColor': 0, 'shrinkPct': 100, 'poly': [],
    });
    return c;
  }

  Future<String> join() async {
    final c = code.text.trim();
    if (!(await db.collection('games').doc(c).get()).exists) throw 'Hra neexistuje';
    await getPos();
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              Icon(Icons.radar, size: 80, color: cs.primary),
              const SizedBox(height: 8),
              Text('MANHUNT', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 4)),
              const Text('Honička s živou mapou', textAlign: TextAlign.center),
              const SizedBox(height: 28),
              TextField(controller: name, decoration: deco('Tvoje jméno', Icons.person)),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                for (final e in icons) ChoiceChip(label: Text(e, style: const TextStyle(fontSize: 20)), selected: icon == e, onSelected: (_) => setState(() => icon = e)),
              ]),
              const SizedBox(height: 6),
              colorDots(colorIdx, (i) => setState(() => colorIdx = i)),
              const SizedBox(height: 10),
              TextField(maxLength: 8, decoration: deco('Nebo vlastní emoji (napiš nebo vlož)', Icons.emoji_emotions).copyWith(counterText: ''), onChanged: (v) { if (v.trim().isNotEmpty) setState(() => icon = v.trim()); }),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'classic', label: Text('Klasický'), icon: Icon(Icons.directions_run)),
                  ButtonSegment(value: 'zombie', label: Text('Zombie'), icon: Icon(Icons.coronavirus)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setState(() => mode = s.first),
              ),
              const SizedBox(height: 8),
              Text(mode == 'zombie' ? 'Chycený hledaný se stane zombie a honí dál.' : 'Chycený hledaný vypadává ze hry.',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: busy ? null : () => go(create),
                icon: const Icon(Icons.add),
                label: const Text('Vytvořit hru'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('nebo')), Expanded(child: Divider())]),
              ),
              Row(children: [
                Expanded(child: TextField(controller: code, keyboardType: TextInputType.number, maxLength: 4, decoration: deco('Kód hry', Icons.pin).copyWith(counterText: ''))),
                const SizedBox(width: 12),
                FilledButton.tonal(style: FilledButton.styleFrom(minimumSize: const Size(110, 56)), onPressed: busy ? null : () => go(join), child: const Text('Připojit')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  final String code;
  const GameScreen({super.key, required this.code});
  @override
  State<GameScreen> createState() => _GameState();
}

class _GameState extends State<GameScreen> {
  late final game = db.collection('games').doc(widget.code);
  late final me = game.collection('players').doc(uid);
  StreamSubscription<Position>? sub;
  Timer? tick;
  Position? pos;
  int lastPub = 0;
  Map<String, dynamic> g = {};
  List<Map<String, dynamic>> ps = [];
  final Map<String, int> tmp = {};
  final List<LatLng> trail = [];
  bool editing = false, darkMap = true, wasOut = false;
  int lastWarn = 0, shrinkStep = 10, lastPing = 0, battery = 100, tickN = 0;
  bool lowWarned = false;
  final bat = Battery();
  StreamSubscription? pingSub;
  List<Map<String, dynamic>> pings = [];

  String role(Map p) => p['role'] ?? 'runner';
  Map<String, dynamic> get mep => ps.firstWhere((p) => p['id'] == uid, orElse: () => <String, dynamic>{});
  String get myRole => role(mep);
  bool on(Map p, String k) => ((p[k] ?? 0) as int) > nowMs;
  bool get zombie => g['mode'] == 'zombie';
  int get nowMs => DateTime.now().millisecondsSinceEpoch;
  int get elapsed => g['status'] == 'running' ? (nowMs - (g['startedAt'] as int)) ~/ 1000 : 0;
  bool get inHeadStart => g['status'] == 'running' && elapsed < (g['headStart'] as int);
  String get status {
    final s = g['status'] ?? 'lobby';
    if (s == 'running' && (!ps.any((p) => role(p) == 'runner') || elapsed > (g['duration'] as int))) return 'ended';
    return s;
  }

  List<LatLng> get poly => ((g['poly'] ?? []) as List).map((e) => LatLng(d(e['lat']), d(e['lng']))).toList();
  Color get zcol => palette[((g['zoneColor'] ?? 0) as int) % palette.length];
  double get zf {
    if (g['status'] != 'running') return 1;
    final hs = g['headStart'] as int, du = g['duration'] as int;
    final t = ((elapsed - hs) / max(1, du - hs)).clamp(0.0, 1.0);
    return 1 - (1 - d(g['shrinkPct'] ?? 100) / 100) * t;
  }

  List<LatLng> get zonePoly {
    final p = poly;
    if (p.length < 3) return [];
    final cy = p.map((e) => e.latitude).reduce((a, b) => a + b) / p.length, cx = p.map((e) => e.longitude).reduce((a, b) => a + b) / p.length;
    return p.map((e) => LatLng(cy + (e.latitude - cy) * zf, cx + (e.longitude - cx) * zf)).toList();
  }

  bool inside(double la, double lo) {
    final z = zonePoly;
    if (z.isEmpty) return Geolocator.distanceBetween(la, lo, d(g['lat']), d(g['lng'])) <= d(g['radius'] ?? 500) * zf;
    var c = false;
    for (var i = 0, j = z.length - 1; i < z.length; j = i++) {
      if ((z[i].latitude > la) != (z[j].latitude > la) && lo < (z[j].longitude - z[i].longitude) * (la - z[i].latitude) / (z[j].latitude - z[i].latitude) + z[i].longitude) c = !c;
    }
    return c;
  }

  void buzz(String m) {
    HapticFeedback.heavyImpact();
    notify(m);
    snack(m);
  }

  void alerts() {
    if (g['status'] != 'running' || pos == null || myRole == 'caught') return;
    final out = !inside(pos!.latitude, pos!.longitude);
    if (out != wasOut) {
      wasOut = out;
      buzz(out ? '⚠️ Opustil jsi zónu!' : '✅ Jsi zpátky v zóně');
    }
    final step = (zf * 10).floor();
    if (step < shrinkStep) buzz('🔴 Zóna se zmenšuje!');
    shrinkStep = step;
    if (nowMs - lastWarn < 20000 || (inHeadStart && myRole == 'hunter')) return;
    final want = myRole == 'runner' ? 'hunter' : 'runner';
    for (final p in ps) {
      if (role(p) != want || p['id'] == uid || p['lat'] == null || on(p, 'hideUntil')) continue;
      final dd = Geolocator.distanceBetween(pos!.latitude, pos!.longitude, d(p['lat']), d(p['lng']));
      if (dd < 100) {
        lastWarn = nowMs;
        buzz(myRole == 'runner' ? '🚨 Lovec do ${dd.round()} m!' : '👀 Hledaný do ${dd.round()} m');
        return;
      }
    }
  }

  String dir(double h) => const ['S', 'SV', 'V', 'JV', 'J', 'JZ', 'Z', 'SZ'][(((h % 360) + 22.5) ~/ 45) % 8];

  Color col(String r) => r == 'hunter' ? (zombie ? Colors.green : Colors.red) : r == 'caught' ? Colors.grey : Colors.blue;
  String roleLabel(String r) => r == 'runner' ? 'Hledaný' : r == 'hunter' ? (zombie ? 'Zombie' : 'Lovec') : 'Chycen';

  @override
  void initState() {
    super.initState();
    pingSub = game.collection('pings').snapshots().listen((q) => pings = q.docs.map((x) => x.data()).toList());
    final LocationSettings s = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            distanceFilter: 3,
            foregroundNotificationConfig: const ForegroundNotificationConfig(notificationTitle: 'Manhunt', notificationText: 'Hra běží', enableWakeLock: true))
        : AppleSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 3,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
            pauseLocationUpdatesAutomatically: false);
    sub = Geolocator.getPositionStream(locationSettings: s).listen((p) {
      pos = p;
      trail.add(LatLng(p.latitude, p.longitude));
      if (trail.length > 500) trail.removeAt(0);
      me.set({'lat': p.latitude, 'lng': p.longitude}, SetOptions(merge: true));
    });
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (g['status'] == 'running' && myRole == 'runner' && pos != null && !on(mep, 'hideUntil') && nowMs - lastPub >= (g['interval'] as int) * 1000) {
        lastPub = nowMs;
        me.set({'pubLat': pos!.latitude, 'pubLng': pos!.longitude}, SetOptions(merge: true));
      }
      alerts();
      if (++tickN % 30 == 1) {
        bat.batteryLevel.then((b) {
          battery = b;
          me.set({'battery': b}, SetOptions(merge: true));
          if (b < 15 && !lowWarned) {
            lowWarned = true;
            buzz('🔋 Slabá baterie: $b %');
          }
        }).catchError((_) {});
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    pingSub?.cancel();
    tick?.cancel();
    super.dispose();
  }

  void snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  String fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  String fmtT(int s) => s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${s % 60} s';

  Future<void> start() async {
    final r = ps.where((p) => role(p) == 'runner').length, h = ps.where((p) => role(p) == 'hunter').length;
    if (r < 1 || h < 1) return snack('Potřeba aspoň 1 hledaný a 1 lovec');
    await game.update({'status': 'running', 'startedAt': nowMs});
  }

  Future<void> catchNear() async {
    if (pos == null) return;
    final b = db.batch();
    var n = 0;
    final dist = d(g['catchDist'] ?? 25);
    for (final p in ps) {
      if (role(p) != 'runner' || p['lat'] == null) continue;
      if (Geolocator.distanceBetween(pos!.latitude, pos!.longitude, d(p['lat']), d(p['lng'])) <= dist) {
        b.update(game.collection('players').doc(p['id']), {'role': zombie ? 'hunter' : 'caught'});
        n++;
      }
    }
    if (n > 0) {
      b.update(game, {'lastCatch': {'lat': pos!.latitude, 'lng': pos!.longitude, 'at': nowMs}});
      await b.commit();
    }
    snack(n > 0 ? 'Chyceno: $n' : 'Nikdo v dosahu ${dist.round()} m');
  }

  String head() {
    final s = status;
    if (s == 'lobby') return 'Lobby';
    if (s == 'ended') {
      return ps.any((p) => role(p) == 'runner') ? 'Hledaní přežili!' : (zombie ? 'Zombie vyhráli!' : 'Lovci vyhráli!');
    }
    final hs = g['headStart'] as int;
    return inHeadStart ? 'Náskok ${hs - elapsed} s' : 'Zbývá ${fmt((g['duration'] as int) - elapsed)}';
  }

  List<Marker> markers() {
    final m = <Marker>[];
    final hide = myRole == 'hunter' && inHeadStart;
    for (final p in ps) {
      final r = role(p), mine = p['id'] == uid;
      if ((r == 'caught' && !mine) || (!mine && r == 'runner' && (hide || (myRole == 'hunter' && on(p, 'hideUntil'))))) continue;
      final blur = !mine && r == 'runner' && myRole == 'hunter' && g['status'] == 'running' && !on(mep, 'radarUntil');
      final lat = (blur ? p['pubLat'] : null) ?? p['lat'], lng = (blur ? p['pubLng'] : null) ?? p['lng'];
      if (lat == null || lng == null) continue;
      final n = (p['name'] ?? '?') as String;
      m.add(Marker(
        point: LatLng(d(lat), d(lng)), width: 80, height: 56,
        child: Opacity(
          opacity: blur ? .75 : 1,
          child: Column(children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: mine ? Colors.white : col(r),
              child: CircleAvatar(radius: 13, backgroundColor: palette[((p['color'] ?? 0) as int) % palette.length], child: Text((p['icon'] ?? '🏃') as String, style: const TextStyle(fontSize: 14))),
            ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
              child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ]),
        ),
      ));
    }
    for (final pg in pings) {
      if (pg['role'] == myRole && nowMs - (pg['ts'] as int) < 60000) {
        m.add(Marker(point: LatLng(d(pg['lat']), d(pg['lng'])), width: 40, height: 40, child: const Text('📍', style: TextStyle(fontSize: 26))));
      }
    }
    final lc = g['lastCatch'];
    if (lc != null) m.add(Marker(point: LatLng(d(lc['lat']), d(lc['lng'])), width: 40, height: 40, child: const Text('💀', style: TextStyle(fontSize: 26))));
    return m;
  }

  Future<void> pingTeam() async {
    if (pos == null || nowMs - lastPing < 15000) return snack('Ping se nabíjí');
    lastPing = nowMs;
    await game.collection('pings').add({'lat': pos!.latitude, 'lng': pos!.longitude, 'role': myRole, 'ts': nowMs});
    snack('Ping odeslán týmu');
  }

  Widget sl(String key, String label, double mn, double mx, double st, num def, String Function(int) f, bool host) {
    final v = d(tmp[key] ?? g[key] ?? def).clamp(mn, mx).toDouble();
    return Column(children: [
      Row(children: [Text(label), const Spacer(), Text(f(v.round()), style: const TextStyle(fontWeight: FontWeight.bold))]),
      Slider(
        value: v, min: mn, max: mx, divisions: ((mx - mn) / st).round(),
        onChanged: host ? (x) => setState(() => tmp[key] = x.round()) : null,
        onChangeEnd: (x) async {
          await game.update({key: x.round()});
          tmp.remove(key);
        },
      ),
    ]);
  }

  Widget panel(Widget child) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .55),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: SafeArea(top: false, child: child),
        ),
      );

  Widget lobby(bool host) => panel(ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('KÓD HRY', style: TextStyle(fontSize: 11, letterSpacing: 2)),
            Text(widget.code, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 8)),
          ]),
          const Spacer(),
          IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: widget.code)); snack('Kód zkopírován'); }),
          Chip(label: Text(zombie ? 'Zombie' : 'Klasický')),
        ]),
        const SizedBox(height: 8),
        Text('Hráči (${ps.length})${host ? ' · klepnutím změníš roli' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in ps)
            ActionChip(
              avatar: CircleAvatar(backgroundColor: col(role(p)), radius: 8),
              label: Text('${p['name'] ?? '?'} · ${roleLabel(role(p))}'),
              onPressed: host ? () => game.collection('players').doc(p['id']).update({'role': role(p) == 'runner' ? 'hunter' : 'runner'}) : () {},
            ),
        ]),
        const Divider(height: 28),
        Text(host ? 'Nastavení hry' : 'Nastavení hry (mění hostitel)', style: const TextStyle(fontWeight: FontWeight.bold)),
        sl('radius', 'Poloměr zóny', 100, 2000, 50, 500, (v) => '$v m', host),
        sl('headStart', 'Náskok hledaných', 0, 600, 30, 120, fmtT, host),
        sl('interval', 'Odhalení polohy každých', 30, 600, 30, 120, fmtT, host),
        sl('duration', 'Délka hry', 600, 7200, 300, 3600, fmtT, host),
        sl('catchDist', 'Dosah chycení', 10, 50, 5, 25, (v) => '$v m', host),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Perky (zmizení, zmrazení, radar)'),
          value: g['perks'] != false,
          onChanged: host ? (v) => game.update({'perks': v}) : null,
        ),
        sl('shrinkPct', 'Zóna na konci hry', 10, 100, 5, 100, (v) => v == 100 ? 'nezmenšuje se' : '$v %', host),
        const Text('Barva zóny'),
        colorDots(((g['zoneColor'] ?? 0) as int), host ? (i) => game.update({'zoneColor': i}) : null),
        if (host)
          Wrap(spacing: 8, children: [
            FilterChip(label: const Text('Kreslit zónu (klepej na mapu)'), selected: editing, onSelected: (v) => setState(() => editing = v)),
            ActionChip(label: const Text('Zpět'), onPressed: poly.isEmpty ? null : () => game.update({'poly': (g['poly'] as List).sublist(0, (g['poly'] as List).length - 1)})),
            ActionChip(label: const Text('Kruh'), onPressed: () => game.update({'poly': []})),
          ]),
        const SizedBox(height: 8),
        if (host)
          FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)), onPressed: start, icon: const Icon(Icons.play_arrow), label: const Text('Spustit hru'))
        else
          const Center(child: Text('Čekáme na hostitele…')),
      ]));

  Future<void> perk(String k, int dur, int cd) async {
    final left = ((mep['cd_$k'] ?? 0) as int) - nowMs;
    if (left > 0) return snack('Nabíjí se: ${left ~/ 1000} s');
    final until = nowMs + dur * 1000;
    if (k == 'freeze') {
      final b = db.batch();
      for (final p in ps) {
        if (role(p) == 'hunter') b.update(game.collection('players').doc(p['id']), {'frozenUntil': until});
      }
      b.update(me, {'cd_$k': nowMs + cd * 1000});
      await b.commit();
    } else {
      await me.update({k == 'hide' ? 'hideUntil' : 'radarUntil': until, 'cd_$k': nowMs + cd * 1000});
    }
    snack('Perk aktivní na $dur s');
  }

  Widget pk(String k, IconData i, String label, int dur, int cd) {
    final left = (((mep['cd_$k'] ?? 0) as int) - nowMs) ~/ 1000;
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: left > 0 ? null : () => perk(k, dur, cd),
        icon: Icon(i),
        label: Text(left > 0 ? '$label · ${left}s' : label),
      ),
    );
  }

  Widget running() {
    final perks = g['perks'] != false;
    final fz = ((mep['frozenUntil'] ?? 0) as int) - nowMs;
    if (myRole == 'hunter') {
      return panel(Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (perks) Row(children: [pk('radar', Icons.radar, 'Radar (15 s)', 15, 180)]),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), backgroundColor: zombie ? Colors.green : Colors.red, foregroundColor: Colors.white),
            onPressed: inHeadStart || fz > 0 ? null : catchNear,
            icon: const Icon(Icons.back_hand),
            label: Text(fz > 0 ? 'Zmrazen ${fz ~/ 1000 + 1} s' : inHeadStart ? 'Počkej na konec náskoku' : 'CHYTIT', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ]),
      ));
    }
    final next = ((g['interval'] as int) - (nowMs - lastPub) ~/ 1000).clamp(0, 99999);
    final hid = ((mep['hideUntil'] ?? 0) as int) - nowMs;
    return panel(Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(myRole == 'caught' ? 'Jsi chycený. Sleduješ hru.' : hid > 0 ? 'Jsi neviditelný ještě ${hid ~/ 1000} s' : 'Utíkej! Lovci tě uvidí za ${fmt(next)}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        if (perks && myRole == 'runner') ...[
          const SizedBox(height: 10),
          Row(children: [pk('hide', Icons.visibility_off, 'Zmizení (60 s)', 60, 180), const SizedBox(width: 8), pk('freeze', Icons.ac_unit, 'Zmrazení (20 s)', 20, 240)]),
        ],
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: game.snapshots(),
      builder: (_, gs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: game.collection('players').snapshots(),
        builder: (_, qs) {
          if (!gs.hasData || !qs.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          g = gs.data!.data() ?? {};
          ps = qs.data!.docs.map((x) => {...x.data(), 'id': x.id}).toList();
          final center = LatLng(d(g['lat']), d(g['lng']));
          final out = pos != null && !inside(pos!.latitude, pos!.longitude);
          final host = g['host'] == uid, s = status;
          return Scaffold(
            body: Column(children: [
              Expanded(
                child: Stack(children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 16,
                      onTap: (tp, ll) {
                        if (editing && host && s == 'lobby') game.update({'poly': FieldValue.arrayUnion([{'lat': ll.latitude, 'lng': ll.longitude}])});
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'cz.manhunt.manhunt',
                        tileBuilder: (c, tilesWidget, t) => !darkMap ? tilesWidget : ColorFiltered(
                          colorFilter: const ColorFilter.matrix(<double>[
                            -0.2126, -0.7152, -0.0722, 0, 255,
                            -0.2126, -0.7152, -0.0722, 0, 255,
                            -0.2126, -0.7152, -0.0722, 0, 255,
                            0, 0, 0, 1, 0,
                          ]),
                          child: tilesWidget,
                        ),
                      ),
                      if (zonePoly.isNotEmpty)
                        PolygonLayer(polygons: [Polygon(points: zonePoly, color: zcol.withAlpha(35), borderColor: zcol, borderStrokeWidth: 3)])
                      else
                        CircleLayer(circles: [CircleMarker(point: center, radius: d(g['radius'] ?? 500) * zf, useRadiusInMeter: true, color: zcol.withAlpha(35), borderColor: zcol, borderStrokeWidth: 3)]),
                      PolylineLayer(polylines: [Polyline(points: List.of(trail), color: Colors.amber, strokeWidth: 3)]),
                      if (editing) MarkerLayer(markers: [for (final p in poly) Marker(point: p, width: 16, height: 16, child: Icon(Icons.circle, size: 14, color: zcol))]),
                      MarkerLayer(markers: markers()),
                    ],
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(children: [
                              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                              Text(head(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              if (s == 'running') IconButton(icon: const Icon(Icons.place), tooltip: 'Ping týmu', onPressed: pingTeam),
                              IconButton(icon: const Icon(Icons.layers), onPressed: () => setState(() => darkMap = !darkMap)),
                              Chip(avatar: CircleAvatar(backgroundColor: col(myRole), radius: 7), label: Text(roleLabel(myRole))),
                              const SizedBox(width: 6),
                            ]),
                          ),
                        ),
                        if (pos != null && s != 'lobby')
                          Card(child: Padding(padding: const EdgeInsets.all(6), child: Text('${(pos!.speed * 3.6).toStringAsFixed(1)} km/h · ${dir(pos!.heading)} · ±${pos!.accuracy.round()} m · 🔋$battery %${zf < 1 ? ' · zóna ${(zf * 100).round()} %' : ''}', style: const TextStyle(fontSize: 12)))),
                        if (out && s == 'running')
                          Card(color: Colors.red, child: Container(width: double.infinity, padding: const EdgeInsets.all(8), child: const Text('Jsi mimo herní zónu!', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)))),
                      ]),
                    ),
                  ),
                ]),
              ),
              if (s == 'lobby') lobby(host),
              if (s == 'running') running(),
              if (s == 'ended') panel(Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Zpět do menu')))),
            ]),
          );
        },
      ),
    );
  }
}
