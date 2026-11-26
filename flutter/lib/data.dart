import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class DialCountry {
  final String code; // ex: SN, ML, GM
  final String name;
  final String nameEn;
  final String flag;
  final String dial; // ex: +221
  const DialCountry(this.code, this.name, this.flag, this.dial, [this.nameEn = '']);

  String label(String lang) => (lang == 'en' && nameEn.isNotEmpty) ? nameEn : name;
}

bool isAnglophoneCountry(String code) {
  const anglophone = {'GM', 'GH', 'NG', 'SL', 'LR'};
  return anglophone.contains(code.toUpperCase());
}

String langForCountry(String code) => isAnglophoneCountry(code) ? 'en' : 'fr';

const Map<String, String> kCountryNamesFr = {
  'SN': 'Sénégal',
  'ML': 'Mali',
  'GM': 'Gambie',
  'MR': 'Mauritanie',
  'GN': 'Guinée',
  'CI': "Côte d'Ivoire",
  'BF': 'Burkina Faso',
  'NE': 'Niger',
  'TG': 'Togo',
  'BJ': 'Bénin',
  'GW': 'Guinée-Bissau',
  'CV': 'Cap-Vert',
  'GH': 'Ghana',
  'NG': 'Nigeria',
  'SL': 'Sierra Leone',
  'LR': 'Liberia',
};

const Map<String, String> kCountryNamesEn = {
  'SN': 'Senegal',
  'ML': 'Mali',
  'GM': 'Gambia',
  'MR': 'Mauritania',
  'GN': 'Guinea',
  'CI': 'Ivory Coast',
  'BF': 'Burkina Faso',
  'NE': 'Niger',
  'TG': 'Togo',
  'BJ': 'Benin',
  'GW': 'Guinea-Bissau',
  'CV': 'Cape Verde',
  'GH': 'Ghana',
  'NG': 'Nigeria',
  'SL': 'Sierra Leone',
  'LR': 'Liberia',
};

String localizedCountryName(String code, String fallback, String lang) {
  final c = code.toUpperCase();
  if (lang == 'en') return kCountryNamesEn[c] ?? fallback;
  return kCountryNamesFr[c] ?? fallback;
}

/// Tous les pays d'Afrique de l'Ouest (CEDEAO + Mauritanie) pour le sélecteur d'indicatif téléphonique
const List<DialCountry> kWestAfricaDialCodes = [
  DialCountry('SN', 'Sénégal', '🇸🇳', '+221', 'Senegal'),
  DialCountry('ML', 'Mali', '🇲🇱', '+223', 'Mali'),
  DialCountry('GM', 'Gambie', '🇬🇲', '+220', 'Gambia'),
  DialCountry('MR', 'Mauritanie', '🇲🇷', '+222', 'Mauritania'),
  DialCountry('GN', 'Guinée', '🇬🇳', '+224', 'Guinea'),
  DialCountry('CI', "Côte d'Ivoire", '🇨🇮', '+225', 'Ivory Coast'),
  DialCountry('BF', 'Burkina Faso', '🇧🇫', '+226', 'Burkina Faso'),
  DialCountry('NE', 'Niger', '🇳🇪', '+227', 'Niger'),
  DialCountry('TG', 'Togo', '🇹🇬', '+228', 'Togo'),
  DialCountry('BJ', 'Bénin', '🇧🇯', '+229', 'Benin'),
  DialCountry('GW', 'Guinée-Bissau', '🇬🇼', '+245', 'Guinea-Bissau'),
  DialCountry('CV', 'Cap-Vert', '🇨🇻', '+238', 'Cape Verde'),
  DialCountry('GH', 'Ghana', '🇬🇭', '+233', 'Ghana'),
  DialCountry('NG', 'Nigeria', '🇳🇬', '+234', 'Nigeria'),
  DialCountry('SL', 'Sierra Leone', '🇸🇱', '+232', 'Sierra Leone'),
  DialCountry('LR', 'Liberia', '🇱🇷', '+231', 'Liberia'),
];

class City {
  final String name, region, country, flag, countryCode;
  final double lat, lon, tz;
  const City(
    this.name,
    this.country,
    this.flag,
    this.lat,
    this.lon,
    this.tz, [
    this.countryCode = 'SN',
    this.region = 'Dakar',
  ]);

  factory City.fromJson(Map<String, dynamic> j) {
    return City(
      (j['name'] as String?) ?? 'Dakar',
      (j['country'] as String?) ?? 'Sénégal',
      (j['flag'] as String?) ?? '🇸🇳',
      toD(j['lat']) ?? 14.6937,
      toD(j['lon']) ?? -17.4441,
      toD(j['tz']) ?? 0,
      (j['country_code'] as String?) ?? 'SN',
      (j['region'] as String?) ?? '',
    );
  }
}

