import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase non encore initialisé: $e");
  }
  runApp(const WeerWiApp());
}

class WeerWiApp extends StatelessWidget {
  const WeerWiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeerWi - Suivi Lunaire & Ramadan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0F1123),
        cardColor: const Color(0xFF1E223D),
        colorScheme: ColorScheme.dark(
          primary: Colors.amberAccent,
          secondary: Colors.tealAccent,
          surface: const Color(0xFF1E223D),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
        ),
      ),
      home: const MoonScreen(),
    );
  }
}

class WestAfricanCity {
  final String name;
  final String country;
  final double lat;
  final double lon;

  const WestAfricanCity({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
  });
}

const List<WestAfricanCity> kCities = [
  WestAfricanCity(name: 'Dakar', country: 'Sénégal', lat: 14.6937, lon: -17.4441),
  WestAfricanCity(name: 'Bamako', country: 'Mali', lat: 12.6392, lon: -8.0029),
  WestAfricanCity(name: 'Abidjan', country: "Côte d'Ivoire", lat: 5.3600, lon: -4.0083),
  WestAfricanCity(name: 'Ouagadougou', country: 'Burkina Faso', lat: 12.3714, lon: -1.5197),
  WestAfricanCity(name: 'Niamey', country: 'Niger', lat: 13.5116, lon: 2.1254),
  WestAfricanCity(name: 'Conakry', country: 'Guinée', lat: 9.6412, lon: -13.5784),
  WestAfricanCity(name: 'Nouakchott', country: 'Mauritanie', lat: 18.0735, lon: -15.9582),
  WestAfricanCity(name: 'Banjul', country: 'Gambie', lat: 13.4549, lon: -16.5790),
  WestAfricanCity(name: 'Lomé', country: 'Togo', lat: 6.1375, lon: 1.2125),
  WestAfricanCity(name: 'Cotonou', country: 'Bénin', lat: 6.3654, lon: 2.4183),
];

class MoonScreen extends StatefulWidget {
  const MoonScreen({Key? key}) : super(key: key);

  @override
  State<MoonScreen> createState() => _MoonScreenState();
}

class _MoonScreenState extends State<MoonScreen> {
  WestAfricanCity _selectedCity = kCities[0]; // Dakar par défaut
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
    // Auto fetch pour aujourd'hui
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMoon());
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  void _onCityChanged(WestAfricanCity city) {
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
      setState(() => _errorMessage = "Coordonnées invalides");
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('http://localhost:8000/moon');
      final dateStr = _selectedDate.toIso8601String().split('T').first;
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
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        setState(() => _result = jsonDecode(response.body));
      } else {
        setState(() => _errorMessage = "Erreur serveur : ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Impossible de joindre le serveur API (port 8000).\nVérifiez que le backend est démarré.";
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = "${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}";

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.nightlight_round, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text('WeerWi • Suivi Lunaire'),
          ],
        ),
        backgroundColor: const Color(0xFF141830),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sélecteur de ville
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🌍 Zone d’observation (Afrique de l’Ouest)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WestAfricanCity>(
                      value: _selectedCity,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF252B4D),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF141830),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: kCities.map((city) {
                        return DropdownMenuItem(
                          value: city,
                          child: Text("${city.name} (${city.country})"),
                        );
                      }).toList(),
                      onChanged: (city) {
                        if (city != null) _onCityChanged(city);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _latController,
                            decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _lonController,
                            decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Sélecteur de date
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.calendar_month, color: Colors.amberAccent),
                title: const Text('Date d’observation'),
                subtitle: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: ElevatedButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Changer'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _fetchMoon();
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.search, color: Colors.black),
              label: Text(
                _loading ? 'Calculs astronomiques en cours...' : 'Calculer la visibilité du croissant',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _loading ? null : _fetchMoon,
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  border: Border.all(color: Colors.redAccent),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 20),
              _buildResultCard(_result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> data) {
    final bool isVisible = data['visible'] ?? false;
    final String phase = data['phase'] ?? 'Inconnu';
    final double illumination = (data['illumination'] as num?)?.toDouble() ?? 0.0;
    final double age = (data['age_days'] as num?)?.toDouble() ?? 0.0;
    final double elongation = (data['elongation_deg'] as num?)?.toDouble() ?? 0.0;
    final double altitude = (data['altitude_deg'] as num?)?.toDouble() ?? 0.0;
    final double? cloud = (data['cloud_cover'] as num?)?.toDouble();
    final String? tip = data['observation_tip'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: const Color(0xFF1E223D),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phase,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text("Âge : ${age.toStringAsFixed(1)} jours après conjonction"),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isVisible ? Colors.green.withOpacity(0.25) : Colors.orange.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isVisible ? Colors.greenAccent : Colors.orangeAccent),
                  ),
                  child: Text(
                    isVisible ? 'VISIBLE' : 'NON VISIBLE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isVisible ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 28, color: Colors.white24),

            // Métriques astronomiques
            Row(
              children: [
                _metricTile('Illumination', '${illumination.toStringAsFixed(1)}%', Icons.light_mode),
                _metricTile('Élongation', '${elongation.toStringAsFixed(1)}°', Icons.straighten),
                _metricTile('Altitude', '${altitude.toStringAsFixed(1)}°', Icons.vertical_align_top),
              ],
            ),

            const SizedBox(height: 16),

            // Météo (couverture nuageuse Open-Meteo)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141830),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud, color: Colors.lightBlueAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cloud != null
                          ? "Couverture nuageuse prévue : ${cloud.toStringAsFixed(0)}%"
                          : "Données météo non disponibles",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            if (tip != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: Colors.amberAccent),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }
}
