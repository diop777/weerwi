import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';

// ─────────────────────────── Palette cosmique ───────────────────────────
const kGold = Color(0xFFFFD872);
const kGoldDeep = Color(0xFFFFB347);
const kCyan = Color(0xFF7DF9FF);
const kViolet = Color(0xFFA98BFF);
const kGreen = Color(0xFF6CFFB0);
const kOrange = Color(0xFFFFA45C);
const kSpace = Color(0xFF02030A);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase sera configuré plus tard (google-services.json)
  }
  runApp(const WeerWiApp());
}

class WeerWiApp extends StatelessWidget {
  const WeerWiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeerWi • Votre astronaute lunaire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: kSpace,
        colorScheme: ColorScheme.fromSeed(seedColor: kGold, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────── Villes ───────────────────────────
class WestAfricanCity {
  final String name;
  final String country;
  final String flag;
  final double lat;
  final double lon;
  const WestAfricanCity(this.name, this.country, this.flag, this.lat, this.lon);
}

const List<WestAfricanCity> kCities = [
  WestAfricanCity('Dakar', 'Sénégal', '🇸🇳', 14.6937, -17.4441),
  WestAfricanCity('Touba', 'Sénégal', '🇸🇳', 14.8647, -15.8756),
  WestAfricanCity('Bamako', 'Mali', '🇲🇱', 12.6392, -8.0029),
  WestAfricanCity('Abidjan', "Côte d'Ivoire", '🇨🇮', 5.3600, -4.0083),
  WestAfricanCity('Ouagadougou', 'Burkina Faso', '🇧🇫', 12.3714, -1.5197),
  WestAfricanCity('Niamey', 'Niger', '🇳🇪', 13.5116, 2.1254),
  WestAfricanCity('Conakry', 'Guinée', '🇬🇳', 9.6412, -13.5784),
  WestAfricanCity('Nouakchott', 'Mauritanie', '🇲🇷', 18.0735, -15.9582),
  WestAfricanCity('Banjul', 'Gambie', '🇬🇲', 13.4549, -16.5790),
  WestAfricanCity('Lomé', 'Togo', '🇹🇬', 6.1375, 1.2125),
  WestAfricanCity('Cotonou', 'Bénin', '🇧🇯', 6.3654, 2.4183),
];

// ─────────────────────────── Écran principal ───────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  WestAfricanCity _city = kCities[0];
  late final TextEditingController _latCtrl;
  late final TextEditingController _lonCtrl;
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  late final AnimationController _float;
  late final AnimationController _orbit;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _latCtrl = TextEditingController(text: _city.lat.toString());
    _lonCtrl = TextEditingController(text: _city.lon.toString());
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
    _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMoon());
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _float.dispose();
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Uri get _apiUri =>
      kIsWeb ? Uri.base.resolve('/moon') : Uri.parse('http://localhost:8000/moon');

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _frDate(DateTime d) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _selectCity(WestAfricanCity c) {
    setState(() {
      _city = c;
      _latCtrl.text = c.lat.toString();
      _lonCtrl.text = c.lon.toString();
    });
    _fetchMoon();
  }

