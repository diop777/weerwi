import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  int _tab = 0; // 0: Ce soir, 1: Calendrier, 2: Hilal & Ramadan, 3: 14 Régions & Pays
  bool _phoneMode = true;

  // Profil utilisateur (Firebase Auth + session locale)
  String? _userName;
  String? _userEmail;
  bool _gpsLoading = false;

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

  // État Onglet 3 (14 Régions du Sénégal & Pays - Point Sentinelle)
  String _selectedCountryCode = 'SN';
  int _regionHijriMonth = 9; // 9=Ramadan, 10=Chawwal, 12=Tabaski, 0=Date choisie
  int _regionDayOffset = 1; // 0=Soir J0, 1=Soir J+1, 2=Soir J+2
  Map<String, dynamic>? _regionsData;
  bool _loadingRegions = false;
  String? _errorRegions;

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
      _loadRegions();
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
    setState(() {
      _city = c;
      _selectedCountryCode = c.countryCode;
    });
    _loadEvening();
    _loadMonth();
    _loadHilal();
    _loadRegions();
  }

  Future<void> _detectGps() async {
    setState(() => _gpsLoading = true);
    try {
      final info = await Api.gpsLocate();
      if (!mounted) return;
      final detected = City(
        (info['name'] as String?) ?? 'Position GPS',
        (info['country'] as String?) ?? 'Sénégal',
        (info['flag'] as String?) ?? '📍',
        toD(info['lat']) ?? 14.6937,
        toD(info['lon']) ?? -17.4441,
        toD(info['tz']) ?? 0,
        (info['country_code'] as String?) ?? 'SN',
      );
      setState(() {
        _city = detected;
        _selectedCountryCode = detected.countryCode;
      });
      _loadEvening();
      _loadMonth();
      _loadHilal();
      _loadRegions();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF141B3D),
          content: Text(
            '📍 Position GPS détectée : ${detected.flag} ${detected.name} (${detected.country}) — '
            'Lat ${detected.lat.toStringAsFixed(3)}°, Lon ${detected.lon.toStringAsFixed(3)}°',
            style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de détecter la position GPS actuelle.')),
      );
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
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

  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _errorRegions = null;
    });
    try {
      final res = await Api.regions(
        countryCode: _selectedCountryCode,
        date: _date,
        hijriMonth: _regionHijriMonth,
        dayOffset: _regionDayOffset,
      );
      if (mounted) setState(() => _regionsData = res);
    } catch (e) {
      if (mounted) setState(() => _errorRegions = 'Impossible de charger le scan régional.');
    } finally {
      if (mounted) setState(() => _loadingRegions = false);
    }
  }

  // ─────────────────────────── BUILD ───────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final showPhoneFrame = _phoneMode && screenW > 540;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: CosmicBackground()),
          if (!showPhoneFrame)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 200,
              child: IgnorePointer(child: CustomPaint(painter: HorizonPainter())),
            ),
          SafeArea(
            child: Column(
              children: [
                if (screenW > 540) _buildSimulatorToolbar(),
                Expanded(
                  child: showPhoneFrame
                      ? Center(child: _buildAndroidVirtualPhone())
                      : _buildAppScrollContent(inPhone: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatorToolbar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 960),
      decoration: BoxDecoration(
        color: const Color(0xFF0E122E).withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: kGold.withOpacity(0.35)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_android_rounded, color: kGold, size: 18),
              const SizedBox(width: 8),
              Text(
                _phoneMode
                    ? 'Émulateur Mobile Android • Google Pixel 8 (Android 14)'
                    : 'Mode Observatoire Grand Écran',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _phoneMode = !_phoneMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kGoldDeep, kGold]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_phoneMode ? Icons.fullscreen_rounded : Icons.smartphone_rounded, size: 15, color: kInk),
                  const SizedBox(width: 6),
                  Text(
                    _phoneMode ? 'Plein écran' : 'Téléphone Virtuel',
                    style: const TextStyle(color: kInk, fontSize: 11.5, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidVirtualPhone() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 424,
          height: 876,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                right: 0,
                top: 170,
                child: Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(color: const Color(0xFF4A506A), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Positioned(
                right: 0,
                top: 238,
                child: Container(
                  width: 4,
                  height: 86,
                  decoration: BoxDecoration(color: const Color(0xFF4A506A), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Container(
                width: 414,
                height: 876,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(52),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF393E54), Color(0xFF171A26), Color(0xFF282C3E)],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.6),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.75), blurRadius: 45, spreadRadius: 8),
                    BoxShadow(color: kGold.withOpacity(0.14), blurRadius: 40, spreadRadius: 2),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(41),
                  child: Container(
                    color: kSpace,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: CosmicBackground()),
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 58,
                          height: 150,
                          child: IgnorePointer(child: CustomPaint(painter: HorizonPainter())),
                        ),
                        Column(
                          children: [
                            _buildAndroidStatusBar(),
                            Expanded(child: _buildAppScrollContent(inPhone: true)),
                            _buildAndroidBottomNav(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidStatusBar() {
    final now = TimeOfDay.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.black.withOpacity(0.28),
      child: Row(
        children: [
          Text('$hh:$mm', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          const Icon(Icons.nightlight_round, color: kGold, size: 12),
          const Spacer(),
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF05060C),
              border: Border.all(color: Colors.white24, width: 0.8),
            ),
          ),
          const Spacer(),
          const Text('5G', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(width: 5),
          const Icon(Icons.signal_cellular_4_bar_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          const Icon(Icons.wifi_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          const Icon(Icons.battery_full_rounded, color: kGreen, size: 15),
        ],
      ),
    );
  }

  Widget _buildAndroidBottomNav() {
    final items = [
      (0, Icons.nightlight_round, 'Ce soir'),
      (1, Icons.calendar_month_rounded, 'Calendrier'),
      (2, Icons.mosque_rounded, 'Ramadan'),
      (3, Icons.map_rounded, '14 Régions'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D22).withOpacity(0.96),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.12))),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: items.map((item) {
              final sel = _tab == item.$1;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = item.$1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: sel ? kGold.withOpacity(0.22) : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(item.$2, size: 19, color: sel ? kGold : Colors.white60),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: sel ? kGold : Colors.white60,
                          fontSize: 10,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Container(
            width: 115,
            height: 4,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.45), borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ),
    );
  }

  Widget _buildAppScrollContent({required bool inPhone}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(inPhone ? 14 : 18, 10, inPhone ? 14 : 18, inPhone ? 28 : 210),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildQuickActionBar(),
              const SizedBox(height: 14),
              _buildCitySelector(),
              if (!inPhone) ...[
                const SizedBox(height: 16),
                _buildNavigationTabs(),
              ],
              const SizedBox(height: 16),
              if (_tab == 0) _buildEveningTab(),
              if (_tab == 1) _buildCalendarTab(),
              if (_tab == 2) _buildHilalTab(),
              if (_tab == 3) _buildRegionsTab(),
              const SizedBox(height: 28),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── En-tête & Actions Rapides (GPS, Bulletin, Compte) ───────────────────────────
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFFFFF4C2), kGoldDeep]),
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.55), blurRadius: 18, spreadRadius: 1)],
          ),
          child: const Icon(Icons.nightlight_round, color: Color(0xFF14102A), size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(colors: [kGold, Colors.white, kCyan]).createShader(b),
                child: const Text(
                  'WeerWi',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2.2,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _userName != null
                    ? 'Astronaute $_userName • Observatoire du Hilal'
                    : 'Astronaute personnel • Observatoire du Hilal',
                style: const TextStyle(color: Colors.white60, fontSize: 10.5),
              ),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _showAuthDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _userName != null ? kGreen.withOpacity(0.16) : Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _userName != null ? kGreen : kGold.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _userName != null ? Icons.verified_user_rounded : Icons.person_outline_rounded,
                  size: 14,
                  color: _userName != null ? kGreen : kGold,
                ),
                const SizedBox(width: 5),
                Text(
                  _userName ?? 'Connexion',
                  style: TextStyle(
                    color: _userName != null ? kGreen : kGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 1. Détection GPS automatique
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _gpsLoading ? null : _detectGps,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kCyan.withOpacity(0.55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_gpsLoading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kCyan),
                  )
                else
                  const Icon(Icons.my_location_rounded, size: 14, color: kCyan),
                const SizedBox(width: 6),
                Text(
                  _gpsLoading ? 'Localisation GPS…' : 'Ma position GPS',
                  style: const TextStyle(color: kCyan, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        // 2. Accès direct aux 14 Régions du Sénégal
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _tab = 3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kGold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withOpacity(0.6)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🇸🇳', style: TextStyle(fontSize: 12)),
                SizedBox(width: 6),
                Text(
                  '14 Régions & Point Sentinelle',
                  style: TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        // 3. Export du Bulletin Officiel PDF / WhatsApp
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _showBulletinDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kViolet.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kViolet.withOpacity(0.6)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf_rounded, size: 14, color: kViolet),
                SizedBox(width: 6),
                Text(
                  'Bulletin PDF',
                  style: TextStyle(color: kViolet, fontSize: 11, fontWeight: FontWeight.w800),
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
        const SectionTitle("POINT D'OBSERVATION • SÉNÉGAL & AFRIQUE DE L'OUEST", icon: Icons.public_rounded),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kCities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = kCities[i];
              final sel = c.name == _city.name;
              return InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => _selectCity(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
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
                  ),
                  child: Row(
                    children: [
                      Text(c.flag, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        c.name,
                        style: TextStyle(
                          color: sel ? kInk : Colors.white,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                          fontSize: 12.5,
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
      (3, Icons.map_rounded, '14 Régions & Pays'),
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
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$2, size: 17, color: sel ? kInk : Colors.white70),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.$3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sel ? kInk : Colors.white,
                          fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 12.5,
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
        '${_city.lat.abs().toStringAsFixed(2)}°${_city.lat >= 0 ? 'N' : 'S'} · ${_city.lon.abs().toStringAsFixed(2)}°${_city.lon >= 0 ? 'E' : 'O'} · UTC${_city.tz >= 0 ? '+${_city.tz.toInt()}' : '${_city.tz.toInt()}'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            SizedBox(
              height: 260,
              child: AnimatedBuilder(
                animation: Listenable.merge([_float, _orbit, _pulse]),
                builder: (context, _) {
                  final dy = math.sin(_float.value * 2 * math.pi) * 7;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(size: const Size(340, 260), painter: OrbitPainter(_orbit.value)),
                      Transform.translate(
                        offset: Offset(0, dy),
                        child: CustomPaint(
                          size: const Size(190, 190),
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
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                shadows: [Shadow(color: kGold, blurRadius: 18)],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_city.flag}  ${_city.name}, ${_city.country}  •  ${frDate(_date, weekday: true)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 3),
            Text('📡 $coords', style: TextStyle(color: kCyan.withOpacity(0.75), fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            if (_loadingEvening)
              const LoadingBlock('Calcul topocentrique au coucher du Soleil…')
            else if (d != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: LinearGradient(colors: [badgeCol.withOpacity(0.24), badgeCol.withOpacity(0.06)]),
                  border: Border.all(color: badgeCol.withOpacity(0.85), width: 1.4),
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
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        badgeText,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: badgeCol, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1.1),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _buildDateControlBar(),
        if (_errorEvening != null) ...[
          const SizedBox(height: 14),
          ErrorBlock(_errorEvening!, onRetry: _loadEvening),
        ],
        if (d != null && !_loadingEvening) ...[
          const SizedBox(height: 16),
          _buildSunMoonTimesBar(d),
          const SizedBox(height: 14),
          _buildCompassAndTurbulenceCard(d),
          const SizedBox(height: 14),
          _buildAstronautReportCard(d),
          if (d['crescent'] != null) ...[
            const SizedBox(height: 14),
            _buildScientificCriteriaCard(d['crescent'] as Map<String, dynamic>),
          ],
          const SizedBox(height: 14),
          _buildLunarMonthContextCard(d),
          const SizedBox(height: 18),
          const SectionTitle('INSTRUMENTS DE BORD AU COUCHER DU SOLEIL • NASA JPL DE421', icon: Icons.speed_rounded),
          const SizedBox(height: 10),
          _buildEveningGauges(d),
        ],
      ],
    );
  }

  Widget _buildCompassAndTurbulenceCard(Map<String, dynamic> d) {
    final moonAz = toD(d['moon_azimuth_deg']) ?? 270.0;
    final sunAz = toD(d['sun_azimuth_deg']) ?? 270.0;
    final moonAlt = toD(d['altitude_deg']) ?? 0.0;
    final daz = toD(d['daz_deg']) ?? 0.0;
    final cardinal = (d['cardinal_direction'] as String?) ?? 'O';
    final turbLevel = (d['turbulence_level'] as String?) ?? 'Stable';
    final turbNote = (d['turbulence_note'] as String?) ?? '';
    final airmass = d['airmass'];

    return Glass(
      accent: kGold,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('BOUSSOLE DE VISÉE & TURBULENCE ATMOSPHÉRIQUE', icon: Icons.explore_rounded, color: kGold),
          const SizedBox(height: 12),
          Row(
            children: [
              CustomPaint(
                size: const Size(118, 118),
                painter: CompassPainter(moonAz: moonAz, sunAz: sunAz, moonAlt: moonAlt),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direction Lune : ${moonAz.toStringAsFixed(1)}° ($cardinal)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hauteur sur l’horizon : ${moonAlt.toStringAsFixed(1)}°',
                      style: TextStyle(
                        color: moonAlt > 0 ? kGreen : kRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Soleil : ${sunAz.toStringAsFixed(1)}°  •  Écart DAZ : ${daz.toStringAsFixed(1)}°',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Pill(
                      '$turbLevel${airmass != null ? ' ($airmass×)' : ''}',
                      moonAlt < 6 ? kOrange : kCyan,
                      icon: Icons.air_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (turbNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(turbNote, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildDateControlBar() {
    return Glass(
      accent: kGold,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _date = _date.subtract(const Duration(days: 1)));
                  _loadEvening();
                },
                icon: const Icon(Icons.chevron_left_rounded, color: kGold),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickEveningDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_rounded, color: kGold, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        frDate(_date),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
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
              TextButton(
                onPressed: () {
                  setState(() => _date = DateTime.now());
                  _loadEvening();
                },
                child: const Text("Aujourd'hui", style: TextStyle(color: kCyan, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: _loadingEvening ? null : _loadEvening,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: kInk,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Analyser', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
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
            ? '+$lag min'
            : '$lag min';

    return Glass(
      accent: kCyan,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('ÉPHÉMÉRIDES DU CRÉPUSCULE & DE LA NUIT', icon: Icons.schedule_rounded, color: kCyan),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _timeStat(Icons.wb_twilight_rounded, 'Coucher Soleil', sunset, kGold),
              _timeStat(Icons.nights_stay_rounded, 'Coucher Lune', moonset, kCyan),
              _timeStat(Icons.timelapse_rounded, 'Décalage', lagStr, (lag is num && lag > 0) ? kGreen : kOrange),
              _timeStat(
                presentTonight ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
                'Cette nuit',
                presentTonight ? 'Présente' : 'Absente',
                presentTonight ? kGreen : kRed,
              ),
            ],
          ),
          if (presence.isNotEmpty) ...[
            const Divider(height: 18, color: Colors.white12),
            Text(presence, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }

  Widget _timeStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('RAPPORT SCIENTIFIQUE DE VOTRE ASTRONAUTE', icon: Icons.person_pin_circle_rounded, color: col),
          const SizedBox(height: 8),
          Text(tip, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45)),
          if (weatherNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_queue_rounded, color: Color(0xFF8EC5FF), size: 17),
                  const SizedBox(width: 8),
                  Expanded(child: Text(weatherNote, style: const TextStyle(color: Colors.white70, fontSize: 12))),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CRITÈRES SCIENTIFIQUES (YALLOP 1997 & ODEH 2004)', icon: Icons.science_rounded, color: kGold),
          const SizedBox(height: 10),
          if (!possible)
            Text(
              (c['verdict_text'] as String?) ?? 'Croissant géométriquement impossible ce soir.',
              style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 13.5),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill('Meilleur moment : $bestTime', kCyan, icon: Icons.access_time_filled_rounded),
                Pill('ARCV : ${c['arcv']}°', kGold),
                Pill('ARCL : ${c['arcl']}°', kGold),
                Pill("Largeur : ${c['width_arcmin']}'", kViolet),
              ],
            ),
            const SizedBox(height: 12),
            if (odeh != null)
              _criterionRow(
                'Critère d’Odeh (2004)',
                'Zone ${odeh['code']} (V=${odeh['v']})',
                (odeh['text'] as String?) ?? '',
                verdictColor(c['verdict_code'] as String?),
              ),
            const SizedBox(height: 8),
            if (yallop != null)
              _criterionRow(
                'Critère de Yallop (1997)',
                'Zone ${yallop['code']} (q=${yallop['q']})',
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: col.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: col),
            ),
            child: Text(code, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CONJONCTIONS & CONTEXTE DU MOIS LUNAIRE', icon: Icons.mosque_rounded, color: kViolet),
          const SizedBox(height: 8),
          Text(ramadan,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Pill('Dernière conjonction : $lastNm', kCyan),
              Pill('Prochaine conjonction : $nextNm', kGold),
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
      spacing: 10,
      runSpacing: 10,
      children: [
        Gauge('ILLUMINATION', illum.toStringAsFixed(1), '%', illum / 100, kGold, Icons.light_mode_rounded),
        Gauge('ÉLONGATION', elong.toStringAsFixed(1), 'degrés', elong / 180, kCyan, Icons.architecture_rounded),
        Gauge('HAUTEUR', alt.toStringAsFixed(1), 'degrés', (alt + 90) / 180, kGreen, Icons.height_rounded),
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
        Glass(
          accent: kGold,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${_city.flag} ${_city.name} • Présence nocturne & phases',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 11.5),
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
          const SizedBox(height: 14),
          ErrorBlock(_errorMonth!, onRetry: _loadMonth),
        ],
        if (_loadingMonth)
          const LoadingBlock('Calcul des éphémérides quotidiennes du mois…')
        else if (m != null) ...[
          const SizedBox(height: 14),
          if (events.isNotEmpty)
            Glass(
              accent: kCyan,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('INSTANTS EXACTS DES PHASES CE MOIS-CI', icon: Icons.auto_awesome_rounded, color: kCyan),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: const [
              Pill('Point vert : Lune présente la nuit', kGreen, icon: Icons.circle),
              Pill('Contour doré : Soirée Hilal', kGold, icon: Icons.brightness_2_rounded),
            ],
          ),
          const SizedBox(height: 12),
          _buildMonthGrid(days),
          if (_selectedDayData != null) ...[
            const SizedBox(height: 14),
            _buildSelectedDayDetail(_selectedDayData!),
          ],
        ],
      ],
    );
  }

  Widget _buildMonthGrid(List<Map<String, dynamic>> days) {
    if (days.isEmpty) return const SizedBox.shrink();
    final firstWeekday = (days.first['weekday'] as int?) ?? 0;
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
      final hasHilal = d['crescent'] != null;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedDayData = d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isSelected ? kGold.withOpacity(0.22) : const Color(0xFF121636).withOpacity(0.75),
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
                        fontSize: 11,
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: present ? kGreen : Colors.white24),
                    ),
                  ],
                ),
                CustomPaint(
                  size: const Size(22, 22),
                  painter: MoonPainter(illumination: illum, waxing: waxing, mini: true),
                ),
                Text('${illum.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white60, fontSize: 9.5)),
              ],
            ),
          ),
        ),
      );
    }

    return Glass(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: headers
                .map((h) => Expanded(
                      child: Center(
                        child: Text(h,
                            style: const TextStyle(color: kGold, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.72,
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size(40, 40),
                    painter: MoonPainter(
                      illumination: toD(d['illumination']) ?? 0,
                      waxing: (d['waxing'] as bool?) ?? true,
                      mini: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dtParsed != null ? frDate(dtParsed, weekday: true) : dateIso,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${d['phase']} • ${d['illumination']}% • ${d['hijri_estimate']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 15),
                label: const Text('Observer ce soir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Pill(present ? 'Présente cette nuit' : 'Absente cette nuit', present ? kGreen : kRed),
              Pill('Coucher Soleil : ${d['sunset'] ?? '—'}', kGold),
              Pill('Lever Lune : ${d['moonrise'] ?? '—'}', kCyan),
              Pill('Coucher Lune : ${d['moonset'] ?? '—'}', kCyan),
              Pill('Hauteur : ${d['moon_alt_at_sunset']}°', kViolet),
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
      (10, '🌙 Chawwal (Korité)'),
      (12, '🕋 Tabaski'),
      (0, '🔭 Prochain mois'),
    ];
    final h = _hilalData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selectors.map((s) {
            final sel = _targetHijriMonth == s.$1;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() => _targetHijriMonth = s.$1);
                _loadHilal();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                  color: sel ? null : const Color(0xFF14183A).withOpacity(0.8),
                  border: Border.all(color: sel ? kGold : Colors.white24),
                ),
                child: Text(
                  s.$2,
                  style: TextStyle(color: sel ? kInk : Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            );
          }).toList(),
        ),
        if (_errorHilal != null) ...[
          const SizedBox(height: 14),
          ErrorBlock(_errorHilal!, onRetry: _loadHilal),
        ],
        if (_loadingHilal)
          const LoadingBlock('Simulation astronomique sur les villes d’Afrique de l’Ouest…')
        else if (h != null) ...[
          const SizedBox(height: 16),
          _buildConjunctionBanner(h),
          const SizedBox(height: 16),
          _buildCityEveningsDetail(h),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('DÉBUT DE ${hMonth.toString().toUpperCase()} $hYear H • ${_city.name.toUpperCase()}',
              icon: Icons.mosque_rounded, color: kGold),
          const SizedBox(height: 10),
          Text(
            'Conjonction exacte (Nouvelle Lune) : ${h['conjunction_label']}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _startCard(
                '1er $hMonth (Visibilité à l’œil nu)',
                (loc['start_naked_eye_label'] as String?) ?? '—',
                'Critère scientifique à l’œil nu (Odeh Zone A)',
                kGreen,
                Icons.visibility_rounded,
              ),
              _startCard(
                '1er $hMonth (Avec instruments)',
                (loc['start_with_instruments_label'] as String?) ?? '—',
                'Si l’observation optique est retenue',
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
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: col.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: col, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(dateLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900)),
                Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('LES 3 SOIRÉES D’OBSERVATION À ${_city.name.toUpperCase()}',
              icon: Icons.insights_rounded, color: kCyan),
          const SizedBox(height: 10),
          ...evenings.map((e) {
            final col = verdictColor(e['verdict_code'] as String?);
            final possible = (e['possible'] as bool?) ?? false;
            final odeh = e['odeh'] as Map<String, dynamic>?;
            final yallop = e['yallop'] as Map<String, dynamic>?;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: col.withOpacity(0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Soir du ${e['date_label']}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Pill((e['verdict_text'] as String?) ?? '', col),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    children: [
                      Text('🌅 Soleil : ${e['sunset'] ?? '—'}', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      Text('🌙 Lune : ${e['moonset'] ?? '—'}', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      Text('⏱️ Lag : ${e['lag_minutes'] ?? '—'} min', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      Text('🕰️ Âge : ${e['age_hours']} h', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      if (possible && odeh != null)
                        Text('📐 Odeh : ${odeh['code']} (V=${odeh['v']})',
                            style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.bold)),
                      if (possible && yallop != null)
                        Text('📏 Yallop : ${yallop['code']} (q=${yallop['q']})',
                            style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CARTE COMPARATIVE • CAPITALES D’AFRIQUE DE L’OUEST',
              icon: Icons.public_rounded, color: kViolet),
          const SizedBox(height: 10),
          ...cities.map((c) {
            final evs = ((c['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        '${c['flag']}  ${c['name']} (${c['country']})',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      Pill('1er jour (œil nu) : ${c['start_naked_eye_label']}', kGreen),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
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

  // ═══════════════════════════ ONGLET 3 : 14 RÉGIONS DU SÉNÉGAL & PAYS (POINT SENTINELLE) ═══════════════════════════
  Widget _buildRegionsTab() {
    final countries = [
      ('SN', '🇸🇳 Sénégal (14 Régions)'),
      ('ML', '🇲🇱 Mali'),
      ('MR', '🇲🇷 Mauritanie'),
      ('CI', "🇨🇮 Côte d'Ivoire"),
      ('GN', '🇬🇳 Guinée'),
      ('BF', '🇧🇫 Burkina Faso'),
      ('NE', '🇳🇪 Niger'),
      ('WORLD', '🌍 Monde & Lieux Saints'),
    ];
    final months = [
      (9, '🕌 Ramadan'),
      (10, '🌙 Korité / Chawwal'),
      (12, '🕋 Tabaski'),
      (0, '🔭 Prochain Hilal'),
    ];
    final r = _regionsData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Sélecteur de Pays
        const SectionTitle('CHOISIR UN PAYS OU OBSERVATOIRE MONDIAL', icon: Icons.flag_rounded),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: countries.map((c) {
            final sel = _selectedCountryCode == c.$1;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() => _selectedCountryCode = c.$1);
                _loadRegions();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                  color: sel ? null : const Color(0xFF14183A).withOpacity(0.8),
                  border: Border.all(color: sel ? kGold : Colors.white24),
                ),
                child: Text(
                  c.$2,
                  style: TextStyle(color: sel ? kInk : Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // 2. Sélecteur de Mois & Soirée (J0, J+1, J+2)
        Glass(
          accent: kCyan,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: months.map((m) {
                  final sel = _regionHijriMonth == m.$1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() => _regionHijriMonth = m.$1);
                      _loadRegions();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: sel ? kCyan.withOpacity(0.22) : Colors.white.withOpacity(0.05),
                        border: Border.all(color: sel ? kCyan : Colors.white12),
                      ),
                      child: Text(
                        m.$2,
                        style: TextStyle(
                          color: sel ? kCyan : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (r != null && r['evenings'] != null) ...[
                const SizedBox(height: 10),
                const Text('Soirée après la conjonction :', style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ((r['evenings'] as List).cast<Map<String, dynamic>>()).map((ev) {
                    final idx = (ev['index'] as int?) ?? 0;
                    final sel = _regionDayOffset == idx;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _regionDayOffset = idx);
                        _loadRegions();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: sel ? kGold : Colors.white.withOpacity(0.05),
                          border: Border.all(color: sel ? kGold : Colors.white24),
                        ),
                        child: Text(
                          'Soir ${idx + 1} (${ev['date']})',
                          style: TextStyle(
                            color: sel ? kInk : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),

        if (_errorRegions != null) ...[
          const SizedBox(height: 14),
          ErrorBlock(_errorRegions!, onRetry: _loadRegions),
        ],

        if (_loadingRegions)
          const LoadingBlock('Scan astronomique de toutes les régions, villes et villages…')
        else if (r != null) ...[
          const SizedBox(height: 16),
          _buildSentinelRuleCard(r),
          const SizedBox(height: 16),
          _buildRegionsBreakdown(r),
        ],
      ],
    );
  }

  Widget _buildSentinelRuleCard(Map<String, dynamic> r) {
    final sen = (r['sentinel'] as Map<String, dynamic>?) ?? {};
    final counts = (r['counts'] as Map<String, dynamic>?) ?? {};
    final col = levelColor(r['rule_level'] as String?);

    return Glass(
      accent: col,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('RÈGLE D’OR ASTRONOMIQUE & POINT SENTINELLE DU PAYS', icon: Icons.emoji_events_rounded, color: col),
          const SizedBox(height: 8),
          Text(
            (r['rule_title'] as String?) ?? '',
            style: TextStyle(color: col, fontSize: 15.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Mois visé : ${r['hijri_target']}  •  Conjonction : ${r['conjunction_label']}',
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kGold.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: kGold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Point Sentinelle #1 (Lieu le plus favorable) : ${sen['name']} — Région de ${sen['region']}',
                        style: const TextStyle(color: kGold, fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '🌅 Soleil : ${sen['sunset']}  •  🌙 Lune : ${sen['moonset']} (Lag : ${sen['lag_minutes']} min)  •  '
                  'Indice Odeh V = ${sen['odeh_v'] ?? '—'} (Zone ${sen['odeh_code']})  •  Yallop = ${sen['yallop_code']}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            (r['rule_text'] as String?) ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill('Œil nu : ${counts['naked_eye']}/${counts['total']}', kGreen, icon: Icons.visibility_rounded),
              Pill('Jumelles / Œil nu possible : ${counts['naked_eye_possible']}', kGold),
              Pill('Instruments seuls : ${counts['optical_only']}', kOrange),
              Pill('Impossible : ${counts['not_visible']}', kRed, icon: Icons.visibility_off_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegionsBreakdown(Map<String, dynamic> r) {
    final regs = ((r['regions'] as List?) ?? []).cast<Map<String, dynamic>>();
    final flag = (r['flag'] as String?) ?? '🇸🇳';
    final cname = (r['country_name'] as String?) ?? 'Sénégal';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('DÉTAIL PAR RÉGION, DÉPARTEMENT, VILLE & FOYER RELIGIEUX ($flag $cname)',
            icon: Icons.location_city_rounded, color: kGold),
        const SizedBox(height: 10),
        ...regs.map((reg) {
          final col = verdictColor(reg['verdict_code'] as String?);
          final locs = ((reg['localities'] as List?) ?? []).cast<Map<String, dynamic>>();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Glass(
              accent: col,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        '$flag  Région de ${reg['region']}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      Pill((reg['verdict_text'] as String?) ?? '', col),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: locs.map((l) {
                      final lCol = verdictColor(l['verdict_code'] as String?);
                      final vStr = l['odeh_v'] != null ? ' • V=${l['odeh_v']}' : '';
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          final chosen = City(
                            (l['name'] as String?) ?? '',
                            cname.split(' (').first,
                            flag,
                            toD(l['lat']) ?? 14.69,
                            toD(l['lon']) ?? -17.44,
                            toD(l['tz']) ?? 0,
                            _selectedCountryCode,
                          );
                          final parsedDate = DateTime.tryParse((r['date'] as String?) ?? '');
                          setState(() {
                            _city = chosen;
                            if (parsedDate != null) _date = parsedDate;
                            _tab = 0;
                          });
                          _loadEvening();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: lCol.withOpacity(0.11),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: lCol.withOpacity(0.55)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    l['verdict_code'] == 'naked_eye'
                                        ? Icons.check_circle_rounded
                                        : l['verdict_code'] == 'not_visible'
                                            ? Icons.cancel_rounded
                                            : Icons.remove_red_eye_rounded,
                                    size: 13,
                                    color: lCol,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${l['name']}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${l['type']} • Lag ${l['lag_minutes']}m$vStr',
                                style: const TextStyle(color: Colors.white60, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════ BOÎTES DE DIALOGUE (CONNEXION & BULLETIN PDF) ═══════════════════════════
  void _showAuthDialog() {
    final nameCtrl = TextEditingController(text: _userName ?? '');
    final emailCtrl = TextEditingController(text: _userEmail ?? '');
    final passCtrl = TextEditingController();
    City favCity = _city;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF101432),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: kGold.withOpacity(0.45)),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_pin_rounded, color: kGold),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Compte Observateur WeerWi',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Connectez-vous pour enregistrer votre ville favorite et personnaliser vos bulletins astronomiques.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom ou Titre (ex: Astronaute Diop)',
                    prefixIcon: Icon(Icons.badge_rounded, color: kGold),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adresse Email',
                    prefixIcon: Icon(Icons.email_rounded, color: kCyan),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: Icon(Icons.lock_rounded, color: kViolet),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<City>(
                  value: kCities.contains(favCity) ? favCity : kCities.first,
                  dropdownColor: const Color(0xFF161B42),
                  decoration: const InputDecoration(labelText: 'Localité favorite par défaut'),
                  items: kCities
                      .map((c) => DropdownMenuItem(value: c, child: Text('${c.flag} ${c.name} (${c.country})')))
                      .toList(),
                  onChanged: (c) {
                    if (c != null) setModalState(() => favCity = c);
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (_userName != null)
              TextButton(
                onPressed: () {
                  try {
                    FirebaseAuth.instance.signOut();
                  } catch (_) {}
                  setState(() {
                    _userName = null;
                    _userEmail = null;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Déconnexion', style: TextStyle(color: kRed)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk),
              onPressed: () async {
                final name = nameCtrl.text.trim().isEmpty ? 'Observateur' : nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final pass = passCtrl.text.trim();
                if (email.isNotEmpty && pass.length >= 6) {
                  try {
                    await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
                  } catch (_) {
                    try {
                      await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
                    } catch (_) {}
                  }
                }
                setState(() {
                  _userName = name;
                  _userEmail = email;
                });
                _selectCity(favCity);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Valider & Connecter', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBulletinDialog() {
    final d = _eveningData;
    final r = _regionsData;
    final sen = (r?['sentinel'] as Map<String, dynamic>?) ?? {};
    final url = Api.bulletinUrl(_city, _date, _regionHijriMonth);

    final reportText = '''
🌙 BULLETIN ASTRONOMIQUE OFFICIEL WEERWI
📍 Localité : ${_city.flag} ${_city.name} (${_city.country})
📅 Soirée : ${d?['date_label'] ?? frDate(_date, weekday: true)}
🔭 Verdict : ${d?['badge_text'] ?? '—'}

🌅 Coucher Soleil : ${d?['sunset'] ?? '—'} | 🌙 Coucher Lune : ${d?['moonset'] ?? '—'} (Lag : ${d?['lag_minutes'] ?? '—'} min)
🧭 Visée : Azimut ${d?['moon_azimuth_deg'] ?? '—'}° (${d?['cardinal_direction'] ?? 'O'}) • Hauteur ${d?['altitude_deg'] ?? '—'}°
🌓 Phase : ${d?['phase'] ?? '—'} (${d?['illumination'] ?? '—'}%) • Âge : ${d?['age_hours'] ?? '—'} h
🌪️ Atmosphère : ${d?['turbulence_level'] ?? '—'}

🏆 Point Sentinelle (${r?['country_name'] ?? _city.country}) : ${sen['name'] ?? _city.name} (${sen['region'] ?? ''}) — Odeh V = ${sen['odeh_v'] ?? '—'}
📌 Synthèse : ${d?['observation_tip'] ?? ''}
🕌 Contexte : ${d?['ramadan_status'] ?? ''}
(Source : WeerWi • Éphémérides NASA JPL DE421 • Critères de Yallop & Odeh)''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101432),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: kGold.withOpacity(0.45)),
        ),
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf_rounded, color: kGold),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bulletin Scientifique Officiel',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: SelectableText(
                  reportText,
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.45),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Lien du Bulletin PDF complet (14 régions & tableau officiel imprimable) :',
                style: TextStyle(color: kCyan, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(url, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: kCyan, foregroundColor: kInk),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lien du Bulletin PDF copié ! Ouvrez-le dans un onglet pour imprimer en PDF.')),
              );
            },
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('Copier lien PDF', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: reportText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('📋 Bulletin copié dans le presse-papiers (prêt pour WhatsApp / Partage) !')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copier pour WhatsApp', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text('✦  ✦  ✦', style: TextStyle(color: kGold.withOpacity(0.5), letterSpacing: 6)),
        const SizedBox(height: 6),
        const Text(
          'WeerWi — la science exacte de l’astronomie au service de toute la communauté.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 10.5),
        ),
        const SizedBox(height: 2),
        const Text(
          'Éphémérides NASA JPL DE421 · Critères de Yallop (1997) & Odeh (2004) · 14 Régions du Sénégal & Monde',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 9.5),
        ),
      ],
    );
  }
}
