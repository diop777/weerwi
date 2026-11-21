import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase info: $e");
  }
  runApp(const WeerWiApp());
}

class WeerWiApp extends StatelessWidget {
  const WeerWiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeerWi • Observatoire Lunaire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: const Color(0xFF090B14),
        cardColor: const Color(0xFF13182C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD54F),
          secondary: Color(0xFF64FFDA),
          surface: Color(0xFF13182C),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class WestAfricanCity {
  final String name;
  final String country;
  final String flag;
  final double lat;
  final double lon;

  const WestAfricanCity({
    required this.name,
    required this.country,
    required this.flag,
    required this.lat,
    required this.lon,
  });
}

const List<WestAfricanCity> kCities = [
  WestAfricanCity(name: 'Dakar', country: 'Sénégal', flag: '🇸🇳', lat: 14.6937, lon: -17.4441),
  WestAfricanCity(name: 'Touba', country: 'Sénégal', flag: '🇸🇳', lat: 14.8647, lon: -15.8756),
  WestAfricanCity(name: 'Bamako', country: 'Mali', flag: '🇲🇱', lat: 12.6392, lon: -8.0029),
  WestAfricanCity(name: 'Abidjan', country: "Côte d'Ivoire", flag: '🇨🇮', lat: 5.3600, lon: -4.0083),
  WestAfricanCity(name: 'Ouagadougou', country: 'Burkina Faso', flag: '🇧🇫', lat: 12.3714, lon: -1.5197),
  WestAfricanCity(name: 'Niamey', country: 'Niger', flag: '🇳🇪', lat: 13.5116, lon: 2.1254),
  WestAfricanCity(name: 'Conakry', country: 'Guinée', flag: '🇬🇳', lat: 9.6412, lon: -13.5784),
  WestAfricanCity(name: 'Nouakchott', country: 'Mauritanie', flag: '🇲🇷', lat: 18.0735, lon: -15.9582),
  WestAfricanCity(name: 'Banjul', country: 'Gambie', flag: '🇬🇲', lat: 13.4549, lon: -16.5790),
  WestAfricanCity(name: 'Lomé', country: 'Togo', flag: '🇹🇬', lat: 6.1375, lon: 1.2125),
  WestAfricanCity(name: 'Cotonou', country: 'Bénin', flag: '🇧🇯', lat: 6.3654, lon: 2.4183),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WestAfricanCity _selectedCity = kCities[0];
  late TextEditingController _latController;
  late TextEditingController _lonController;
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController(text: _selectedCity.lat.toString());
    _lonController = TextEditingController(text: _selectedCity.lon.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMoon());
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  void _selectCity(WestAfricanCity city) {
    setState(() {
      _selectedCity = city;
      _latController.text = city.lat.toString();
      _lonController.text = city.lon.toString();
    });
    _fetchMoon();
  }

  Future<void> _fetchMoon() async {
    final lat = double.tryParse(_latController.text);
    final lon = double.tryParse(_lonController.text);
    if (lat == null || lon == null) {
      setState(() => _errorMessage = "Coordonnées GPS invalides.");
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final dateStr = "${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      final uri = Uri.parse('/moon'); // Same origin host
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': lat,
              'longitude': lon,
              'date': dateStr,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _result = jsonDecode(response.body);
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = "Erreur serveur (${response.statusCode}) : ${response.body}";
        });
      }
    } catch (e) {
      // Fallback localhost:8000 si exécuté hors navigateur ou port différent
      try {
        final dateStr = "${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
        final uriFallback = Uri.parse('http://localhost:8000/moon');
        final response = await http
            .post(
              uriFallback,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'latitude': lat,
                'longitude': lon,
                'date': dateStr,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          setState(() {
            _result = jsonDecode(response.body);
            _errorMessage = null;
          });
        } else {
          setState(() => _errorMessage = "Erreur : ${response.statusCode}");
        }
      } catch (e2) {
        setState(() => _errorMessage = "Connexion au serveur impossible : $e2");
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Arrière-plan animé ciel étoilé
          const StarryBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 850),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header somptueux
                      _buildHeader(),
                      const SizedBox(height: 20),

                      // Bandeau Villes d'Afrique de l'Ouest
                      _buildCitySelector(),
                      const SizedBox(height: 16),

                      // Contrôles Date & Recherche
                      _buildControlPanel(),
                      const SizedBox(height: 20),

                      // Message d'erreur s'il y a lieu
                      if (_errorMessage != null) _buildErrorCard(),

                      // Indicateur de chargement
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(color: Color(0xFFFFD54F)),
                                SizedBox(height: 16),
                                Text(
                                  "Calculs astronomiques Skyfield & NASA en cours...",
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                )
                              ],
                            ),
                          ),
                        ),

                      // Résultats Visuels
                      if (_result != null && !_loading) ...[
                        _buildMoonCard(_result!),
                        const SizedBox(height: 20),
                        _buildRamadanCard(_result!),
                        const SizedBox(height: 20),
                        _buildMetricsGrid(_result!),
                      ],

                      const SizedBox(height: 40),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF181D38).withOpacity(0.9),
            const Color(0xFF0F1224).withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD54F).withOpacity(0.08),
            blurRadius: 30,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFFFE082), Color(0xFFFFB300)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB300).withOpacity(0.4),
                  blurRadius: 16,
                  spreadRadius: 3,
                )
              ],
            ),
            child: const Icon(Icons.nightlight_round, color: Color(0xFF0E111E), size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'WeerWi',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD54F).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'وِيرْ وِي • ASTRONOMIE',
                        style: TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Observatoire Scientifique & Visibilité du Croissant Lunaire (Afrique de l’Ouest)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            "🌍 CHOISIR UNE VILLE D'AFRIQUE DE L'OUEST :",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD54F),
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kCities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final city = kCities[index];
              final isSelected = city.name == _selectedCity.name;
              return InkWell(
                onTap: () => _selectCity(city),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFD54F)
                        : const Color(0xFF141930).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFFD54F)
                          : Colors.white12,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFFD54F).withOpacity(0.3),
                              blurRadius: 10,
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(city.flag, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        city.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF0C0F1D) : Colors.white,
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

  Widget _buildControlPanel() {
    final dateDisplay =
        "${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12162B).withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFFFFD54F),
                              onPrimary: Color(0xFF0C0F1D),
                              surface: Color(0xFF161B33),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _fetchMoon();
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191F3B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: Color(0xFFFFD54F), size: 18),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Date d'observation", style: TextStyle(color: Colors.white54, fontSize: 10)),
                            Text(dateDisplay, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _selectedDate = DateTime.now());
                  _fetchMoon();
                },
                icon: const Icon(Icons.today, size: 16),
                label: const Text("Aujourd'hui"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22294E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "Latitude (${_selectedCity.name})",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF191F3B),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lonController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "Longitude (${_selectedCity.name})",
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF191F3B),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _loading ? null : _fetchMoon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD54F),
                  foregroundColor: const Color(0xFF0C0F1D),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 6,
                ),
                child: const Text("Calculer", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoonCard(Map<String, dynamic> data) {
    final bool isVisible = data['visible'] ?? false;
    final String phase = data['phase'] ?? 'Non déterminée';
    final double illumination = (data['illumination'] as num?)?.toDouble() ?? 0.0;
    final double age = (data['age_days'] as num?)?.toDouble() ?? 0.0;
    final String tip = data['observation_tip'] ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isVisible
              ? [const Color(0xFF0F261F), const Color(0xFF131D2F)]
              : [const Color(0xFF261A14), const Color(0xFF16192E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isVisible ? const Color(0xFF00E676).withOpacity(0.5) : const Color(0xFFFF9100).withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isVisible ? const Color(0xFF00E676).withOpacity(0.12) : const Color(0xFFFF9100).withOpacity(0.1),
            blurRadius: 24,
            spreadRadius: 2,
          )
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Visualiseur dynamique de la lune
              CustomPaint(
                size: const Size(90, 90),
                painter: MoonPhasePainter(illumination: illumination),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isVisible ? const Color(0xFF00E676).withOpacity(0.2) : const Color(0xFFFF9100).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isVisible ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVisible ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: isVisible ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isVisible ? 'CROISSANT VISIBLE À L’ŒIL NU' : 'NON VISIBLE À L’ŒIL NU CE SOIR',
                            style: TextStyle(
                              color: isVisible ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      phase,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Âge de la lune : ${age.toStringAsFixed(1)} jours après la nouvelle lune",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.wb_twilight_rounded, color: Color(0xFFFFD54F), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRamadanCard(Map<String, dynamic> data) {
    final String ramadan = data['ramadan_status'] ?? 'Observation normale';
    final double? cloud = (data['cloud_cover'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1A38), Color(0xFF141933)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9FA8DA).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.mosque_rounded, color: Color(0xFFFFD54F), size: 22),
              SizedBox(width: 10),
              Text(
                "CONTEXTE DU MOIS LUNAIRE & DÉBUT DU RAMADAN",
                style: TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ramadan,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1327),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_queue_rounded, color: Color(0xFF81D4FA), size: 22),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Météo (ciel au crépuscule)", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          Text(
                            cloud != null ? "${cloud.toStringAsFixed(0)}% de nuages" : "Météo calculée",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1327),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFFA7FFEB), size: 22),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Critère scientifique", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const Text(
                            "Yallop & Danjon",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(Map<String, dynamic> data) {
    final double illum = (data['illumination'] as num?)?.toDouble() ?? 0.0;
    final double elong = (data['elongation_deg'] as num?)?.toDouble() ?? 0.0;
    final double alt = (data['altitude_deg'] as num?)?.toDouble() ?? 0.0;
    final double age = (data['age_days'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            "DONNÉES ASTRONOMIQUES EXACTES (NASA EPHEMERIS DE421) :",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white60,
              letterSpacing: 1,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.25,
          children: [
            _buildMetricBox("Illumination", "${illum.toStringAsFixed(1)}%", Icons.light_mode_rounded, const Color(0xFFFFD54F)),
            _buildMetricBox("Élongation", "${elong.toStringAsFixed(1)}°", Icons.architecture_rounded, const Color(0xFF80D8FF)),
            _buildMetricBox("Hauteur (Horizon)", "${alt.toStringAsFixed(1)}°", Icons.height_rounded, const Color(0xFFA7FFEB)),
            _buildMetricBox("Âge Conjonction", "${age.toStringAsFixed(1)} j", Icons.timer_rounded, const Color(0xFFFFAB91)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13172E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF33141E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const Center(
      child: Column(
        children: [
          Text(
            "WeerWi • Conçu pour lever toute confusion lors de la recherche du croissant de lune.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          SizedBox(height: 4),
          Text(
            "Données basées sur les éphémérides DE421 de la NASA et les prévisions Open-Meteo.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// Dessinateur de la lune
class MoonPhasePainter extends CustomPainter {
  final double illumination;

  MoonPhasePainter({required this.illumination});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Halo lumineux
    final glowPaint = Paint()
      ..color = const Color(0xFFFFD54F).withOpacity(0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius + 4, glowPaint);

    // Disque sombre de la lune (ombre)
    final darkPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF1E2540), const Color(0xFF0F1322)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, darkPaint);

    // Partie éclairée de la lune
    if (illumination > 1) {
      final brightPaint = Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFFF9C4), const Color(0xFFFFD54F)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      // Arc de cercle éclairé
      final path = Path();
      path.addArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, math.pi);
      
      // Facteur d'ellipse pour la phase
      final phaseRatio = (illumination - 50.0) / 50.0;
      final sweepDirection = phaseRatio >= 0;
      final controlX = radius * phaseRatio.abs();

      final ovalRect = Rect.fromCenter(
        center: center,
        width: controlX * 2,
        height: radius * 2,
      );

      if (sweepDirection) {
        path.arcTo(ovalRect, math.pi / 2, math.pi, false);
      } else {
        path.arcTo(ovalRect, math.pi / 2, -math.pi, false);
      }
      path.close();

      canvas.drawPath(path, brightPaint);
    }

    // Bordure fine élégante
    final strokePaint = Paint()
      ..color = const Color(0xFFFFD54F).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius, strokePaint);
  }

  @override
  bool shouldRepaint(covariant MoonPhasePainter oldDelegate) {
    return oldDelegate.illumination != illumination;
  }
}

// Ciel étoilé subtil
class StarryBackground extends StatelessWidget {
  const StarryBackground({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF080B17), Color(0xFF0E1226), Color(0xFF090C1A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}