  Future<void> _fetchMoon() async {
    final lat = double.tryParse(_latCtrl.text.replaceAll(',', '.'));
    final lon = double.tryParse(_lonCtrl.text.replaceAll(',', '.'));
    if (lat == null || lon == null) {
      setState(() => _error = 'Coordonnées GPS invalides.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            _apiUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'latitude': lat, 'longitude': lon, 'date': _isoDate(_date)}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        setState(() => _result = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
      } else {
        setState(() => _error = 'Le serveur a répondu ${res.statusCode}.');
      }
    } catch (e) {
      setState(() => _error = 'Contact perdu avec la station (serveur injoignable).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────── BUILD ───────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: CosmicBackground()),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 200,
            child: IgnorePointer(child: CustomPaint(painter: HorizonPainter())),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 210),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      const SizedBox(height: 8),
                      _hero(),
                      const SizedBox(height: 18),
                      _sectionTitle(Icons.public_rounded, "POINT D'OBSERVATION • AFRIQUE DE L'OUEST"),
                      const SizedBox(height: 10),
                      _cityChips(),
                      const SizedBox(height: 18),
                      _missionControl(),
                      if (_error != null) ...[const SizedBox(height: 16), _errorCard()],
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                            child: child,
                          ),
                        ),
                        child: _result == null
                            ? const SizedBox.shrink()
                            : _results(_result!),
                      ),
                      const SizedBox(height: 28),
                      _footer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── En-tête ───────────────────────────
  Widget _header() {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFFFFF4C2), kGoldDeep]),
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.55), blurRadius: 22, spreadRadius: 1)],
          ),
          child: const Icon(Icons.nightlight_round, color: Color(0xFF14102A), size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [kGold, Colors.white, kCyan],
                ).createShader(b),
                child: const Text(
                  'WeerWi',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 3,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Votre astronaute personnel • Observatoire du Hilal',
                style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 0.4),
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: kGreen.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGreen,
                    boxShadow: [
                      BoxShadow(color: kGreen.withOpacity(0.3 + 0.6 * _pulse.value), blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'EN ORBITE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.8, color: kGreen),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── Lune héroïque ───────────────────────────
  Widget _hero() {
    final illum = (_result?['illumination'] as num?)?.toDouble() ?? 50.0;
    final phase = (_result?['phase'] as String?) ?? 'Scan du ciel…';
    final visible = (_result?['visible'] as bool?) ?? false;
    final lat = double.tryParse(_latCtrl.text) ?? _city.lat;
    final lon = double.tryParse(_lonCtrl.text) ?? _city.lon;
    final coords =
        '${lat.abs().toStringAsFixed(2)}°${lat >= 0 ? 'N' : 'S'}  ·  ${lon.abs().toStringAsFixed(2)}°${lon >= 0 ? 'E' : 'O'}';

    return Column(
      children: [
        SizedBox(
          height: 320,
          child: AnimatedBuilder(
            animation: Listenable.merge([_float, _orbit, _pulse]),
            builder: (context, _) {
              final dy = math.sin(_float.value * 2 * math.pi) * 9;
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(size: const Size(380, 320), painter: OrbitPainter(_orbit.value)),
                  Transform.translate(
                    offset: Offset(0, dy),
                    child: CustomPaint(
                      size: const Size(220, 220),
                      painter: MoonPainter(illumination: illum, glow: 0.65 + 0.35 * _pulse.value),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Text(
          phase,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.5,
            shadows: [Shadow(color: kGold, blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_city.flag}  ${_city.name}, ${_city.country}   •   ${_frDate(_date)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '📡  $coords',
          style: TextStyle(color: kCyan.withOpacity(0.75), fontSize: 11, letterSpacing: 1.5),
        ),
        const SizedBox(height: 14),
        if (_loading)
          SizedBox(
            width: 220,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    minHeight: 3,
                    color: kGold,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Calculs astronomiques en cours…',
                    style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
              ],
            ),
          )
        else if (_result != null)
          _visibilityBadge(visible),
      ],
    );
  }

  Widget _visibilityBadge(bool visible) {
    final color = visible ? kGreen : kOrange;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: LinearGradient(colors: [color.withOpacity(0.22), color.withOpacity(0.06)]),
          border: Border.all(color: color.withOpacity(0.8), width: 1.3),
          boxShadow: [BoxShadow(color: color.withOpacity(0.15 + 0.2 * _pulse.value), blurRadius: 26)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(visible ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: color, size: 18),
            const SizedBox(width: 10),
            Text(
              visible ? 'VISIBLE À L’ŒIL NU' : 'NON VISIBLE À L’ŒIL NU',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Villes ───────────────────────────
  Widget _cityChips() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kCities.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = kCities[i];
          final sel = c.name == _city.name;
          return InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => _selectCity(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: sel
                    ? const LinearGradient(colors: [kGoldDeep, kGold])
                    : LinearGradient(colors: [
                        const Color(0xFF1A1F45).withOpacity(0.75),
                        const Color(0xFF0C0F2A).withOpacity(0.6),
                      ]),
                border: Border.all(color: sel ? kGold : Colors.white.withOpacity(0.14)),
                boxShadow: sel ? [BoxShadow(color: kGold.withOpacity(0.45), blurRadius: 16)] : null,
              ),
              child: Row(
                children: [
                  Text(c.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    c.name,
                    style: TextStyle(
                      color: sel ? const Color(0xFF16112B) : Colors.white,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────── Centre de contrôle ───────────────────────────
  Widget _missionControl() {
    return _glass(
      accent: kGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(Icons.satellite_alt_rounded, 'CENTRE DE CONTRÔLE DE MISSION'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.04),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_rounded, color: kGold, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("DATE D'OBSERVATION",
                                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
                              const SizedBox(height: 2),
                              Text(_frDate(_date),
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        ),
                        const Icon(Icons.expand_more_rounded, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() => _date = DateTime.now());
                  _fetchMoon();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: kCyan.withOpacity(0.08),
                    border: Border.all(color: kCyan.withOpacity(0.35)),
                  ),
                  child: const Text("Aujourd'hui",
                      style: TextStyle(color: kCyan, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              iconColor: Colors.white54,
              collapsedIconColor: Colors.white38,
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text('Coordonnées GPS personnalisées',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              children: [
                Row(
                  children: [
                    Expanded(child: _coordField(_latCtrl, 'Latitude')),
                    const SizedBox(width: 10),
                    Expanded(child: _coordField(_lonCtrl, 'Longitude')),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          _launchButton(),
        ],
      ),
    );
  }

  Widget _coordField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kGold),
        ),
      ),
    );
  }

  Widget _launchButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _loading ? null : _fetchMoon,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(colors: [kGoldDeep, kGold, Color(0xFFFFF0B3)]),
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 6))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF16112B)),
                    )
                  : const Icon(Icons.rocket_launch_rounded, color: Color(0xFF16112B)),
              const SizedBox(width: 12),
              Text(
                _loading ? 'EXPLORATION DU CIEL…' : 'LANCER L’ANALYSE DU CIEL',
                style: const TextStyle(
                  color: Color(0xFF16112B),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kGold,
            onPrimary: Color(0xFF16112B),
            surface: Color(0xFF12153A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _fetchMoon();
    }
  }

  // ─────────────────────────── Résultats ───────────────────────────
  Widget _results(Map<String, dynamic> d) {
    final visible = (d['visible'] as bool?) ?? false;
    final illum = (d['illumination'] as num?)?.toDouble() ?? 0;
    final elong = (d['elongation_deg'] as num?)?.toDouble() ?? 0;
    final alt = (d['altitude_deg'] as num?)?.toDouble() ?? 0;
    final age = (d['age_days'] as num?)?.toDouble() ?? 0;
    final cloud = (d['cloud_cover'] as num?)?.toDouble();
    final tip = (d['observation_tip'] as String?) ?? '';
    final ramadan = (d['ramadan_status'] as String?) ?? '';
    final accent = visible ? kGreen : kOrange;

    return Column(
      key: ValueKey(jsonEncode(d)),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        _glass(
          accent: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.person_pin_circle_rounded, 'RAPPORT DE VOTRE ASTRONAUTE', color: accent),
              const SizedBox(height: 12),
              Text(tip, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _glass(
          accent: kViolet,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kViolet.withOpacity(0.15),
                  border: Border.all(color: kViolet.withOpacity(0.5)),
                ),
                child: const Icon(Icons.mosque_rounded, color: kGold, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(null, 'MOIS LUNAIRE • RAMADAN', color: kViolet),
                    const SizedBox(height: 8),
                    Text(ramadan,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle(Icons.speed_rounded, 'INSTRUMENTS DE BORD • NASA JPL DE421'),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            _gauge('ILLUMINATION', illum.toStringAsFixed(1), '%', illum / 100, kGold, Icons.light_mode_rounded),
            _gauge('ÉLONGATION', elong.toStringAsFixed(1), 'degrés', elong / 180, kCyan, Icons.architecture_rounded),
            _gauge('HAUTEUR', alt.toStringAsFixed(1), 'degrés', (alt + 90) / 180, kGreen, Icons.height_rounded),
            _gauge('ÂGE LUNAIRE', age.toStringAsFixed(1), 'jours', age / 29.53, kViolet, Icons.hourglass_bottom_rounded),
            _gauge('NUAGES', cloud == null ? '—' : cloud.toStringAsFixed(0), '%', (cloud ?? 0) / 100,
                const Color(0xFF8EC5FF), Icons.cloud_rounded),
          ],
        ),
      ],
    );
  }

  Widget _gauge(String label, String value, String unit, double fraction, Color color, IconData icon) {
    return SizedBox(
      width: 160,
      child: _glass(
        accent: color,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            SizedBox(
              width: 116,
              height: 116,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0).toDouble()),
                    duration: const Duration(milliseconds: 1400),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) =>
                        CustomPaint(size: const Size(116, 116), painter: GaugePainter(v, color)),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 16),
                      const SizedBox(height: 2),
                      Text(value,
                          style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                      Text(unit, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: color.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return _glass(
      accent: Colors.redAccent,
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering_error_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _footer() {
    return Column(
      children: [
        Text('✦  ✦  ✦', style: TextStyle(color: kGold.withOpacity(0.5), letterSpacing: 6)),
        const SizedBox(height: 8),
        const Text(
          'WeerWi — la science des astres au service de toute la communauté.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 3),
        const Text(
          'Éphémérides NASA JPL DE421 · Critères Danjon / Yallop · Météo Open-Meteo',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      ],
    );
  }

  // ─────────────────────────── Helpers UI ───────────────────────────
  Widget _sectionTitle(IconData? icon, String text, {Color color = kGold}) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, color: color, size: 16), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
        ),
      ],
    );
  }

  Widget _glass({
    required Widget child,
    Color accent = Colors.white,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF181D48).withOpacity(0.72),
            const Color(0xFF080A22).withOpacity(0.62),
          ],
        ),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.08), blurRadius: 30, spreadRadius: 1)],
      ),
      child: child,
    );
  }
}

// ═══════════════════════════ CIEL ANIMÉ ═══════════════════════════
class _Star {
  final double x, y, r, phase, speed, depth;
  final bool band;
  final Color color;
  const _Star(this.x, this.y, this.r, this.phase, this.speed, this.depth, this.band, this.color);
}

class CosmicBackground extends StatefulWidget {
  const CosmicBackground({super.key});

  @override
  State<CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<CosmicBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final Stopwatch _clock = Stopwatch()..start();
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    final rnd = math.Random(7);
    const palette = [
      Colors.white,
      Color(0xFFCFE3FF),
      Color(0xFFFFF1C9),
      Color(0xFFBFD4FF),
      Color(0xFFFFD6E8),
    ];
    _stars = [
      // Étoiles dispersées
      for (int i = 0; i < 260; i++)
        () {
          final depth = rnd.nextDouble();
          return _Star(rnd.nextDouble(), rnd.nextDouble(), 0.4 + depth * depth * 1.9,
              rnd.nextDouble() * math.pi * 2, 0.5 + rnd.nextDouble() * 2.5, depth, false,
              palette[rnd.nextInt(palette.length)]);
        }(),
      // Voie lactée
      for (int i = 0; i < 180; i++)
        () {
          final g = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble()) / 3 - 0.5; // ~gaussien
          return _Star(rnd.nextDouble(), g, 0.3 + rnd.nextDouble() * 0.8, rnd.nextDouble() * math.pi * 2,
              0.8 + rnd.nextDouble() * 2, rnd.nextDouble() * 0.6, true, palette[rnd.nextInt(palette.length)]);
        }(),
    ];
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: SkyPainter(_clock.elapsedMilliseconds / 1000.0, _stars),
        ),
      ),
    );
  }
}

