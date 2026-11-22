import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'cosmic.dart';
import 'data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  City _city = kCities[0];
  int _tab = 0; // 0: Ce soir, 1: Calendrier, 2: Hilal & Ramadan

  // État Onglet 0 (Ce soir)
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _eveningData;
  bool _loadingEvening = false;
  String? _errorEvening;

  // État Onglet 1 (Calendrier mensuel)
  int _calYear = DateTime.now().year;
  int _calMonth = DateTime.now().month;
  Map<String, dynamic>? _monthData;
  bool _loadingMonth = false;
  String? _errorMonth;
  Map<String, dynamic>? _selectedDayData;

  // État Onglet 2 (Hilal & Ramadan)
  int _targetHijriMonth = 9; // 9 = Ramadan, 10 = Chawwal, 12 = Dhou al-Hijja, 0 = Prochain mois
  Map<String, dynamic>? _hilalData;
  bool _loadingHilal = false;
  String? _errorHilal;

  late final AnimationController _float;
  late final AnimationController _orbit;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
    _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEvening();
      _loadMonth();
      _loadHilal();
    });
  }

  @override
  void dispose() {
    _float.dispose();
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _selectCity(City c) {
    setState(() => _city = c);
    _loadEvening();
    _loadMonth();
    _loadHilal();
  }

  Future<void> _loadEvening() async {
    setState(() {
      _loadingEvening = true;
      _errorEvening = null;
    });
    try {
      final res = await Api.evening(_city, _date);
      if (mounted) setState(() => _eveningData = res);
    } catch (e) {
      if (mounted) setState(() => _errorEvening = 'Impossible de charger les données de la soirée.');
    } finally {
      if (mounted) setState(() => _loadingEvening = false);
    }
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loadingMonth = true;
      _errorMonth = null;
    });
    try {
      final res = await Api.month(_city, _calYear, _calMonth);
      if (mounted) {
        setState(() {
          _monthData = res;
          final days = (res['days'] as List?) ?? [];
          if (days.isNotEmpty) {
            final todayIso = isoDate(_date);
            _selectedDayData = days.cast<Map<String, dynamic>>().firstWhere(
                  (d) => d['date'] == todayIso,
                  orElse: () => days.first as Map<String, dynamic>,
                );
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMonth = 'Impossible de charger le calendrier mensuel.');
    } finally {
      if (mounted) setState(() => _loadingMonth = false);
    }
  }

  Future<void> _loadHilal() async {
    setState(() {
      _loadingHilal = true;
      _errorHilal = null;
    });
    try {
      final res = _targetHijriMonth == 0
          ? await Api.hilal(_city, DateTime.now())
          : await Api.hijriMonth(_city, _targetHijriMonth);
      if (mounted) setState(() => _hilalData = res);
    } catch (e) {
      if (mounted) setState(() => _errorHilal = 'Impossible de charger les prévisions du Hilal.');
    } finally {
      if (mounted) setState(() => _loadingHilal = false);
    }
  }

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
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildCitySelector(),
                      const SizedBox(height: 16),
                      _buildNavigationTabs(),
                      const SizedBox(height: 20),
                      if (_tab == 0) _buildEveningTab(),
                      if (_tab == 1) _buildCalendarTab(),
                      if (_tab == 2) _buildHilalTab(),
                      const SizedBox(height: 32),
                      _buildFooter(),
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

  // ─────────────────────────── En-tête & Navigation ───────────────────────────
  Widget _buildHeader() {
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
                shaderCallback: (b) => const LinearGradient(colors: [kGold, Colors.white, kCyan]).createShader(b),
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
                'Votre astronaute personnel • Observatoire scientifique du Hilal',
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
                  'NASA DE421 • EN ORBITE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.4, color: kGreen),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle("POINT D'OBSERVATION • AFRIQUE DE L'OUEST", icon: Icons.public_rounded),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
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
                  duration: const Duration(milliseconds: 220),
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
                          color: sel ? kInk : Colors.white,
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
        ),
      ],
    );
  }

  Widget _buildNavigationTabs() {
    final items = [
      (0, Icons.nightlight_round, 'Ce soir • Observatoire'),
      (1, Icons.calendar_month_rounded, 'Calendrier Mensuel'),
      (2, Icons.mosque_rounded, 'Hilal & Ramadan'),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF0E122E).withOpacity(0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: items.map((item) {
          final sel = _tab == item.$1;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _tab = item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                  boxShadow: sel ? [BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 14)] : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$2, size: 18, color: sel ? kInk : Colors.white70),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.$3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sel ? kInk : Colors.white,
                          fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════ ONGLET 0 : CE SOIR ═══════════════════════════
  Widget _buildEveningTab() {
    final d = _eveningData;
    final illum = toD(d?['illumination']) ?? 50.0;
    final waxing = (d?['waxing'] as bool?) ?? true;
    final phase = (d?['phase'] as String?) ?? 'Scan du ciel…';
    final badgeText = (d?['badge_text'] as String?) ?? 'ANALYSE EN COURS';
    final badgeLevel = (d?['badge_level'] as String?) ?? 'maybe';
    final badgeCol = levelColor(badgeLevel);

    final coords =
        '${_city.lat.abs().toStringAsFixed(2)}°${_city.lat >= 0 ? 'N' : 'S'}  ·  ${_city.lon.abs().toStringAsFixed(2)}°${_city.lon >= 0 ? 'E' : 'O'}  ·  UTC${_city.tz >= 0 ? '+${_city.tz.toInt()}' : '${_city.tz.toInt()}'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lune héroïque en orbite
        Column(
          children: [
            SizedBox(
              height: 300,
              child: AnimatedBuilder(
                animation: Listenable.merge([_float, _orbit, _pulse]),
                builder: (context, _) {
                  final dy = math.sin(_float.value * 2 * math.pi) * 8;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(size: const Size(370, 300), painter: OrbitPainter(_orbit.value)),
                      Transform.translate(
                        offset: Offset(0, dy),
                        child: CustomPaint(
                          size: const Size(210, 210),
                          painter: MoonPainter(
                            illumination: illum,
                            waxing: waxing,
                            glow: 0.65 + 0.35 * _pulse.value,
                          ),
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
              '${_city.flag}  ${_city.name}, ${_city.country}   •   ${frDate(_date, weekday: true)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text('📡  $coords', style: TextStyle(color: kCyan.withOpacity(0.75), fontSize: 11, letterSpacing: 1.4)),
            const SizedBox(height: 14),
            if (_loadingEvening)
              const LoadingBlock('Calcul topocentrique au coucher du Soleil…')
            else if (d != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: LinearGradient(colors: [badgeCol.withOpacity(0.24), badgeCol.withOpacity(0.06)]),
                  border: Border.all(color: badgeCol.withOpacity(0.85), width: 1.4),
                  boxShadow: [BoxShadow(color: badgeCol.withOpacity(0.22), blurRadius: 24)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      badgeLevel == 'good'
                          ? Icons.visibility_rounded
                          : badgeLevel == 'bad'
                              ? Icons.visibility_off_rounded
                              : Icons.travel_explore_rounded,
                      color: badgeCol,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        badgeText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: badgeCol,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 18),

        // Sélecteur de date rapide
        _buildDateControlBar(),

        if (_errorEvening != null) ...[
          const SizedBox(height: 16),
          ErrorBlock(_errorEvening!, onRetry: _loadEvening),
        ],

        if (d != null && !_loadingEvening) ...[
          const SizedBox(height: 18),
          _buildSunMoonTimesBar(d),
          const SizedBox(height: 16),
          _buildAstronautReportCard(d),
          if (d['crescent'] != null) ...[
            const SizedBox(height: 16),
            _buildScientificCriteriaCard(d['crescent'] as Map<String, dynamic>),
          ],
          const SizedBox(height: 16),
          _buildLunarMonthContextCard(d),
          const SizedBox(height: 20),
          const SectionTitle('INSTRUMENTS DE BORD AU COUCHER DU SOLEIL • NASA JPL DE421', icon: Icons.speed_rounded),
          const SizedBox(height: 12),
          _buildEveningGauges(d),
        ],
      ],
    );
  }

  Widget _buildDateControlBar() {
    return Glass(
      accent: kGold,
      padding: const EdgeInsets.all(14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Jour précédent',
                onPressed: () {
                  setState(() => _date = _date.subtract(const Duration(days: 1)));
                  _loadEvening();
                },
                icon: const Icon(Icons.chevron_left_rounded, color: kGold),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickEveningDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_rounded, color: kGold, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        frDate(_date, weekday: true),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_drop_down, color: Colors.white54),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Jour suivant',
                onPressed: () {
                  setState(() => _date = _date.add(const Duration(days: 1)));
                  _loadEvening();
                },
                icon: const Icon(Icons.chevron_right_rounded, color: kGold),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() => _date = DateTime.now());
                  _loadEvening();
                },
                icon: const Icon(Icons.today_rounded, size: 16, color: kCyan),
                label: const Text("Aujourd'hui", style: TextStyle(color: kCyan, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: _loadingEvening ? null : _loadEvening,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: kInk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                label: const Text('Analyser', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSunMoonTimesBar(Map<String, dynamic> d) {
    final sunset = (d['sunset'] as String?) ?? '—';
    final moonset = (d['moonset'] as String?) ?? '—';
    final lag = d['lag_minutes'];
    final presence = (d['moon_presence'] as String?) ?? '';
    final presentTonight = (d['present_tonight'] as bool?) ?? false;

    final lagStr = lag == null
        ? '—'
        : (lag as num) >= 0
            ? '+$lag min après Soleil'
            : '$lag min (avant Soleil)';

    return Glass(
      accent: kCyan,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('ÉPHÉMÉRIDES LOCALES DU CRÉPUSCULE & DE LA NUIT', icon: Icons.schedule_rounded, color: kCyan),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _timeStat(Icons.wb_twilight_rounded, 'Coucher du Soleil', sunset, kGold),
              _timeStat(Icons.nights_stay_rounded, 'Coucher de la Lune', moonset, kCyan),
              _timeStat(Icons.timelapse_rounded, 'Décalage (Lag)', lagStr,
                  (lag is num && lag > 0) ? kGreen : kOrange),
              _timeStat(
                presentTonight ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
                'Présence nocturne',
                presentTonight ? 'Présente cette nuit' : 'Absente cette nuit',
                presentTonight ? kGreen : kRed,
              ),
            ],
          ),
          if (presence.isNotEmpty) ...[
            const Divider(height: 22, color: Colors.white12),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.white60),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(presence, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAstronautReportCard(Map<String, dynamic> d) {
    final tip = (d['observation_tip'] as String?) ?? '';
    final weatherNote = (d['weather_note'] as String?) ?? '';
    final col = levelColor(d['badge_level'] as String?);

    return Glass(
      accent: col,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('RAPPORT SCIENTIFIQUE DE VOTRE ASTRONAUTE', icon: Icons.person_pin_circle_rounded, color: col),
          const SizedBox(height: 10),
          Text(tip, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
          if (weatherNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_queue_rounded, color: Color(0xFF8EC5FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(weatherNote, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScientificCriteriaCard(Map<String, dynamic> c) {
    final possible = (c['possible'] as bool?) ?? false;
    final yallop = c['yallop'] as Map<String, dynamic>?;
    final odeh = c['odeh'] as Map<String, dynamic>?;
    final bestTime = (c['best_time'] as String?) ?? '—';

    return Glass(
      accent: kGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CRITÈRES SCIENTIFIQUES DU CROISSANT (YALLOP 1997 & ODEH 2004)',
              icon: Icons.science_rounded, color: kGold),
          const SizedBox(height: 12),
          if (!possible)
            Text(
              (c['verdict_text'] as String?) ?? 'Croissant géométriquement impossible ce soir.',
              style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 14),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                Pill('Meilleur moment : $bestTime', kCyan, icon: Icons.access_time_filled_rounded),
                Pill('ARCV : ${c['arcv']}°', kGold),
                Pill('ARCL (Élongation) : ${c['arcl']}°', kGold),
                Pill("Largeur : ${c['width_arcmin']}'", kViolet),
                Pill('Hauteur Lune : ${c['moon_alt']}°', kGreen),
              ],
            ),
            const SizedBox(height: 14),
            if (odeh != null)
              _criterionRow(
                'Critère d’Odeh (2004)',
                'Zone ${odeh['code']}  (V = ${odeh['v']})',
                (odeh['text'] as String?) ?? '',
                verdictColor(c['verdict_code'] as String?),
              ),
            const SizedBox(height: 10),
            if (yallop != null)
              _criterionRow(
                'Critère de Yallop (1997)',
                'Zone ${yallop['code']}  (q = ${yallop['q']})',
                (yallop['text'] as String?) ?? '',
                verdictColor(c['verdict_code'] as String?),
              ),
          ],
        ],
      ),
    );
  }

  Widget _criterionRow(String title, String code, String desc, Color col) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: col.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: col),
            ),
            child: Text(code, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLunarMonthContextCard(Map<String, dynamic> d) {
    final ramadan = (d['ramadan_status'] as String?) ?? '';
    final lastNm = (d['last_new_moon'] as String?)?.replaceAll('T', ' à ') ?? '—';
    final nextNm = (d['next_new_moon'] as String?)?.replaceAll('T', ' à ') ?? '—';

    return Glass(
      accent: kViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CONJONCTIONS & CONTEXTE DU MOIS LUNAIRE', icon: Icons.mosque_rounded, color: kViolet),
          const SizedBox(height: 10),
          Text(ramadan,
              style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.45)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Pill('Dernière conjonction : $lastNm', kCyan, icon: Icons.history_rounded),
              Pill('Prochaine conjonction : $nextNm', kGold, icon: Icons.update_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEveningGauges(Map<String, dynamic> d) {
    final illum = toD(d['illumination']) ?? 0;
    final elong = toD(d['elongation_deg']) ?? 0;
    final alt = toD(d['altitude_deg']) ?? 0;
    final age = toD(d['age_days']) ?? 0;
    final cloud = toD(d['cloud_cover']);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Gauge('ILLUMINATION', illum.toStringAsFixed(1), '%', illum / 100, kGold, Icons.light_mode_rounded),
        Gauge('ÉLONGATION', elong.toStringAsFixed(1), 'degrés', elong / 180, kCyan, Icons.architecture_rounded),
        Gauge('HAUTEUR (COUCHER)', alt.toStringAsFixed(1), 'degrés', (alt + 90) / 180, kGreen, Icons.height_rounded),
        Gauge('ÂGE EXACT', age.toStringAsFixed(1), 'jours', age / 29.53, kViolet, Icons.hourglass_bottom_rounded),
        Gauge('NUAGES', cloud == null ? '—' : cloud.toStringAsFixed(0), '%', (cloud ?? 0) / 100,
            const Color(0xFF8EC5FF), Icons.cloud_rounded),
      ],
    );
  }

  Future<void> _pickEveningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2038),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kGold,
            onPrimary: kInk,
            surface: Color(0xFF12153A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _loadEvening();
    }
  }

  // ═══════════════════════════ ONGLET 1 : CALENDRIER MENSUEL ═══════════════════════════
  Widget _buildCalendarTab() {
    final m = _monthData;
    final events = ((m?['events'] as List?) ?? []).cast<Map<String, dynamic>>();
    final days = ((m?['days'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barre de navigation du mois
        Glass(
          accent: kGold,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_calMonth == 1) {
                      _calMonth = 12;
                      _calYear--;
                    } else {
                      _calMonth--;
                    }
                  });
                  _loadMonth();
                },
                icon: const Icon(Icons.chevron_left_rounded, color: kGold),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      (m?['month_label'] as String?) ?? '${kMonthsFr[_calMonth - 1].toUpperCase()} $_calYear',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${_city.flag} ${_city.name} • Présence nocturne & phases au coucher du Soleil',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_calMonth == 12) {
                      _calMonth = 1;
                      _calYear++;
                    } else {
                      _calMonth++;
                    }
                  });
                  _loadMonth();
                },
                icon: const Icon(Icons.chevron_right_rounded, color: kGold),
              ),
            ],
          ),
        ),

        if (_errorMonth != null) ...[
          const SizedBox(height: 16),
          ErrorBlock(_errorMonth!, onRetry: _loadMonth),
        ],

        if (_loadingMonth)
          const LoadingBlock('Calcul des éphémérides quotidiennes du mois…')
        else if (m != null) ...[
          const SizedBox(height: 16),

          // Événements majeurs du mois (Nouvelle Lune, Quartiers, Pleine Lune)
          if (events.isNotEmpty)
            Glass(
              accent: kCyan,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('INSTANTS EXACTS DES PHASES CE MOIS-CI', icon: Icons.auto_awesome_rounded, color: kCyan),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: events.map((e) {
                      final isNew = e['type'] == 0;
                      return Pill(
                        '${e['name']} : ${e['label']}',
                        isNew ? kGold : kCyan,
                        icon: isNew ? Icons.brightness_3_rounded : Icons.circle_outlined,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Légende
          Wrap(
            spacing: 14,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: const [
              Pill('Point vert : Lune présente la nuit', kGreen, icon: Icons.circle),
              Pill('Contour doré : Soirée de recherche du Hilal', kGold, icon: Icons.brightness_2_rounded),
            ],
          ),

          const SizedBox(height: 14),

          // Grille des jours
          _buildMonthGrid(days),

          if (_selectedDayData != null) ...[
            const SizedBox(height: 18),
            _buildSelectedDayDetail(_selectedDayData!),
          ],
        ],
      ],
    );
  }

  Widget _buildMonthGrid(List<Map<String, dynamic>> days) {
    if (days.isEmpty) return const SizedBox.shrink();
    final firstWeekday = (days.first['weekday'] as int?) ?? 0; // 0 = Lundi .. 6 = Dimanche
    const headers = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (final d in days) {
      final isSelected = _selectedDayData?['date'] == d['date'];
      final illum = toD(d['illumination']) ?? 0;
      final waxing = (d['waxing'] as bool?) ?? true;
      final present = (d['present_tonight'] as bool?) ?? false;
      final crescent = d['crescent'] as Map<String, dynamic>?;
      final hasHilal = crescent != null;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selectedDayData = d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isSelected
                  ? kGold.withOpacity(0.22)
                  : const Color(0xFF121636).withOpacity(0.75),
              border: Border.all(
                color: isSelected
                    ? kGold
                    : hasHilal
                        ? kGold.withOpacity(0.6)
                        : Colors.white.withOpacity(0.1),
                width: (isSelected || hasHilal) ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${d['day']}',
                      style: TextStyle(
                        color: isSelected ? kGold : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: present ? kGreen : Colors.white24,
                      ),
                    ),
                  ],
                ),
                CustomPaint(
                  size: const Size(26, 26),
                  painter: MoonPainter(illumination: illum, waxing: waxing, mini: true),
                ),
                Text(
                  '${illum.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Glass(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: headers
                .map((h) => Expanded(
                      child: Center(
                        child: Text(h,
                            style: const TextStyle(
                                color: kGold, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.78,
            children: cells,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayDetail(Map<String, dynamic> d) {
    final dateIso = (d['date'] as String?) ?? '';
    final dtParsed = DateTime.tryParse(dateIso);
    final present = (d['present_tonight'] as bool?) ?? false;
    final crescent = d['crescent'] as Map<String, dynamic>?;

    return Glass(
      accent: kGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomPaint(
                size: const Size(48, 48),
                painter: MoonPainter(
                  illumination: toD(d['illumination']) ?? 0,
                  waxing: (d['waxing'] as bool?) ?? true,
                  mini: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dtParsed != null ? frDate(dtParsed, weekday: true) : dateIso,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${d['phase']} • Illumination : ${d['illumination']}% • Estimation : ${d['hijri_estimate']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: dtParsed == null
                    ? null
                    : () {
                        setState(() {
                          _date = dtParsed;
                          _tab = 0;
                        });
                        _loadEvening();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: kInk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('Observer ce soir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Pill(present ? 'Présente dans le ciel cette nuit' : 'Absente du ciel cette nuit',
                  present ? kGreen : kRed),
              Pill('Coucher Soleil : ${d['sunset'] ?? '—'}', kGold),
              Pill('Lever Lune : ${d['moonrise'] ?? '—'}', kCyan),
              Pill('Coucher Lune : ${d['moonset'] ?? '—'}', kCyan),
              Pill('Hauteur au coucher : ${d['moon_alt_at_sunset']}°', kViolet),
              if (crescent != null)
                Pill('Hilal : ${crescent['verdict_text']}', verdictColor(crescent['verdict_code'] as String?)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════ ONGLET 2 : HILAL & RAMADAN ═══════════════════════════
  Widget _buildHilalTab() {
    final selectors = [
      (9, '🕌 Ramadan'),
      (10, '🌙 Chawwal (Korité / Aïd el-Fitr)'),
      (12, '🕋 Dhou al-Hijja (Tabaski)'),
      (0, '🔭 Prochain mois lunaire'),
    ];
    final h = _hilalData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Choix du mois sacré
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: selectors.map((s) {
            final sel = _targetHijriMonth == s.$1;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() => _targetHijriMonth = s.$1);
                _loadHilal();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                  color: sel ? null : const Color(0xFF14183A).withOpacity(0.8),
                  border: Border.all(color: sel ? kGold : Colors.white24),
                ),
                child: Text(
                  s.$2,
                  style: TextStyle(
                    color: sel ? kInk : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        if (_errorHilal != null) ...[
          const SizedBox(height: 16),
          ErrorBlock(_errorHilal!, onRetry: _loadHilal),
        ],

        if (_loadingHilal)
          const LoadingBlock('Simulation astronomique sur les 11 villes d’Afrique de l’Ouest…')
        else if (h != null) ...[
          const SizedBox(height: 18),
          _buildConjunctionBanner(h),
          const SizedBox(height: 18),
          _buildCityEveningsDetail(h),
          const SizedBox(height: 18),
          _buildWestAfricaComparisonTable(h),
        ],
      ],
    );
  }

  Widget _buildConjunctionBanner(Map<String, dynamic> h) {
    final loc = (h['location'] as Map<String, dynamic>?) ?? {};
    final hMonth = h['hijri_month'] ?? '';
    final hYear = h['hijri_year'] ?? '';

    return Glass(
      accent: kGold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('DÉBUT DU MOIS DE ${hMonth.toString().toUpperCase()} $hYear H • ${_city.name.toUpperCase()}',
              icon: Icons.mosque_rounded, color: kGold),
          const SizedBox(height: 12),
          Text(
            'Conjonction géocentrique exacte (Nouvelle Lune) : ${h['conjunction_label']}',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              _startCard(
                '1er $hMonth (Visibilité à l’œil nu)',
                (loc['start_naked_eye_label'] as String?) ?? '—',
                'Basé sur le critère scientifique à l’œil nu (Odeh Zone A)',
                kGreen,
                Icons.visibility_rounded,
              ),
              _startCard(
                '1er $hMonth (Avec instruments optiques)',
                (loc['start_with_instruments_label'] as String?) ?? '—',
                'Si l’observation aux jumelles / télescope est retenue',
                kCyan,
                Icons.biotech_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _startCard(String title, String dateLabel, String subtitle, Color col, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: col, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(dateLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCityEveningsDetail(Map<String, dynamic> h) {
    final loc = (h['location'] as Map<String, dynamic>?) ?? {};
    final evenings = ((loc['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Glass(
      accent: kCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('LES 3 SOIRÉES D’OBSERVATION À ${_city.name.toUpperCase()} (${_city.country.toUpperCase()})',
              icon: Icons.insights_rounded, color: kCyan),
          const SizedBox(height: 12),
          ...evenings.map((e) {
            final col = verdictColor(e['verdict_code'] as String?);
            final possible = (e['possible'] as bool?) ?? false;
            final odeh = e['odeh'] as Map<String, dynamic>?;
            final yallop = e['yallop'] as Map<String, dynamic>?;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: col.withOpacity(0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Soir du ${e['date_label']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      Pill((e['verdict_text'] as String?) ?? '', col),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Text('🌅 Coucher Soleil : ${e['sunset'] ?? '—'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('🌙 Coucher Lune : ${e['moonset'] ?? '—'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('⏱️ Décalage : ${e['lag_minutes'] ?? '—'} min',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('🕰️ Âge : ${e['age_hours']} h',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (possible && odeh != null)
                        Text('📐 Odeh : ${odeh['code']} (V=${odeh['v']})',
                            style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.bold)),
                      if (possible && yallop != null)
                        Text('📏 Yallop : ${yallop['code']} (q=${yallop['q']})',
                            style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWestAfricaComparisonTable(Map<String, dynamic> h) {
    final cities = ((h['cities'] as List?) ?? []).cast<Map<String, dynamic>>();
    final evHeaders = ((h['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Glass(
      accent: kViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CARTE COMPARATIVE • LES 11 VILLES D’AFRIQUE DE L’OUEST',
              icon: Icons.public_rounded, color: kViolet),
          const SizedBox(height: 12),
          ...cities.map((c) {
            final evs = ((c['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${c['flag']} ', style: const TextStyle(fontSize: 16)),
                      Expanded(
                        child: Text(
                          '${c['name']} (${c['country']})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      Pill('1er jour (œil nu) : ${c['start_naked_eye_label']}', kGreen),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: List.generate(evs.length, (i) {
                      final e = evs[i];
                      final col = verdictColor(e['verdict_code'] as String?);
                      final label = i < evHeaders.length ? evHeaders[i]['date'] : e['date'];
                      return Pill('$label : ${e['verdict_text']}', col);
                    }),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text('✦  ✦  ✦', style: TextStyle(color: kGold.withOpacity(0.5), letterSpacing: 6)),
        const SizedBox(height: 8),
        const Text(
          'WeerWi — la science exacte de l’astronomie au service de toute la communauté.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 3),
        const Text(
          'Éphémérides NASA JPL DE421 · Critères de Yallop (1997) & Odeh (2004) · Météo Open-Meteo',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      ],
    );
  }
}
