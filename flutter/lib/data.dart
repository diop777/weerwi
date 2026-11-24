import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

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

/// Villes du pays par défaut (Sénégal - 14 Régions & Cités religieuses) avant ou après détection GPS locale
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
const kDaysFr = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String frDate(DateTime d, {bool weekday = false}) {
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
      throw Exception('Le serveur a répondu ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> evening(City c, DateTime d) async {
    final r = await http
        .post(buildUri('/moon'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'latitude': c.lat, 'longitude': c.lon, 'date': isoDate(d), 'utc_offset': c.tz}))
        .timeout(const Duration(seconds: 40));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> month(City c, int year, int month) async {
    final r = await http
        .get(buildUri('/month', {
          'lat': '${c.lat}',
          'lon': '${c.lon}',
          'year': '$year',
          'month': '$month',
          'utc_offset': '${c.tz}',
        }))
        .timeout(const Duration(seconds: 60));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> hilal(City c, DateTime from) async {
    final r = await http
        .get(buildUri('/hilal', {
          'lat': '${c.lat}',
          'lon': '${c.lon}',
          'date': isoDate(from),
          'utc_offset': '${c.tz}',
          'country_code': c.countryCode,
        }))
        .timeout(const Duration(seconds: 90));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> hijriMonth(City c, int month) async {
    final r = await http
        .get(buildUri('/hijri-month', {
          'lat': '${c.lat}',
          'lon': '${c.lon}',
          'month': '$month',
          'utc_offset': '${c.tz}',
          'country_code': c.countryCode,
        }))
        .timeout(const Duration(seconds: 90));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> regions({
    required String countryCode,
    required DateTime date,
    required int hijriMonth,
    required int dayOffset,
  }) async {
    final r = await http
        .get(buildUri('/regions', {
          'country': countryCode,
          'date': isoDate(date),
          'hijri_month': '$hijriMonth',
          'day_offset': '$dayOffset',
        }))
        .timeout(const Duration(seconds: 60));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> gpsLocate({double? lat, double? lon}) async {
    final q = <String, String>{};
    if (lat != null && lon != null) {
      q['lat'] = '$lat';
      q['lon'] = '$lon';
    }
    final r = await http.get(buildUri('/gps-locate', q.isEmpty ? null : q)).timeout(const Duration(seconds: 20));
    return _decode(r);
  }

  static String bulletinUrl(City c, DateTime d, int hijriMonth) {
    return buildUri('/bulletin', {
      'city': c.name,
      'country': c.country,
      'country_code': c.countryCode,
      'lat': '${c.lat}',
      'lon': '${c.lon}',
      'utc_offset': '${c.tz}',
      'date': isoDate(d),
      'hijri_month': '$hijriMonth',
    }).toString();
  }
}
