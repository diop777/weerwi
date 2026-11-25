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
      title: 'WeerWi • Observatoire Lunaire',
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

enum _AppStage { login, verifyOtp, locationPermission, ready }

enum _PhoneModal { none, dialPicker, profile, bulletin, guestRestriction }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  _AppStage _stage = _AppStage.login;
  _PhoneModal _modal = _PhoneModal.none;
  bool _isSignUp = false;
  bool _loginWithPhone = true;
  bool _obscurePassword = true;
  bool _isGuest = false;
  bool _authBusy = false;

  DialCountry _dialCountry = kWestAfricaDialCodes[0];
  String? _preferredCountryCode;

  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final ScrollController _mainScrollCtrl = ScrollController();

  String? _authIdentity;
  String? _userFullName;
  String? _pendingContact;
  String _pendingChannel = 'sms';
  String? _otpPreviewCode;
  String? _authError;

  City _city = kDefaultCountryCities[0];
  List<City> _countryCities = kDefaultCountryCities;
  int _regionCount = 14;
  int _tab = 0; // 0: Ce soir, 1: Calendrier, 2: Ramadan, 3: Régions
  bool _phoneMode = true;
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
  int _targetHijriMonth = 9;
  Map<String, dynamic>? _hilalData;
  bool _loadingHilal = false;
  String? _errorHilal;

  // État Onglet 3 (Régions du pays de l'utilisateur)
  int _regionHijriMonth = 9;
  int _regionDayOffset = 1;
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
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _otpCtrl.dispose();
    _mainScrollCtrl.dispose();
    _float.dispose();
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _switchTab(int newTab) {
    setState(() => _tab = newTab);
    if (_mainScrollCtrl.hasClients) {
      _mainScrollCtrl.jumpTo(0);
    }
  }

  // ─────────────────────────── Étape 1 : Connexion / Création de Compte ───────────────────────────
  Future<void> _submitAuthForm() async {
    setState(() => _authError = null);

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (_isSignUp && (firstName.isEmpty || lastName.isEmpty)) {
      setState(() => _authError = 'Veuillez renseigner votre prénom et votre nom.');
      return;
    }

    String contact;
    String channel;
    if (_loginWithPhone) {
      final rawPhone = _phoneCtrl.text.trim();
      if (rawPhone.length < 5) {
        setState(() => _authError = 'Veuillez saisir un numéro de téléphone valide.');
        return;
      }
      contact = '${_dialCountry.dial} $rawPhone';
      channel = 'sms';
      _preferredCountryCode = _dialCountry.code;
    } else {
      final email = _emailCtrl.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        setState(() => _authError = 'Veuillez saisir une adresse e-mail valide.');
        return;
      }
      contact = email;
      channel = 'email';
      _preferredCountryCode = null;
    }

    if (pass.length < 4) {
      setState(() => _authError = 'Veuillez définir un mot de passe (4 caractères min.).');
      return;
    }

    if (_isSignUp) {
      setState(() => _authBusy = true);
      try {
        final res = await Api.sendOtp(
          firstName: firstName,
          lastName: lastName,
          contact: contact,
          channel: channel,
        );
        if (!mounted) return;
        setState(() {
          _pendingContact = contact;
          _pendingChannel = channel;
          _otpPreviewCode = (res['code_preview'] as String?) ?? '';
          _userFullName = '$firstName $lastName';
          _otpCtrl.clear();
          _stage = _AppStage.verifyOtp;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _authError = "Impossible d'envoyer le code de vérification.");
      } finally {
        if (mounted) setState(() => _authBusy = false);
      }
    } else {
      if (!_loginWithPhone) {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(email: contact, password: pass);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _isGuest = false;
        _authIdentity = contact;
        _stage = _AppStage.locationPermission;
      });
    }
  }

  Future<void> _verifyOtpCode() async {
    setState(() => _authError = null);
    final code = _otpCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _authError = 'Veuillez saisir le code à 6 chiffres reçu.');
      return;
    }
    setState(() => _authBusy = true);
    try {
      await Api.verifyOtp(contact: _pendingContact ?? '', code: code);
      if (!_loginWithPhone && _pendingContact != null) {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _pendingContact!,
            password: _passCtrl.text.trim(),
          );
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _isGuest = false;
        _authIdentity = _pendingContact;
        _stage = _AppStage.locationPermission;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _authError = 'Code de vérification incorrect.');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _resendOtpCode() async {
    setState(() {
      _authBusy = true;
      _authError = null;
    });
    try {
      final res = await Api.sendOtp(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        contact: _pendingContact ?? '',
        channel: _pendingChannel,
      );
      if (!mounted) return;
      setState(() => _otpPreviewCode = (res['code_preview'] as String?) ?? '');
    } catch (_) {
      if (!mounted) return;
      setState(() => _authError = 'Impossible de renvoyer le code.');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _submitAppleLogin() async {
    setState(() => _authError = null);
    try {
      final provider = OAuthProvider('apple.com');
      await FirebaseAuth.instance.signInWithProvider(provider);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isGuest = false;
      _preferredCountryCode = null;
      _authIdentity = 'Compte Apple';
      _stage = _AppStage.locationPermission;
    });
  }

  void _continueAsGuest() {
    setState(() {
      _authError = null;
      _isGuest = true;
      _authIdentity = null;
      _userFullName = null;
      _preferredCountryCode = null;
      _stage = _AppStage.locationPermission;
    });
  }

  // ─────────────────────────── Étape 3 : Autorisation GPS & Adaptation au Pays ───────────────────────────
  Future<void> _authorizeAndDetectGps() async {
    setState(() => _gpsLoading = true);
    try {
      final info = await Api.gpsLocate(countryCode: _preferredCountryCode);
      if (!mounted) return;
      final detected = City.fromJson(info);
      final rawCities = (info['country_cities'] as List?) ?? [];
      final parsedCities = rawCities.isNotEmpty
          ? rawCities.cast<Map<String, dynamic>>().map(City.fromJson).toList()
          : kDefaultCountryCities;
      setState(() {
        _city = detected;
        _countryCities = parsedCities;
        _regionCount = (info['region_count'] as int?) ?? 14;
        _stage = _AppStage.ready;
      });
      _loadAllForCurrentCity();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _city = kDefaultCountryCities[0];
        _countryCities = kDefaultCountryCities;
        _regionCount = 14;
        _stage = _AppStage.ready;
      });
      _loadAllForCurrentCity();
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _selectCity(City c) {
    setState(() => _city = c);
    _loadAllForCurrentCity();
  }

  void _loadAllForCurrentCity() {
    _loadEvening();
    _loadMonth();
    _loadHilal();
    _loadRegions();
  }

  Future<void> _loadEvening() async {
    setState(() {
      _loadingEvening = true;
      _errorEvening = null;
    });
    try {
      final res = await Api.evening(_city, _date);
      if (mounted) setState(() => _eveningData = res);
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
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
        countryCode: _city.countryCode,
        date: _date,
        hijriMonth: _regionHijriMonth,
        dayOffset: _regionDayOffset,
      );
      if (mounted) {
        setState(() {
          _regionsData = res;
          final regs = (res['regions'] as List?) ?? [];
          if (regs.isNotEmpty) _regionCount = regs.length;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorRegions = 'Impossible de charger les régions.');
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
                      : Stack(
                          children: [
                            _buildStageContent(inPhone: false),
                            if (_modal != _PhoneModal.none) _buildInScreenModalOverlay(),
                          ],
                        ),
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
                _phoneMode ? 'Téléphone Virtuel Mobile • WeerWi' : 'Mode Observatoire Grand Écran',
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
    final hasBottomNav = _stage == _AppStage.ready;
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
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: hasBottomNav ? 58 : 0,
                          height: 155,
                          child: const IgnorePointer(child: CustomPaint(painter: HorizonPainter())),
                        ),
                        Column(
                          children: [
                            _buildAndroidStatusBar(),
                            Expanded(
                              child: Stack(
                                children: [
                                  _buildStageContent(inPhone: true),
                                  if (_modal != _PhoneModal.none) _buildInScreenModalOverlay(),
                                ],
                              ),
                            ),
                            if (hasBottomNav) _buildAndroidBottomNav(),
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

  Widget _buildStageContent({required bool inPhone}) {
    switch (_stage) {
      case _AppStage.login:
        return _buildLoginScreen(inPhone: inPhone);
      case _AppStage.verifyOtp:
        return _buildVerifyOtpScreen(inPhone: inPhone);
      case _AppStage.locationPermission:
        return _buildLocationPermissionScreen(inPhone: inPhone);
      case _AppStage.ready:
        return _buildAppScrollContent(inPhone: inPhone);
    }
  }

  // ─────────────────────────── Champ de saisie uniforme (46px) ───────────────────────────
  Widget _uniformTextField({
    required TextEditingController controller,
    required String hint,
    IconData? prefixIcon,
    Color prefixColor = kGold,
    Widget? suffix,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: prefixColor, size: 18) : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 46),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.16), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGold, width: 1.4),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════ ÉCRAN 1 : CONNEXION & CRÉATION DE COMPTE ═══════════════════════════
  Widget _buildLoginScreen({required bool inPhone}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(inPhone ? 18 : 28, 12, inPhone ? 18 : 28, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              SizedBox(
                height: 112,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_float, _pulse]),
                  builder: (context, _) {
                    final dy = math.sin(_float.value * 2 * math.pi) * 5;
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: CustomPaint(
                        size: const Size(106, 106),
                        painter: MoonPainter(illumination: 24, waxing: true, glow: 0.7 + 0.3 * _pulse.value),
                      ),
                    );
                  },
                ),
              ),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(colors: [kGold, Colors.white, kCyan]).createShader(b),
                child: const Text(
                  'WeerWi',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2.8),
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Observatoire scientifique du croissant lunaire',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),

              Glass(
                accent: kGold,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sélecteur : Se connecter | Créer un compte
                    Container(
                      height: 42,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() {
                                _isSignUp = false;
                                _authError = null;
                              }),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: !_isSignUp ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                                ),
                                child: Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    color: !_isSignUp ? kInk : Colors.white70,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() {
                                _isSignUp = true;
                                _authError = null;
                              }),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: _isSignUp ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                                ),
                                child: Text(
                                  'Créer un compte',
                                  style: TextStyle(
                                    color: _isSignUp ? kInk : Colors.white70,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Prénom & Nom uniquement lors de la création de compte
                    if (_isSignUp) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _uniformTextField(
                              controller: _firstNameCtrl,
                              hint: 'Prénom',
                              prefixIcon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _uniformTextField(
                              controller: _lastNameCtrl,
                              hint: 'Nom',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Bascule Téléphone / E-mail
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() {
                              _loginWithPhone = true;
                              _authError = null;
                            }),
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: _loginWithPhone ? kCyan.withOpacity(0.16) : Colors.white.withOpacity(0.04),
                                border: Border.all(color: _loginWithPhone ? kCyan : Colors.white12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.phone_iphone_rounded,
                                      size: 15, color: _loginWithPhone ? kCyan : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Par Téléphone',
                                    style: TextStyle(
                                      color: _loginWithPhone ? kCyan : Colors.white60,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() {
                              _loginWithPhone = false;
                              _authError = null;
                            }),
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: !_loginWithPhone ? kCyan.withOpacity(0.16) : Colors.white.withOpacity(0.04),
                                border: Border.all(color: !_loginWithPhone ? kCyan : Colors.white12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.mail_outline_rounded,
                                      size: 15, color: !_loginWithPhone ? kCyan : Colors.white60),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Par E-mail',
                                    style: TextStyle(
                                      color: !_loginWithPhone ? kCyan : Colors.white60,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (_loginWithPhone) ...[
                      // Sélecteur d'indicatif (46px exact) + Champ numéro (46px exact)
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _modal = _PhoneModal.dialPicker),
                            child: Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: kGold.withOpacity(0.55), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_dialCountry.flag, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 6),
                                  Text(
                                    _dialCountry.dial,
                                    style: const TextStyle(
                                      color: kGold,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.expand_more_rounded, color: Colors.white70, size: 17),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _uniformTextField(
                              controller: _phoneCtrl,
                              hint: 'Numéro (${_dialCountry.name})',
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _uniformTextField(
                        controller: _emailCtrl,
                        hint: 'Adresse e-mail (exemple@email.com)',
                        prefixIcon: Icons.mail_outline_rounded,
                        prefixColor: kCyan,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],

                    const SizedBox(height: 10),
                    _uniformTextField(
                      controller: _passCtrl,
                      hint: _isSignUp ? 'Créer un mot de passe' : 'Mot de passe',
                      prefixIcon: Icons.lock_outline_rounded,
                      prefixColor: kViolet,
                      obscure: _obscurePassword,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: Colors.white54,
                          size: 17,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),

                    if (_authError != null) ...[
                      const SizedBox(height: 8),
                      Text(_authError!, style: const TextStyle(color: kRed, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ],

                    const SizedBox(height: 14),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _authBusy ? null : _submitAuthForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGold,
                          foregroundColor: kInk,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _authBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: kInk),
                              )
                            : Text(
                                _isSignUp ? 'Créer mon compte & Recevoir le code' : 'Se connecter',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white.withOpacity(0.14))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('OU', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ),
                        Expanded(child: Divider(color: Colors.white.withOpacity(0.14))),
                      ],
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _submitAppleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.apple_rounded, size: 20, color: Colors.black),
                        label: const Text(
                          'Continuer avec Apple',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.black),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _continueAsGuest,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                      icon: const Icon(Icons.explore_outlined, size: 15, color: Colors.white70),
                      label: const Text(
                        'Continuer sans créer de compte (Mode Invité)',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════ ÉCRAN 2 : VÉRIFICATION DU CODE OTP (SMS / E-MAIL) ═══════════════════════════
  Widget _buildVerifyOtpScreen({required bool inPhone}) {
    final isSms = _pendingChannel == 'sms';
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: inPhone ? 18 : 28, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              if (_otpPreviewCode != null && _otpPreviewCode!.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _otpCtrl.text = _otpPreviewCode!),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162447),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kGreen.withOpacity(0.75), width: 1.4),
                      boxShadow: [BoxShadow(color: kGreen.withOpacity(0.2), blurRadius: 18)],
                    ),
                    child: Row(
                      children: [
                        Icon(isSms ? Icons.sms_rounded : Icons.mark_email_unread_rounded, color: kGreen, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isSms ? 'Nouveau SMS reçu • WeerWi' : 'Nouvel E-mail reçu • WeerWi',
                                style: const TextStyle(color: kGreen, fontWeight: FontWeight.w900, fontSize: 11.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Code de validation : $_otpPreviewCode (Appuyez pour remplir)',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Glass(
                accent: kGold,
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kGold.withOpacity(0.14),
                        border: Border.all(color: kGold, width: 1.6),
                      ),
                      child: Icon(
                        isSms ? Icons.phonelink_lock_rounded : Icons.verified_rounded,
                        color: kGold,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isSms ? 'Vérification par SMS' : 'Vérification par E-mail',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nous avons envoyé un code à 6 chiffres à :\n${_pendingContact ?? ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••••',
                        hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 10),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    if (_authError != null) ...[
                      const SizedBox(height: 10),
                      Text(_authError!, style: const TextStyle(color: kRed, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _authBusy ? null : _verifyOtpCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGold,
                          foregroundColor: kInk,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text(
                          'Valider le code & Activer mon compte',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _stage = _AppStage.login;
                            _authError = null;
                          }),
                          child: const Text('← Modifier mes infos', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: _authBusy ? null : _resendOtpCode,
                          child: const Text('Renvoyer le code', style: TextStyle(color: kCyan, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════ ÉCRAN 3 : AUTORISATION DE LOCALISATION GPS ═══════════════════════════
  Widget _buildLocationPermissionScreen({required bool inPhone}) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: inPhone ? 20 : 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Glass(
            accent: kCyan,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kCyan.withOpacity(0.14),
                    border: Border.all(color: kCyan.withOpacity(0.6), width: 1.8),
                    boxShadow: [BoxShadow(color: kCyan.withOpacity(0.25), blurRadius: 24)],
                  ),
                  child: const Icon(Icons.my_location_rounded, color: kCyan, size: 36),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Autoriser votre localisation',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                const Text(
                  'WeerWi utilise votre position GPS pour configurer automatiquement l’observatoire lunaire sur votre localité et afficher uniquement les régions de votre pays.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _gpsLoading ? null : _authorizeAndDetectGps,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: kInk,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _gpsLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: kInk),
                          )
                        : const Icon(Icons.location_on_rounded, size: 19),
                    label: Text(
                      _gpsLoading ? 'Détection GPS en cours…' : 'Autoriser la localisation GPS',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _stage = _AppStage.login),
                  child: const Text(
                    '← Retour à l’écran de connexion',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════ MODALES INTÉGRÉES DANS L'ÉCRAN DU TÉLÉPHONE ═══════════════════════════
  Widget _buildInScreenModalOverlay() {
    Widget content;
    switch (_modal) {
      case _PhoneModal.dialPicker:
        content = _buildDialPickerModalCard();
        break;
      case _PhoneModal.profile:
        content = _buildProfileModalCard();
        break;
      case _PhoneModal.bulletin:
        content = _buildBulletinModalCard();
        break;
      case _PhoneModal.guestRestriction:
        content = _buildGuestRestrictionModalCard();
        break;
      case _PhoneModal.none:
        return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _modal = _PhoneModal.none),
        child: Container(
          color: Colors.black.withOpacity(0.72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {}, // Empêche la fermeture au clic sur la carte
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialPickerModalCard() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 540),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101432),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kGold.withOpacity(0.5), width: 1.4),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.public_rounded, color: kGold, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Indicatif Pays (Afrique de l’Ouest)',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _modal = _PhoneModal.none),
                icon: const Icon(Icons.cancel_rounded, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const Divider(height: 12, color: Colors.white12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: kWestAfricaDialCodes.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.06)),
              itemBuilder: (context, i) {
                final item = kWestAfricaDialCodes[i];
                final sel = item.code == _dialCountry.code;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    setState(() {
                      _dialCountry = item;
                      _modal = _PhoneModal.none;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: sel ? kGold.withOpacity(0.18) : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Text(item.flag, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.name,
                            style: TextStyle(
                              color: sel ? kGold : Colors.white,
                              fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          item.dial,
                          style: TextStyle(
                            color: sel ? kGold : kCyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
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
      ),
    );
  }

  Widget _buildProfileModalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101432),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kGold.withOpacity(0.5), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF252D63), Color(0xFF121636)]),
                  border: Border.all(color: kGold, width: 1.8),
                ),
                child: const Icon(Icons.person_rounded, color: kGold, size: 32),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGreen,
                    border: Border.all(color: const Color(0xFF101432), width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _userFullName ?? 'Compte connecté',
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            _maskedIdentity(_authIdentity),
            style: const TextStyle(color: Colors.white60, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.my_location_rounded, color: kCyan, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zone GPS : ${_city.flag} ${_city.name} (${_city.country})',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _modal = _PhoneModal.none),
                  child: const Text('Fermer', style: TextStyle(color: Colors.white70)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kRed.withOpacity(0.2),
                    foregroundColor: kRed,
                    side: BorderSide(color: kRed.withOpacity(0.6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    try {
                      FirebaseAuth.instance.signOut();
                    } catch (_) {}
                    setState(() {
                      _modal = _PhoneModal.none;
                      _authIdentity = null;
                      _userFullName = null;
                      _isGuest = false;
                      _stage = _AppStage.login;
                    });
                  },
                  icon: const Icon(Icons.logout_rounded, size: 15),
                  label: const Text('Déconnexion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuestRestrictionModalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101432),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kGold.withOpacity(0.5), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kGold.withOpacity(0.14),
              border: Border.all(color: kGold),
            ),
            child: const Icon(Icons.lock_person_rounded, color: kGold, size: 28),
          ),
          const SizedBox(height: 12),
          const Text(
            'Réservé aux membres inscrits',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            'En mode Invité, vous avez accès librement à l’observatoire du soir, à la boussole, au calendrier et aux régions de votre pays.\n\n'
            'L’export du Bulletin Scientifique Officiel PDF certifié nécessite la création gratuite d’un compte WeerWi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _modal = _PhoneModal.none),
                  child: const Text('Plus tard', style: TextStyle(color: Colors.white60)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: kInk,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() {
                      _modal = _PhoneModal.none;
                      _isSignUp = true;
                      _stage = _AppStage.login;
                    });
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                  label: const Text('Créer un compte', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulletinModalCard() {
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

🏆 Point Sentinelle (${_city.country}) : ${sen['name'] ?? _city.name} (${sen['region'] ?? ''}) — Odeh V = ${sen['odeh_v'] ?? '—'}
📌 Synthèse : ${d?['observation_tip'] ?? ''}
🕌 Contexte : ${d?['ramadan_status'] ?? ''}
(Source : WeerWi • Éphémérides NASA JPL DE421 • Critères de Yallop & Odeh)''';

    return Container(
      constraints: const BoxConstraints(maxHeight: 560),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101432),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kGold.withOpacity(0.5), width: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: kGold, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Bulletin Scientifique Officiel',
                  style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _modal = _PhoneModal.none),
                icon: const Icon(Icons.cancel_rounded, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: SelectableText(
                  reportText,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.45),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCyan,
                    foregroundColor: kInk,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien du Bulletin PDF copié !')),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 15),
                  label: const Text('Lien PDF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: kInk,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: reportText));
                    setState(() => _modal = _PhoneModal.none);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('📋 Bulletin copié pour WhatsApp !')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copier texte', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════ ÉCRAN 4 : OBSERVATOIRE DU PAYS DÉTECTÉ ═══════════════════════════
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
      (3, Icons.map_rounded, 'Régions'),
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
                  onTap: () => _switchTab(item.$1),
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
      controller: _mainScrollCtrl,
      padding: EdgeInsets.fromLTRB(inPhone ? 14 : 18, 10, inPhone ? 14 : 18, inPhone ? 44 : 210),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildLocationAndToolsBar(),
              const SizedBox(height: 12),
              _buildLocalCountryCitiesBar(),
              if (!inPhone) ...[
                const SizedBox(height: 16),
                _buildNavigationTabs(),
              ],
              const SizedBox(height: 16),
              if (_tab == 0) _buildEveningTab(),
              if (_tab == 1) _buildCalendarTab(),
              if (_tab == 2) _buildHilalTab(),
              if (_tab == 3) _buildRegionsTab(),
              const SizedBox(height: 24),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFFFFF4C2), kGoldDeep]),
            boxShadow: [BoxShadow(color: kGold.withOpacity(0.55), blurRadius: 16, spreadRadius: 1)],
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
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2),
                ),
              ),
              Text(
                '${_city.flag} Observatoire national • ${_city.country}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
        if (_isGuest)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _stage = _AppStage.login),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kGold.withOpacity(0.55)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1_rounded, size: 14, color: kGold),
                  SizedBox(width: 5),
                  Text(
                    'Invité • Connexion',
                    style: TextStyle(color: kGold, fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          )
        else
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => _modal = _PhoneModal.profile),
            child: Tooltip(
              message: 'Mon profil',
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF22295A), Color(0xFF121636)],
                        ),
                        border: Border.all(color: kGold.withOpacity(0.55), width: 1.4),
                        boxShadow: [BoxShadow(color: kGold.withOpacity(0.18), blurRadius: 12)],
                      ),
                      child: const Icon(Icons.person_rounded, color: kGold, size: 20),
                    ),
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kGreen,
                          border: Border.all(color: const Color(0xFF0A0D22), width: 2),
                          boxShadow: [BoxShadow(color: kGreen.withOpacity(0.8), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _maskedIdentity(String? raw) {
    if (raw == null || raw.isEmpty) return 'Session active';
    if (raw == 'Compte Apple') return 'Identifiant Apple vérifié';
    if (raw.contains('@')) {
      final parts = raw.split('@');
      final u = parts.first;
      final visible = u.length <= 2 ? u : '${u.substring(0, 2)}••••';
      return '$visible@${parts.last}';
    }
    if (raw.length > 6) {
      return '${raw.substring(0, 4)} ••• •• ${raw.substring(raw.length - 2)}';
    }
    return 'Compte vérifié';
  }

  Widget _buildLocationAndToolsBar() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _gpsLoading ? null : _authorizeAndDetectGps,
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
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: kCyan))
                  else
                    const Icon(Icons.my_location_rounded, size: 13, color: kCyan),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'GPS : ${_city.name} (${_city.country})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kCyan, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _modal = _isGuest ? _PhoneModal.guestRestriction : _PhoneModal.bulletin),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kViolet.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kViolet.withOpacity(0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_isGuest ? Icons.lock_outline_rounded : Icons.picture_as_pdf_rounded, size: 13, color: kViolet),
                const SizedBox(width: 5),
                const Text(
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

  Widget _buildLocalCountryCitiesBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'LOCALITÉS DE VOTRE PAYS • ${_city.country.toUpperCase()} (${_city.flag})',
          icon: Icons.place_rounded,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _countryCities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _countryCities[i];
              final sel = c.name == _city.name;
              return InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => _selectCity(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
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
                  child: Text(
                    c.name,
                    style: TextStyle(
                      color: sel ? kInk : Colors.white,
                      fontWeight: sel ? FontWeight.w900 : FontWeight.w500,
                      fontSize: 12,
                    ),
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
      (3, Icons.map_rounded, 'Régions'),
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
              onTap: () => _switchTab(item.$1),
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
              height: 236,
              child: AnimatedBuilder(
                animation: Listenable.merge([_float, _orbit, _pulse]),
                builder: (context, _) {
                  final dy = math.sin(_float.value * 2 * math.pi) * 6;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(size: const Size(320, 236), painter: OrbitPainter(_orbit.value)),
                      Transform.translate(
                        offset: Offset(0, dy),
                        child: CustomPaint(
                          size: const Size(176, 176),
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
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                shadows: [Shadow(color: kGold, blurRadius: 18)],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_city.flag}  ${_city.name}, ${_city.country}  •  ${frDate(_date, weekday: true)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                        style: TextStyle(color: badgeCol, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1.0),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _buildDateControlBar(),
        if (_errorEvening != null) ...[
          const SizedBox(height: 14),
          ErrorBlock(_errorEvening!, onRetry: _loadEvening),
        ],
        if (d != null && !_loadingEvening) ...[
          const SizedBox(height: 14),
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
                size: const Size(110, 110),
                painter: CompassPainter(moonAz: moonAz, sunAz: sunAz, moonAlt: moonAlt),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direction Lune : ${moonAz.toStringAsFixed(1)}° ($cardinal)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
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
                      style: const TextStyle(color: Colors.white60, fontSize: 11.5),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
            onPressed: () {
              setState(() => _date = _date.subtract(const Duration(days: 1)));
              _loadEvening();
            },
            icon: const Icon(Icons.chevron_left_rounded, color: kGold),
          ),
          Expanded(
            child: InkWell(
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.event_rounded, color: kGold, size: 15),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        frDate(_date),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
            onPressed: () {
              setState(() => _date = _date.add(const Duration(days: 1)));
              _loadEvening();
            },
            icon: const Icon(Icons.chevron_right_rounded, color: kGold),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() => _date = DateTime.now());
              _loadEvening();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: kCyan.withOpacity(0.14),
                border: Border.all(color: kCyan.withOpacity(0.45)),
              ),
              child: const Text(
                "Aujourd'hui",
                style: TextStyle(color: kCyan, fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Grille 2×2 parfaitement symétrique pour les 4 éphémérides du soir
  Widget _buildSunMoonTimesBar(Map<String, dynamic> d) {
    final sunset = (d['sunset'] as String?) ?? '—';
    final moonset = (d['moonset'] as String?) ?? '—';
    final moonriseTonight = d['moonrise_tonight'] as String?;
    final lag = d['lag_minutes'] as num?;
    final presence = (d['moon_presence'] as String?) ?? '';
    final presentTonight = (d['present_tonight'] as bool?) ?? false;

    String thirdLabel;
    String thirdValue;
    Color thirdColor;
    IconData thirdIcon;
    if (lag != null && lag > 0) {
      thirdLabel = 'Décalage (Lag)';
      thirdValue = '+$lag min';
      thirdColor = kGreen;
      thirdIcon = Icons.timelapse_rounded;
    } else if (moonriseTonight != null) {
      thirdLabel = 'Lever Lune (Nuit)';
      thirdValue = moonriseTonight;
      thirdColor = kGold;
      thirdIcon = Icons.light_mode_rounded;
    } else {
      thirdLabel = 'Au coucher Soleil';
      thirdValue = 'Sous l’horizon';
      thirdColor = kOrange;
      thirdIcon = Icons.timelapse_rounded;
    }

    return Glass(
      accent: kCyan,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('ÉPHÉMÉRIDES DU CRÉPUSCULE & DE LA NUIT', icon: Icons.schedule_rounded, color: kCyan),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _timeStat(Icons.wb_twilight_rounded, 'Coucher Soleil', sunset, kGold)),
              const SizedBox(width: 10),
              Expanded(child: _timeStat(Icons.nights_stay_rounded, 'Coucher Lune', moonset, kCyan)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _timeStat(thirdIcon, thirdLabel, thirdValue, thirdColor)),
              const SizedBox(width: 10),
              Expanded(
                child: _timeStat(
                  presentTonight ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
                  'Présence Nuit',
                  presentTonight ? 'Présente' : 'Absente',
                  presentTonight ? kGreen : kRed,
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ],
            ),
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
          SectionTitle('DIAGNOSTIC SCIENTIFIQUE DE L’OBSERVATOIRE', icon: Icons.auto_awesome_rounded, color: col),
          const SizedBox(height: 8),
          Text(tip, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.45)),
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

    // Si la hauteur est négative (sous l'horizon), jauge orange/rouge avec faible arc
    final altFraction = alt > 0 ? (alt / 90.0).clamp(0.05, 1.0) : 0.06;
    final altColor = alt > 0 ? kGreen : kOrange;
    final altUnit = alt > 0 ? 'degrés' : 'sous horizon';

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Gauge('ILLUMINATION', illum.toStringAsFixed(1), '%', illum / 100, kGold, Icons.light_mode_rounded),
        Gauge('ÉLONGATION', elong.toStringAsFixed(1), 'degrés', elong / 180, kCyan, Icons.architecture_rounded),
        Gauge('HAUTEUR', '${alt.toStringAsFixed(1)}°', altUnit, altFraction, altColor, Icons.height_rounded),
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
                      '${_city.flag} ${_city.name} (${_city.country}) • Présence nocturne & phases',
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

  /// Carte de détail du jour sélectionné (sans aucun débordement horizontal)
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CustomPaint(
                size: const Size(42, 42),
                painter: MoonPainter(
                  illumination: toD(d['illumination']) ?? 0,
                  waxing: (d['waxing'] as bool?) ?? true,
                  mini: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dtParsed != null ? frDate(dtParsed, weekday: true) : dateIso,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d['phase']} (${d['illumination']}%) • ${d['hijri_estimate']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                    ),
                  ],
                ),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: dtParsed == null
                  ? null
                  : () {
                      setState(() => _date = dtParsed);
                      _switchTab(0);
                      _loadEvening();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: kInk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.visibility_rounded, size: 16),
              label: const Text('Observer cette soirée dans l’Observatoire',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Grille 2×2 symétrique pour le choix du mois sacré ───────────────────────────
  Widget _buildSacredMonthGrid({required int selectedMonth, required ValueChanged<int> onSelect}) {
    const items = [
      (9, Icons.mosque_rounded, 'Ramadan'),
      (10, Icons.nightlight_round, 'Chawwal (Korité)'),
      (12, Icons.star_rounded, 'Dhou al-Hijja (Tabaski)'),
      (0, Icons.travel_explore_rounded, 'Prochain Hilal'),
    ];
    Widget pill((int, IconData, String) s) {
      final sel = selectedMonth == s.$1;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelect(s.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
              color: sel ? null : const Color(0xFF14183A).withOpacity(0.85),
              border: Border.all(color: sel ? kGold : Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(s.$2, size: 14, color: sel ? kInk : kGold),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    s.$3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: sel ? kInk : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [pill(items[0]), const SizedBox(width: 8), pill(items[1])]),
        const SizedBox(height: 8),
        Row(children: [pill(items[2]), const SizedBox(width: 8), pill(items[3])]),
      ],
    );
  }

  // ═══════════════════════════ ONGLET 2 : HILAL & RAMADAN ═══════════════════════════
  Widget _buildHilalTab() {
    final h = _hilalData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSacredMonthGrid(
          selectedMonth: _targetHijriMonth,
          onSelect: (m) {
            setState(() => _targetHijriMonth = m);
            _loadHilal();
          },
        ),
        if (_errorHilal != null) ...[
          const SizedBox(height: 14),
          ErrorBlock(_errorHilal!, onRetry: _loadHilal),
        ],
        if (_loadingHilal)
          LoadingBlock('Simulation astronomique pour ${_city.country}…')
        else if (h != null) ...[
          const SizedBox(height: 16),
          _buildConjunctionBanner(h),
          const SizedBox(height: 16),
          _buildCityEveningsDetail(h),
          const SizedBox(height: 16),
          _buildNationalCitiesComparisonTable(h),
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
          SectionTitle('DÉBUT DE ${hMonth.toString().toUpperCase()} $hYear H • ${_city.name.toUpperCase()} (${_city.country.toUpperCase()})',
              icon: Icons.mosque_rounded, color: kGold),
          const SizedBox(height: 10),
          Text(
            'Conjonction exacte (Nouvelle Lune) : ${h['conjunction_label']}',
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _startCard(
            '1er $hMonth (Visibilité à l’œil nu)',
            (loc['start_naked_eye_label'] as String?) ?? '—',
            'Critère scientifique à l’œil nu (Odeh Zone A)',
            kGreen,
            Icons.visibility_rounded,
          ),
          const SizedBox(height: 10),
          _startCard(
            '1er $hMonth (Avec instruments optiques)',
            (loc['start_with_instruments_label'] as String?) ?? '—',
            'Si l’observation aux jumelles / télescope est retenue',
            kCyan,
            Icons.biotech_rounded,
          ),
        ],
      ),
    );
  }

  Widget _startCard(String title, String dateLabel, String subtitle, Color col, IconData icon) {
    return Container(
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
                const SizedBox(height: 2),
                Text(dateLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
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

  Widget _buildNationalCitiesComparisonTable(Map<String, dynamic> h) {
    final cities = ((h['cities'] as List?) ?? []).cast<Map<String, dynamic>>();
    final evHeaders = ((h['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Glass(
      accent: kViolet,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('SYNTHÈSE NATIONALE • VILLES DE ${_city.country.toUpperCase()} (${_city.flag})',
              icon: Icons.location_city_rounded, color: kViolet),
          const SizedBox(height: 10),
          ...cities.map((c) {
            final evs = ((c['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();
            final regLabel = (c['region'] as String?)?.isNotEmpty == true ? ' (${c['region']})' : '';
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
                        '${c['flag']}  ${c['name']}$regLabel',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Pill('1er jour : ${c['start_naked_eye_label']}', kGreen),
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

  // ═══════════════════════════ ONGLET 3 : RÉGIONS DU PAYS DE L'UTILISATEUR UNIQUEMENT ═══════════════════════════
  Widget _buildRegionsTab() {
    final r = _regionsData;
    final eveningsList = ((r?['evenings'] as List?) ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          accent: kCyan,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'OBSERVATOIRE DES RÉGIONS • ${_city.country.toUpperCase()} (${_city.flag})',
                icon: Icons.map_rounded,
                color: kCyan,
              ),
              const SizedBox(height: 10),
              _buildSacredMonthGrid(
                selectedMonth: _regionHijriMonth,
                onSelect: (m) {
                  setState(() => _regionHijriMonth = m);
                  _loadRegions();
                },
              ),
              if (eveningsList.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Soirée après la conjonction :', style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(eveningsList.length, (i) {
                    final ev = eveningsList[i];
                    final idx = (ev['index'] as int?) ?? i;
                    final sel = _regionDayOffset == idx;
                    final dateShort = ((ev['date'] as String?) ?? '').length >= 10
                        ? (ev['date'] as String).substring(5)
                        : (ev['date'] as String? ?? '');
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() => _regionDayOffset = idx);
                            _loadRegions();
                          },
                          child: Container(
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: sel ? const LinearGradient(colors: [kGoldDeep, kGold]) : null,
                              color: sel ? null : Colors.white.withOpacity(0.05),
                              border: Border.all(color: sel ? kGold : Colors.white24),
                            ),
                            child: Text(
                              'Soir ${idx + 1} ($dateShort)',
                              style: TextStyle(
                                color: sel ? kInk : Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
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
          LoadingBlock('Scan astronomique des régions de ${_city.country}…')
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
          SectionTitle('RÈGLE D’OR ASTRONOMIQUE & POINT SENTINELLE (${_city.country.toUpperCase()})',
              icon: Icons.emoji_events_rounded, color: col),
          const SizedBox(height: 8),
          Text(
            (r['rule_title'] as String?) ?? '',
            style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.w900),
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
                        style: const TextStyle(color: kGold, fontWeight: FontWeight.w900, fontSize: 13),
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
            style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.45),
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
    final flag = (r['flag'] as String?) ?? _city.flag;
    final cname = ((r['country_name'] as String?) ?? _city.country).split(' (').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('RÉGIONS & LOCALITÉS DE VOTRE PAYS ($flag $cname)',
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14.5),
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
                            cname,
                            flag,
                            toD(l['lat']) ?? _city.lat,
                            toD(l['lon']) ?? _city.lon,
                            toD(l['tz']) ?? _city.tz,
                            _city.countryCode,
                            (reg['region'] as String?) ?? '',
                          );
                          final parsedDate = DateTime.tryParse((r['date'] as String?) ?? '');
                          setState(() {
                            _city = chosen;
                            if (parsedDate != null) _date = parsedDate;
                          });
                          _switchTab(0);
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

  Widget _buildFooter() {
    return Column(
      children: [
        Text('✦  ✦  ✦', style: TextStyle(color: kGold.withOpacity(0.6), letterSpacing: 6)),
        const SizedBox(height: 6),
        Text(
          'WeerWi • Observatoire astronomique national (${_city.country})',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        const Text(
          'Éphémérides NASA JPL DE421 · Critères de Yallop (1997) & Odeh (2004) · Météo Open-Meteo',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }
}