/// Villes du pays par défaut (Sénégal)
const List<City> kDefaultCountryCities = [
  City('Dakar', 'Sénégal', '🇸🇳', 14.6937, -17.4441, 0, 'SN', 'Dakar'),
  City('Touba', 'Sénégal', '🇸🇳', 14.8647, -15.8756, 0, 'SN', 'Diourbel'),
  City('Tivaouane', 'Sénégal', '🇸🇳', 14.9514, -16.8189, 0, 'SN', 'Thiès'),
  City('Thiès', 'Sénégal', '🇸🇳', 14.7886, -16.9260, 0, 'SN', 'Thiès'),
  City('Saint-Louis', 'Sénégal', '🇸🇳', 16.0179, -16.4896, 0, 'SN', 'Saint-Louis'),
  City('Kaolack', 'Sénégal', '🇸🇳', 14.1520, -16.0726, 0, 'SN', 'Kaolack'),
  City('Diourbel', 'Sénégal', '🇸🇳', 14.6550, -16.2314, 0, 'SN', 'Diourbel'),
  City('Louga', 'Sénégal', '🇸🇳', 15.6186, -16.2244, 0, 'SN', 'Louga'),
  City('Fatick', 'Sénégal', '🇸🇳', 14.3390, -16.4111, 0, 'SN', 'Fatick'),
  City('Kaffrine', 'Sénégal', '🇸🇳', 14.1059, -15.5508, 0, 'SN', 'Kaffrine'),
  City('Matam', 'Sénégal', '🇸🇳', 15.6559, -13.2554, 0, 'SN', 'Matam'),
  City('Tambacounda', 'Sénégal', '🇸🇳', 13.7707, -13.6673, 0, 'SN', 'Tambacounda'),
  City('Kédougou', 'Sénégal', '🇸🇳', 12.5579, -12.1743, 0, 'SN', 'Kédougou'),
  City('Kolda', 'Sénégal', '🇸🇳', 12.8939, -14.9412, 0, 'SN', 'Kolda'),
  City('Sédhiou', 'Sénégal', '🇸🇳', 12.7081, -15.5569, 0, 'SN', 'Sédhiou'),
  City('Ziguinchor', 'Sénégal', '🇸🇳', 12.5681, -16.2719, 0, 'SN', 'Ziguinchor'),
];

const kMonthsFr = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];
const kMonthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const kDaysFr = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const kDaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String frDate(DateTime d, {bool weekday = false, String lang = 'fr'}) {
  if (lang == 'en') {
    final s = '${d.day} ${kMonthsEn[d.month - 1]} ${d.year}';
    return weekday ? '${kDaysEn[d.weekday - 1]}, $s' : s;
  }
  final s = '${d.day} ${kMonthsFr[d.month - 1]} ${d.year}';
  return weekday ? '${kDaysFr[d.weekday - 1]} $s' : s;
}

double? toD(dynamic v) => (v as num?)?.toDouble();

class Api {
  static Uri buildUri(String path, [Map<String, String>? q]) {
    final base = kIsWeb ? Uri.base : Uri.parse('http://localhost:8000/');
    return base.replace(path: path, queryParameters: q);
  }

  static Future<Map<String, dynamic>> _decode(http.Response r) async {
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendOtp({
    required String firstName,
    required String lastName,
    required String contact,
    required String channel,
  }) async {
    final r = await http
        .post(
          buildUri('/auth/send-code'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'first_name': firstName,
            'last_name': lastName,
            'contact': contact,
            'channel': channel,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String contact,
    required String code,
  }) async {
    final r = await http
        .post(
          buildUri('/auth/verify-code'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'contact': contact, 'code': code}),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> evening(City c, DateTime d, {String lang = 'fr'}) async {
    final r = await http
        .post(buildUri('/moon'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'latitude': c.lat,
              'longitude': c.lon,
              'date': isoDate(d),
              'utc_offset': c.tz,
              'lang': lang,
              'country_code': c.countryCode,
            }))
        .timeout(const Duration(seconds: 40));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> month(City c, int year, int month, {String lang = 'fr'}) async {
    final r = await http
        .get(buildUri('/month', {
          'lat': '${c.lat}',
          'lon': '${c.lon}',
          'year': '$year',
          'month': '$month',
          'utc_offset': '${c.tz}',
          'lang': lang,
          'country_code': c.countryCode,
        }))
        .timeout(const Duration(seconds: 60));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> hilal(City c, DateTime from, {String lang = 'fr'}) async {
    final r = await http
        .get(buildUri('/hilal', {
          'lat': '${c.lat}',
          'lon': '${c.lon}',
          'date': isoDate(from),
          'utc_offset': '${c.tz}',
          'country_code': c.countryCode,
          'lang': lang,
        }))
        .timeout(const Duration(seconds: 90));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> hijriMonth(City c, int month, {String lang = 'fr'}) async {
    final r = await http
        .get(buildUri('/hijri-month', {
          'lat': '${c.lat}',
          'lon': '${c.lon}',
          'month': '$month',
          'utc_offset': '${c.tz}',
          'country_code': c.countryCode,
          'lang': lang,
        }))
        .timeout(const Duration(seconds: 90));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> regions({
    required String countryCode,
    required DateTime date,
    required int hijriMonth,
    required int dayOffset,
    String lang = 'fr',
  }) async {
    final r = await http
        .get(buildUri('/regions', {
          'country': countryCode,
          'date': isoDate(date),
          'hijri_month': '$hijriMonth',
          'day_offset': '$dayOffset',
          'lang': lang,
        }))
        .timeout(const Duration(seconds: 60));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> gpsLocate({
    double? lat,
    double? lon,
    String? countryCode,
    String? lang,
  }) async {
    final q = <String, String>{};
    if (lat != null && lon != null) {
      q['lat'] = '$lat';
      q['lon'] = '$lon';
    }
    if (countryCode != null && countryCode.isNotEmpty) {
      q['country_code'] = countryCode;
    }
    if (lang != null && lang.isNotEmpty) {
      q['lang'] = lang;
    }
    final r = await http.get(buildUri('/gps-locate', q.isEmpty ? null : q)).timeout(const Duration(seconds: 20));
    return _decode(r);
  }

  static String bulletinUrl(City c, DateTime d, int hijriMonth, {String lang = 'fr'}) {
    return buildUri('/bulletin', {
      'city': c.name,
      'country': localizedCountryName(c.countryCode, c.country, lang),
      'country_code': c.countryCode,
      'lat': '${c.lat}',
      'lon': '${c.lon}',
      'utc_offset': '${c.tz}',
      'date': isoDate(d),
      'hijri_month': '$hijriMonth',
      'lang': lang,
    }).toString();
  }
}