class SkyPainter extends CustomPainter {
  final double t;
  final List<_Star> stars;
  SkyPainter(this.t, this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // Dégradé du ciel nocturne
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF01020A), Color(0xFF060A26), Color(0xFF120D38), Color(0xFF2B1542)],
          stops: [0, 0.45, 0.8, 1],
        ).createShader(rect),
    );

    // Nébuleuses
    void nebula(double cx, double cy, double rad, Color c, double op) {
      final center = Offset(cx, cy);
      canvas.drawCircle(
        center,
        rad,
        Paint()
          ..shader = RadialGradient(colors: [c.withOpacity(op), c.withOpacity(0)])
              .createShader(Rect.fromCircle(center: center, radius: rad)),
      );
    }

    final m = math.max(w, h);
    nebula(w * 0.12 + math.sin(t * 0.05) * 30, h * 0.22, m * 0.42, const Color(0xFF6B3FD9), 0.22);
    nebula(w * 0.88, h * 0.12 + math.cos(t * 0.04) * 30, m * 0.32, const Color(0xFF1FA2C4), 0.16);
    nebula(w * 0.72 + math.cos(t * 0.03) * 25, h * 0.62, m * 0.45, const Color(0xFFB0367A), 0.11);
    nebula(w * 0.25, h * 0.88, m * 0.38, const Color(0xFF2D5BFF), 0.10);

    // Voie lactée (bande diffuse)
    const angle = -0.42;
    canvas.save();
    canvas.translate(w / 2, h * 0.42);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: m * 1.9, height: h * 0.16),
      Paint()
        ..color = const Color(0xFFDCD6FF).withOpacity(0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: m * 1.5, height: h * 0.06),
      Paint()
        ..color = Colors.white.withOpacity(0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.restore();

    // Étoiles scintillantes
    final tanA = math.tan(angle);
    for (final s in stars) {
      double px, py;
      if (s.band) {
        px = (s.x * 1.4 - 0.2) * w;
        py = h * 0.42 + (px - w / 2) * tanA + s.y * h * 0.22;
      } else {
        px = ((s.x + t * 0.0012 * (0.2 + s.depth)) % 1.0) * w;
        py = s.y * h;
      }
      final tw = 0.55 + 0.45 * math.sin(t * s.speed + s.phase);
      final op = math.min(1.0, math.max(0.0, (0.25 + 0.75 * tw) * (0.35 + 0.65 * s.depth)));
      final pos = Offset(px, py);
      canvas.drawCircle(pos, s.r, Paint()..color = s.color.withOpacity(op));
      if (s.r > 1.55) {
        canvas.drawCircle(
          pos,
          s.r * 3.2,
          Paint()
            ..color = s.color.withOpacity(op * 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        final l = Paint()
          ..color = s.color.withOpacity(op * 0.55)
          ..strokeWidth = 0.6;
        final len = s.r * 4.5 * tw;
        canvas.drawLine(Offset(px - len, py), Offset(px + len, py), l);
        canvas.drawLine(Offset(px, py - len), Offset(px, py + len), l);
      }
    }

    // Étoiles filantes
    _shootingStar(canvas, w, h, 5.5, 0);
    _shootingStar(canvas, w, h, 9.0, 1000);
  }

  void _shootingStar(Canvas canvas, double w, double h, double cycle, int seedOffset) {
    const dur = 1.3;
    final k = (t / cycle).floor();
    final local = t - k * cycle;
    if (local > dur) return;
    final rnd = math.Random(k + seedOffset);
    final start = Offset(w * (0.3 + rnd.nextDouble() * 0.7), h * rnd.nextDouble() * 0.45);
    final ang = math.pi * (0.72 + rnd.nextDouble() * 0.12);
    final dir = Offset(math.cos(ang), math.sin(ang));
    final prog = local / dur;
    final head = start + dir * (prog * w * 0.4);
    final fade = math.sin(prog * math.pi);
    final tail = head - dir * (150 * fade + 10);
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..shader = ui.Gradient.linear(tail, head, [Colors.white.withOpacity(0), Colors.white.withOpacity(0.9 * fade)])
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      head,
      2.4,
      Paint()
        ..color = Colors.white.withOpacity(fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant SkyPainter old) => true;
}

// ═══════════════════════════ LUNE ═══════════════════════════
class MoonPainter extends CustomPainter {
  final double illumination;
  final double glow;
  MoonPainter({required this.illumination, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.74;
    final k = (illumination / 100).clamp(0.0, 1.0).toDouble();
    final lit = 0.35 + 0.65 * k;

    // Halo
    final radii = [r * 1.95, r * 1.45, r * 1.15];
    final ops = [0.10, 0.17, 0.25];
    final cols = [kGold, kGold, Colors.white];
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        c,
        radii[i],
        Paint()
          ..shader = RadialGradient(colors: [
            cols[i].withOpacity(ops[i] * glow * lit),
            cols[i].withOpacity(0),
          ]).createShader(Rect.fromCircle(center: c, radius: radii[i])),
      );
    }

    // Face sombre (lumière cendrée)
    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFF2B3156), Color(0xFF0C0F25)],
        ).createShader(disc),
    );

    // Partie éclairée (terminateur elliptique)
    if (k > 0.005) {
      final path = Path()..moveTo(c.dx, c.dy - r);
      path.arcToPoint(Offset(c.dx, c.dy + r), radius: Radius.circular(r), clockwise: true);
      final ex = math.max(0.5, r * (1 - 2 * k).abs());
      path.arcToPoint(Offset(c.dx, c.dy - r), radius: Radius.elliptical(ex, r), clockwise: k > 0.5);
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0.35, -0.25),
            radius: 0.95,
            colors: [Color(0xFFFFFCEE), Color(0xFFF4E6B8), Color(0xFFC9B784)],
            stops: [0, 0.6, 1],
          ).createShader(disc),
      );

      // Cratères
      canvas.save();
      canvas.clipPath(path);
      const craters = [
        [0.25, -0.30, 0.16], [-0.20, 0.15, 0.12], [0.35, 0.35, 0.10], [-0.05, -0.48, 0.08],
        [0.08, 0.08, 0.07], [-0.42, -0.10, 0.09], [0.52, -0.05, 0.06], [0.15, 0.55, 0.07],
      ];
      for (final cr in craters) {
        final cc = c + Offset(cr[0] * r, cr[1] * r);
        canvas.drawCircle(cc, cr[2] * r, Paint()..color = const Color(0xFFAE9C6E).withOpacity(0.35));
        canvas.drawCircle(
          cc,
          cr[2] * r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withOpacity(0.18),
        );
      }
      canvas.restore();
    }

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = kGold.withOpacity(0.25),
    );
  }

  @override
  bool shouldRepaint(covariant MoonPainter old) => true;
}

// ═══════════════════════════ ORBITES ═══════════════════════════
class OrbitPainter extends CustomPainter {
  final double progress;
  OrbitPainter(this.progress);

  void _orbit(Canvas canvas, Size size, double rot, double a, double b, Color color, double phase) {
    final c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: a * 2, height: b * 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withOpacity(0.2),
    );
    final th = (progress + phase) * 2 * math.pi;
    final p = Offset(a * math.cos(th), b * math.sin(th));
    canvas.drawCircle(
      p,
      8,
      Paint()
        ..color = color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(p, 2.6, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _orbit(canvas, size, -0.28, size.width * 0.47, size.height * 0.15, kCyan, 0);
    _orbit(canvas, size, 0.35, size.width * 0.40, size.height * 0.11, kViolet, 0.5);
  }

  @override
  bool shouldRepaint(covariant OrbitPainter old) => old.progress != progress;
}

// ═══════════════════════════ JAUGES ═══════════════════════════
class GaugePainter extends CustomPainter {
  final double fraction;
  final Color color;
  GaugePainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.07),
    );

    for (int i = 0; i <= 10; i++) {
      final a = start + sweep * i / 10;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * (r - 11),
        c + dir * (r - 15),
        Paint()
          ..color = Colors.white.withOpacity(0.18)
          ..strokeWidth = 1,
      );
    }

    final f = fraction.clamp(0.0, 1.0).toDouble();
    if (f <= 0) return;
    canvas.drawArc(
      rect,
      start,
      sweep * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..color = color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      rect,
      start,
      sweep * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweep,
          colors: [color.withOpacity(0.45), color],
          transform: const GradientRotation(start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) => old.fraction != fraction || old.color != color;
}

// ═══════════════════════════ HORIZON (dunes + mosquée) ═══════════════════════════
class HorizonPainter extends CustomPainter {
  const HorizonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // Lueur du crépuscule
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFFFF7A3D).withOpacity(0.08),
            const Color(0xFFFFB347).withOpacity(0.20),
          ],
        ).createShader(rect),
    );

    // Dunes arrière
    final back = Path()..moveTo(0, h * 0.62);
    for (double x = 0; x <= w; x += w / 60) {
      back.lineTo(x, h * 0.62 + math.sin(x / w * math.pi * 3) * 12 + math.sin(x / w * math.pi * 8) * 5);
    }
    back
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFF0D0B24));

    // Mosquée
    final m = Paint()..color = const Color(0xFF05040F);
    final bx = w * 0.78;
    final base = h * 0.78;
    canvas.drawRect(Rect.fromLTWH(bx - 58, base - 38, 116, 60), m);
    canvas.drawArc(Rect.fromCircle(center: Offset(bx, base - 38), radius: 34), math.pi, math.pi, true, m);
    canvas.drawArc(Rect.fromCircle(center: Offset(bx - 44, base - 38), radius: 13), math.pi, math.pi, true, m);
    canvas.drawArc(Rect.fromCircle(center: Offset(bx + 44, base - 38), radius: 13), math.pi, math.pi, true, m);
    canvas.drawRect(Rect.fromLTWH(bx - 1.5, base - 88, 3, 18), m);
    for (final mx in [bx - 82, bx + 82]) {
      canvas.drawRect(Rect.fromLTWH(mx - 6, base - 100, 12, 122), m);
      canvas.drawRect(Rect.fromLTWH(mx - 9, base - 72, 18, 5), m);
      final cone = Path()
        ..moveTo(mx - 7, base - 100)
        ..lineTo(mx, base - 124)
        ..lineTo(mx + 7, base - 100)
        ..close();
      canvas.drawPath(cone, m);
    }
    // Petit croissant doré au sommet du dôme
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: Offset(bx, base - 95), radius: 6)),
      Path()..addOval(Rect.fromCircle(center: Offset(bx + 3, base - 97), radius: 5.2)),
    );
    canvas.drawPath(
      crescent,
      Paint()
        ..color = kGold
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
    );

    // Dunes avant
    final front = Path()..moveTo(0, h * 0.82);
    for (double x = 0; x <= w; x += w / 60) {
      front.lineTo(x, h * 0.82 + math.sin(x / w * math.pi * 2 + 1) * 10 + math.sin(x / w * math.pi * 6) * 4);
    }
    front
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF030309));
  }

  @override
  bool shouldRepaint(covariant HorizonPainter old) => false;
}
