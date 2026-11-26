"""
WeerWi - Moteur astronomique.

Calculs basés sur les éphémérides NASA JPL DE421 (Skyfield) :
  * instants exacts des phases (conjonction / nouvelle lune, quartiers, pleine lune)
  * coucher du Soleil et de la Lune pour un lieu donné (topocentrique)
  * visibilité du croissant selon les critères de Yallop (1997) et d'Odeh (2004),
    évalués au « meilleur moment » d'observation : Tb = coucher Soleil + 4/9 × décalage.
"""
import calendar
import datetime as dt
import math
import os
import ssl

import certifi
import skyfield.iokit
from skyfield import almanac
from skyfield.api import Loader, wgs84

# Certificats SSL fiables sous Windows pour le téléchargement éventuel des éphémérides
skyfield.iokit.create_default_context = lambda *a, **k: ssl.create_default_context(cafile=certifi.where())

_HERE = os.path.dirname(os.path.abspath(__file__))
_load = Loader(_HERE, verbose=False)
ts = _load.timescale()
eph = _load("de421.bsp")
EARTH, SUN, MOON = eph["earth"], eph["sun"], eph["moon"]
MOON_PHASES = almanac.moon_phases(eph)

MOON_RADIUS_KM = 1737.4
EARTH_RADIUS_KM = 6378.137

PHASE_EVENT_NAMES = ["Nouvelle lune", "Premier quartier", "Pleine lune", "Dernier quartier"]
PHASE_EVENT_NAMES_EN = ["New Moon", "First Quarter", "Full Moon", "Last Quarter"]
HIJRI_MONTHS = [
    "Mouharram", "Safar", "Rabi al-Awwal", "Rabi ath-Thani", "Joumada al-Oula", "Joumada ath-Thania",
    "Rajab", "Chaabane", "Ramadan", "Chawwal", "Dhou al-Qi'da", "Dhou al-Hijja",
]
HIJRI_MONTHS_EN = [
    "Muharram", "Safar", "Rabi' al-Awwal", "Rabi' al-Thani", "Jumada al-Ula", "Jumada al-Akhirah",
    "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhu al-Qi'dah", "Dhu al-Hijjah",
]
MONTHS_FR = [
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
]
MONTHS_EN = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]
DAYS_FR = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
DAYS_EN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

ANGLOPHONE_COUNTRIES = {"GM", "GH", "NG", "SL", "LR"}

COUNTRY_NAMES_EN = {
    "SN": "Senegal",
    "ML": "Mali",
    "GM": "Gambia",
    "MR": "Mauritania",
    "GN": "Guinea",
    "CI": "Ivory Coast",
    "BF": "Burkina Faso",
    "NE": "Niger",
    "TG": "Togo",
    "BJ": "Benin",
    "GW": "Guinea-Bissau",
    "CV": "Cape Verde",
    "GH": "Ghana",
    "NG": "Nigeria",
    "SL": "Sierra Leone",
    "LR": "Liberia",
    "WORLD": "World & Holy Sites",
}

LOCALITY_TYPE_EN = {
    "Capitale": "Capital",
    "Capitale côtière": "Coastal Capital",
    "Capitale (Ouest)": "Capital (West)",
    "Métropole": "Metropolis",
    "Chef-lieu": "Regional Capital",
    "Chef-lieu côtier": "Coastal Regional Capital",
    "Chef-lieu Sud": "Southern Regional Capital",
    "Chef-lieu & Cité religieuse": "Regional Capital & Religious City",
    "Cité religieuse": "Religious City",
    "Cité religieuse & Département": "Religious City & Department",
    "Foyer religieux": "Religious Center",
    "Cité historique": "Historic City",
    "Département": "Department",
    "Département côtier": "Coastal Department",
    "Commune": "Municipality",
    "Commune côtière": "Coastal Municipality",
    "Cercle": "District",
    "Cap le plus à l'Ouest": "Westernmost Cape",
    "Pointe Sud-Ouest côtière": "South-West Coastal Tip",
    "Sud-Ouest côtier": "South-West Coast",
    "Nord-Ouest côtier": "North-West Coast",
    "Nord-Ouest": "North-West",
    "Sud-Ouest": "South-West",
    "Nord": "North",
    "Sud": "South",
    "Est": "East",
    "Centre": "Central",
    "Sud-Centre": "South-Central",
    "Nord-Est": "North-East",
    "Extrême-Est": "Far East",
}


def resolve_lang(lang: str | None = None, country_code: str | None = None) -> str:
    if lang and lang.lower().startswith("en"):
        return "en"
    if lang and lang.lower().startswith("fr"):
        return "fr"
    if country_code and country_code.upper() in ANGLOPHONE_COUNTRIES:
        return "en"
    return "fr"


def country_display_name(country_code: str, default_name: str, lang: str = "fr") -> str:
    base = default_name.split(" (")[0]
    if lang == "en":
        return COUNTRY_NAMES_EN.get((country_code or "").upper(), base)
    return base


def translate_locality_type(t: str, lang: str = "fr") -> str:
    if lang != "en":
        return t
    return LOCALITY_TYPE_EN.get(t, t)

# Villes de référence (Afrique de l'Ouest) avec leur fuseau horaire (heures / UTC)
CITIES = [
    {"name": "Dakar", "country": "Sénégal", "flag": "🇸🇳", "lat": 14.6937, "lon": -17.4441, "tz": 0},
    {"name": "Touba", "country": "Sénégal", "flag": "🇸🇳", "lat": 14.8647, "lon": -15.8756, "tz": 0},
    {"name": "Nouakchott", "country": "Mauritanie", "flag": "🇲🇷", "lat": 18.0735, "lon": -15.9582, "tz": 0},
    {"name": "Banjul", "country": "Gambie", "flag": "🇬🇲", "lat": 13.4549, "lon": -16.5790, "tz": 0},
    {"name": "Conakry", "country": "Guinée", "flag": "🇬🇳", "lat": 9.6412, "lon": -13.5784, "tz": 0},
    {"name": "Bamako", "country": "Mali", "flag": "🇲🇱", "lat": 12.6392, "lon": -8.0029, "tz": 0},
    {"name": "Abidjan", "country": "Côte d'Ivoire", "flag": "🇨🇮", "lat": 5.3600, "lon": -4.0083, "tz": 0},
    {"name": "Ouagadougou", "country": "Burkina Faso", "flag": "🇧🇫", "lat": 12.3714, "lon": -1.5197, "tz": 0},
    {"name": "Lomé", "country": "Togo", "flag": "🇹🇬", "lat": 6.1375, "lon": 1.2125, "tz": 0},
    {"name": "Cotonou", "country": "Bénin", "flag": "🇧🇯", "lat": 6.3654, "lon": 2.4183, "tz": 1},
    {"name": "Niamey", "country": "Niger", "flag": "🇳🇪", "lat": 13.5116, "lon": 2.1254, "tz": 1},
]

# ─────────────────────────── Outils temps ───────────────────────────

def default_offset(lon: float) -> float:
    return float(round(lon / 15.0))


def shift(t, days: float):
    return ts.tt_jd(t.tt + days)


def local_to_t(d: dt.date, hour: float, off: float):
    base = dt.datetime(d.year, d.month, d.day) + dt.timedelta(hours=hour - off)
    return ts.from_datetime(base.replace(tzinfo=dt.timezone.utc))


def t_to_local(t, off: float) -> dt.datetime:
    return t.utc_datetime().replace(tzinfo=None) + dt.timedelta(hours=off, seconds=30)


def hm(t, off):
    return t_to_local(t, off).strftime("%H:%M") if t is not None else None


def iso_local(t, off):
    return t_to_local(t, off).strftime("%Y-%m-%dT%H:%M") if t is not None else None


def fr_date(d: dt.date, with_day=True, lang: str = "fr") -> str:
    if lang == "en":
        s = f"{d.day} {MONTHS_EN[d.month - 1]} {d.year}"
        return f"{DAYS_EN[d.weekday()]}, {s}" if with_day else s
    s = f"{d.day} {MONTHS_FR[d.month - 1]} {d.year}"
    return f"{DAYS_FR[d.weekday()]} {s}" if with_day else s


def _events(fn, obs, body, t0, t1):
    t, y = fn(obs, body, t0, t1)
    return [t[i] for i in range(len(t)) if y[i]]


def observer(lat, lon):
    return EARTH + wgs84.latlon(lat, lon)

# ─────────────────────────── Calendrier hégirien (tabulaire, indicatif) ───────────────────────────

_ISLAMIC_EPOCH = 1948439.5


def _islamic_to_jd(y, m, d):
    return d + math.ceil(29.5 * (m - 1)) + (y - 1) * 354 + math.floor((3 + 11 * y) / 30) + _ISLAMIC_EPOCH - 1


def hijri_from_date(d: dt.date):
    jd = math.floor(d.toordinal() + 1721424.5) + 0.5
    y = math.floor((30 * (jd - _ISLAMIC_EPOCH) + 10646) / 10631)
    m = min(12, math.ceil((jd - (29 + _islamic_to_jd(y, 1, 1))) / 29.5) + 1)
    day = jd - _islamic_to_jd(y, m, 1) + 1
    return int(y), int(m), int(day)


def month_starting_after(conj_local_date: dt.date, lang: str = "fr"):
    """Mois hégirien qui commence juste après une conjonction (3 jours après = au cœur du nouveau mois)."""
    y, m, _ = hijri_from_date(conj_local_date + dt.timedelta(days=3))
    months = HIJRI_MONTHS_EN if lang == "en" else HIJRI_MONTHS
    return y, m, months[m - 1]

# ─────────────────────────── Phases ───────────────────────────

def phase_info(t):
    ang = float(almanac.moon_phase(eph, t).degrees)
    illum = float(almanac.fraction_illuminated(eph, "moon", t)) * 100.0
    return ang, illum, ang < 180.0


def phase_name(ang: float, lang: str = "fr") -> str:
    if lang == "en":
        if ang < 6 or ang >= 354:
            return "New Moon"
        if ang < 84:
            return "Waxing Crescent"
        if ang < 96:
            return "First Quarter"
        if ang < 174:
            return "Waxing Gibbous"
        if ang < 186:
            return "Full Moon"
        if ang < 264:
            return "Waning Gibbous"
        if ang < 276:
            return "Last Quarter"
        return "Waning Crescent"
    if ang < 6 or ang >= 354:
        return "Nouvelle lune"
    if ang < 84:
        return "Premier croissant"
    if ang < 96:
        return "Premier quartier"
    if ang < 174:
        return "Gibbeuse croissante"
    if ang < 186:
        return "Pleine lune"
    if ang < 264:
        return "Gibbeuse décroissante"
    if ang < 276:
        return "Dernier quartier"
    return "Dernier croissant"


def new_moons_between(t0, t1):
    t, y = almanac.find_discrete(t0, t1, MOON_PHASES)
    return [t[i] for i in range(len(t)) if y[i] == 0]


def surrounding_new_moons(t):
    prev = new_moons_between(shift(t, -31), t)
    nxt = new_moons_between(t, shift(t, 31))
    return prev[-1], nxt[0]

# ─────────────────────────── Géométrie & critères ───────────────────────────

def geometry(obs, t):
    o = obs.at(t)
    m = o.observe(MOON).apparent()
    s = o.observe(SUN).apparent()
    malt, maz, mdist = m.altaz()  # sans réfraction (« airless »), comme l'exigent Yallop et Odeh
    salt, saz, _ = s.altaz()
    arcl = float(m.separation_from(s).degrees)
    dist_km = float(mdist.km)
    sd = math.degrees(math.asin(MOON_RADIUS_KM / dist_km)) * 60.0       # demi-diamètre topocentrique (')
    width = sd * (1 - math.cos(math.radians(arcl)))                      # largeur du croissant (')
    hp = math.degrees(math.asin(EARTH_RADIUS_KM / dist_km))              # parallaxe horizontale
    moon_alt = float(malt.degrees)
    sun_alt = float(salt.degrees)
    moon_alt_geo = moon_alt + hp * math.cos(math.radians(moon_alt))
    daz = (float(saz.degrees) - float(maz.degrees) + 180) % 360 - 180
    return {
        "moon_alt": moon_alt, "sun_alt": sun_alt, "moon_az": float(maz.degrees), "sun_az": float(saz.degrees),
        "arcl": arcl, "arcv_topo": moon_alt - sun_alt, "arcv_geo": moon_alt_geo - sun_alt,
        "daz": daz, "width": width, "dist_km": dist_km,
    }


def yallop(width, arcv, lang: str = "fr"):
    q = (arcv - (11.8371 - 6.3226 * width + 0.7319 * width ** 2 - 0.1018 * width ** 3)) / 10.0
    if lang == "en":
        if q > 0.216:
            c, txt = "A", "Easily visible to the naked eye"
        elif q > -0.014:
            c, txt = "B", "Visible to the naked eye under perfect conditions"
        elif q > -0.160:
            c, txt = "C", "Optical aid helpful to locate, then visible to the naked eye"
        elif q > -0.232:
            c, txt = "D", "Visible only with binoculars or telescope"
        elif q > -0.293:
            c, txt = "E", "Not visible, even with a telescope"
        else:
            c, txt = "F", "Not visible (below the Danjon limit)"
        return {"q": round(q, 3), "code": c, "text": txt}
    if q > 0.216:
        c, txt = "A", "Facilement visible à l'œil nu"
    elif q > -0.014:
        c, txt = "B", "Visible à l'œil nu si conditions parfaites"
    elif q > -0.160:
        c, txt = "C", "Jumelles utiles pour le repérer, puis visible à l'œil nu"
    elif q > -0.232:
        c, txt = "D", "Visible uniquement avec jumelles ou télescope"
    elif q > -0.293:
        c, txt = "E", "Non visible, même au télescope"
    else:
        c, txt = "F", "Non visible (sous la limite de Danjon)"
    return {"q": round(q, 3), "code": c, "text": txt}


def odeh(width, arcv, lang: str = "fr"):
    v = arcv - (7.1651 - 6.3226 * width + 0.7319 * width ** 2 - 0.1018 * width ** 3)
    if lang == "en":
        if v >= 5.65:
            c, txt = "A", "Visible to the naked eye"
        elif v >= 2.0:
            c, txt = "B", "Visible with binoculars, possible to the naked eye"
        elif v >= -0.96:
            c, txt = "C", "Visible only with binoculars or telescope"
        else:
            c, txt = "D", "Not visible, even with optical instruments"
        return {"v": round(v, 2), "code": c, "text": txt}
    if v >= 5.65:
        c, txt = "A", "Visible à l'œil nu"
    elif v >= 2.0:
        c, txt = "B", "Visible aux jumelles, possible à l'œil nu"
    elif v >= -0.96:
        c, txt = "C", "Visible uniquement avec jumelles ou télescope"
    else:
        c, txt = "D", "Non visible, même avec instruments"
    return {"v": round(v, 2), "code": c, "text": txt}


VERDICTS = {
    "naked_eye": ("Visible à l'œil nu", "good"),
    "naked_eye_possible": ("Jumelles conseillées, œil nu possible", "maybe"),
    "optical_only": ("Visible uniquement aux instruments", "optical"),
    "not_visible": ("Non visible", "bad"),
}
VERDICTS_EN = {
    "naked_eye": ("Visible to the naked eye", "good"),
    "naked_eye_possible": ("Binoculars advised, naked eye possible", "maybe"),
    "optical_only": ("Visible with instruments only", "optical"),
    "not_visible": ("Not visible", "bad"),
}
_ODEH_TO_VERDICT = {"A": "naked_eye", "B": "naked_eye_possible", "C": "optical_only", "D": "not_visible"}


def crescent_eval(obs, sunset, moonset, age_h, lang: str = "fr"):
    """Évalue la visibilité du croissant au meilleur moment après le coucher du Soleil."""
    lag = (moonset.tt - sunset.tt) * 1440.0 if moonset is not None else None
    base = {"lag_minutes": round(lag) if lag is not None else None, "age_hours": round(age_h, 1)}
    if age_h <= 0:
        msg = ("Conjunction after sunset: no crescent possible"
               if lang == "en" else "Conjonction après le coucher du Soleil : aucun croissant possible")
        return {**base, "possible": False, "verdict_code": "not_visible",
                "verdict_text": msg,
                "level": "bad"}
    if lag is None or lag <= 0:
        msg = ("Moon sets before the Sun: crescent impossible to see"
               if lang == "en" else "La Lune se couche avant le Soleil : croissant impossible à voir")
        return {**base, "possible": False, "verdict_code": "not_visible",
                "verdict_text": msg,
                "level": "bad"}
    tb = shift(sunset, lag * 4.0 / 9.0 / 1440.0)
    g = geometry(obs, tb)
    y = yallop(g["width"], g["arcv_geo"], lang=lang)
    o = odeh(g["width"], g["arcv_topo"], lang=lang)
    code = _ODEH_TO_VERDICT[o["code"]]
    vmap = VERDICTS_EN if lang == "en" else VERDICTS
    text, level = vmap[code]
    return {
        **base, "possible": True, "best_time_t": tb,
        "arcl": round(g["arcl"], 2), "arcv": round(g["arcv_topo"], 2), "daz": round(g["daz"], 2),
        "width_arcmin": round(g["width"], 3), "moon_alt": round(g["moon_alt"], 2), "sun_alt": round(g["sun_alt"], 2),
        "yallop": y, "odeh": o, "verdict_code": code, "verdict_text": text, "level": level,
    }


def _clean_crescent(c, off):
    if c is None:
        return None
    c = dict(c)
    tb = c.pop("best_time_t", None)
    c["best_time"] = hm(tb, off) if tb is not None else None
    return c

# ─────────────────────────── Rapport d'une soirée ───────────────────────────

def _sunset_on(obs, d, off):
    s = _events(almanac.find_settings, obs, SUN, local_to_t(d, 12, off), local_to_t(d, 24, off))
    return s[0] if s else local_to_t(d, 18.75, off)


def _nearest(times, ref):
    return min(times, key=lambda t: abs(t.tt - ref.tt)) if times else None


def evening_report(lat: float, lon: float, d: dt.date, off: float, lang: str = "fr") -> dict:
    lang = resolve_lang(lang)
    is_en = lang == "en"
    obs = observer(lat, lon)
    sunset = _sunset_on(obs, d, off)
    moonset = _nearest(_events(almanac.find_settings, obs, MOON, shift(sunset, -0.5), shift(sunset, 0.6)), sunset)
    sunrises = _events(almanac.find_risings, obs, SUN, sunset, shift(sunset, 0.75))
    sunrise = sunrises[0] if sunrises else shift(sunset, 0.5)
    night_rises = _events(almanac.find_risings, obs, MOON, sunset, sunrise)
    night_sets = _events(almanac.find_settings, obs, MOON, sunset, sunrise)

    g = geometry(obs, sunset)
    ang, illum, waxing = phase_info(sunset)
    prev_nm, next_nm = surrounding_new_moons(sunset)
    age_h = (sunset.tt - prev_nm.tt) * 24.0
    to_next_h = (next_nm.tt - sunset.tt) * 24.0

    # Présence de la Lune durant la nuit
    above = g["moon_alt"] > 0
    if is_en:
        if above and not night_sets:
            presence = "Present all night, from sunset until dawn."
        elif above:
            presence = f"Visible from sunset until {hm(night_sets[0], off)}."
        elif night_rises:
            presence = f"Rises at {hm(night_rises[0], off)}"
            later_sets = [s for s in night_sets if s.tt > night_rises[0].tt]
            presence += f" and sets at {hm(later_sets[0], off)}." if later_sets else " and remains visible until dawn."
        else:
            presence = "Absent from the sky tonight (below the horizon between sunset and sunrise)."
    else:
        if above and not night_sets:
            presence = "Présente toute la nuit, du coucher du Soleil jusqu'à l'aube."
        elif above:
            presence = f"Visible dès le coucher du Soleil jusqu'à {hm(night_sets[0], off)}."
        elif night_rises:
            presence = f"Se lève à {hm(night_rises[0], off)}"
            later_sets = [s for s in night_sets if s.tt > night_rises[0].tt]
            presence += f" et se couche à {hm(later_sets[0], off)}." if later_sets else " et reste visible jusqu'à l'aube."
        else:
            presence = "Absente du ciel cette nuit (sous l'horizon entre le coucher et le lever du Soleil)."
    present_tonight = above or bool(night_rises)

    crescent = None
    if 0 < age_h <= 72:
        context = "crescent"
        crescent = crescent_eval(obs, sunset, moonset, age_h, lang=lang)
        hy, hmo, hname = month_starting_after(t_to_local(prev_nm, off).date(), lang=lang)
    elif to_next_h <= 48:
        context = "pre_conjunction"
        hy, hmo, hname = month_starting_after(t_to_local(next_nm, off).date(), lang=lang)
    else:
        context = "general"
        hy, hmo, hname = month_starting_after(t_to_local(prev_nm, off).date(), lang=lang)

    tomorrow = d + dt.timedelta(days=1)
    if context == "crescent":
        code = crescent["verdict_code"]
        if is_en:
            badge = {
                "naked_eye": ("CRESCENT VISIBLE TO THE NAKED EYE", "good"),
                "naked_eye_possible": ("CRESCENT: NAKED EYE POSSIBLE, BINOCULARS ADVISED", "maybe"),
                "optical_only": ("CRESCENT VISIBLE WITH INSTRUMENTS ONLY", "optical"),
                "not_visible": ("CRESCENT NOT VISIBLE TONIGHT", "bad"),
            }[code]
        else:
            badge = {
                "naked_eye": ("CROISSANT VISIBLE À L'ŒIL NU", "good"),
                "naked_eye_possible": ("CROISSANT : ŒIL NU POSSIBLE, JUMELLES CONSEILLÉES", "maybe"),
                "optical_only": ("CROISSANT VISIBLE AUX INSTRUMENTS SEULEMENT", "optical"),
                "not_visible": ("CROISSANT NON VISIBLE CE SOIR", "bad"),
            }[code]
        visible = code == "naked_eye"
        if crescent["possible"]:
            if is_en:
                tip = (f"Look west (azimuth ≈ {g['moon_az']:.0f}°) between {hm(sunset, off)} and "
                       f"{hm(moonset, off)}. Best sighting time: {_clean_crescent(crescent, off)['best_time']}. "
                       f"Odeh: {crescent['odeh']['text'].lower()}. Yallop ({crescent['yallop']['code']}): "
                       f"{crescent['yallop']['text'].lower()}.")
            else:
                tip = (f"Regardez vers l'ouest (azimut ≈ {g['moon_az']:.0f}°) entre {hm(sunset, off)} et "
                       f"{hm(moonset, off)}. Meilleur moment : {_clean_crescent(crescent, off)['best_time']}. "
                       f"Odeh : {crescent['odeh']['text'].lower()}. Yallop ({crescent['yallop']['code']}) : "
                       f"{crescent['yallop']['text'].lower()}.")
        else:
            tip = crescent["verdict_text"] + "."
        if code in ("naked_eye", "naked_eye_possible"):
            if is_en:
                status = (f"Crescent sighting evening for {hname} {hy} AH. If sighted tonight, "
                          f"1 {hname} will be on {fr_date(tomorrow, lang=lang)}.")
            else:
                status = (f"Soirée d'observation du croissant de {hname} {hy} H. S'il est aperçu ce soir, "
                          f"le 1er {hname} sera le {fr_date(tomorrow, lang=lang)}.")
        else:
            if is_en:
                status = (f"Crescent sighting evening for {hname} {hy} AH. Crescent not visible to the naked eye: "
                          f"the current month should complete 30 days (or begin after sighting the next evening).")
            else:
                status = (f"Soirée d'observation du croissant de {hname} {hy} H. Croissant non visible à l'œil nu : "
                          f"le mois en cours devrait compléter 30 jours (ou débuter après une observation le lendemain).")
    elif context == "pre_conjunction":
        badge = ("NO CRESCENT: NEW MOON UPCOMING", "bad") if is_en else ("PAS DE CROISSANT : NOUVELLE LUNE À VENIR", "bad")
        visible = False
        nm_local = t_to_local(next_nm, off)
        first_search = nm_local.date() if nm_local.hour < 12 else nm_local.date() + dt.timedelta(days=1)
        if is_en:
            tip = (f"Astronomical conjunction (New Moon) will occur on {fr_date(nm_local.date(), lang=lang)} at "
                   f"{nm_local.strftime('%H:%M')}. No new crescent is possible before that time.")
            status = (f"End of the lunar month. The crescent of {hname} {hy} AH can be searched starting on the evening "
                      f"of {fr_date(first_search, lang=lang)}.")
        else:
            tip = (f"La conjonction (nouvelle lune astronomique) aura lieu le {fr_date(nm_local.date(), lang=lang)} à "
                   f"{nm_local.strftime('%H:%M')}. Aucun nouveau croissant n'est possible avant cet instant.")
            status = (f"Fin du mois lunaire. Le croissant de {hname} {hy} H pourra être recherché à partir du soir "
                      f"du {fr_date(first_search, lang=lang)}.")
    else:
        if is_en:
            badge = ("MOON PRESENT IN THE SKY TONIGHT", "good") if present_tonight else (
                "MOON ABSENT FROM THE SKY TONIGHT", "bad")
            visible = present_tonight
            tip = presence
            nm_local = t_to_local(next_nm, off)
            status = (f"Ongoing lunar month ({hname} {hy} AH, estimate) — {age_h / 24:.1f} days after "
                      f"New Moon. Next New Moon: {fr_date(nm_local.date(), lang=lang)} at {nm_local.strftime('%H:%M')}.")
        else:
            badge = ("LUNE PRÉSENTE DANS LE CIEL CETTE NUIT", "good") if present_tonight else (
                "LUNE ABSENTE DU CIEL CE SOIR", "bad")
            visible = present_tonight
            tip = presence
            nm_local = t_to_local(next_nm, off)
            status = (f"Mois lunaire en cours ({hname} {hy} H, estimation) — {age_h / 24:.1f} jours après la "
                      f"nouvelle lune. Prochaine nouvelle lune : {fr_date(nm_local.date(), lang=lang)} à {nm_local.strftime('%H:%M')}.")

    if crescent and crescent.get("possible"):
        score = max(0.0, min(1.0, (crescent["odeh"]["v"] + 0.96) / 8.0))
    else:
        score = 1.0 if visible else 0.0

    # Direction cardinale & turbulence atmosphérique (masse d'air près de l'horizon)
    dirs_fr = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]
    dirs_en = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    dirs = dirs_en if is_en else dirs_fr
    cardinal = dirs[int(((g["moon_az"] + 11.25) % 360) / 22.5)]
    alt_deg = g["moon_alt"]
    if alt_deg <= 0:
        airmass = None
        if is_en:
            turb_level = "Below the horizon"
            turb_note = "The Moon is below the horizon at sunset: no direct light reaches the observer."
        else:
            turb_level = "Sous l'horizon"
            turb_note = "La Lune est sous l'horizon au coucher du Soleil : aucune lumière directe n'atteint l'observateur."
    else:
        # Formule de Kasten & Young (1989) pour la masse d'air atmosphérique
        airmass = round(1.0 / (math.sin(math.radians(alt_deg)) + 0.50572 * ((alt_deg + 6.07995) ** -1.6364)), 2)
        if alt_deg < 6:
            if is_en:
                turb_level = "High horizon turbulence"
                turb_note = (f"High airmass ({airmass}×) at {alt_deg:.1f}° altitude: strong atmospheric extinction, haze, "
                             f"dust (Harmattan), and scintillation near the horizon. A completely unobstructed western horizon is required.")
            else:
                turb_level = "Forte turbulence d'horizon"
                turb_note = (f"Masse d'air élevée ({airmass}×) à {alt_deg:.1f}° de hauteur : forte absorption, brume, "
                             f"poussière (Harmattan) et scintillation près de l'horizon. Un horizon ouest parfaitement dégagé est indispensable.")
        elif alt_deg < 15:
            if is_en:
                turb_level = "Moderate turbulence"
                turb_note = (f"Moderate airmass ({airmass}×) at {alt_deg:.1f}° altitude: good atmospheric transparency "
                             f"if the western horizon is free of dust and haze.")
            else:
                turb_level = "Turbulence modérée"
                turb_note = (f"Masse d'air modérée ({airmass}×) à {alt_deg:.1f}° de hauteur : transparence atmosphérique "
                             f"correcte si l'horizon ouest est sans poussière ni brume.")
        else:
            if is_en:
                turb_level = "Stable atmosphere (low extinction)"
                turb_note = f"Low airmass ({airmass}×) at {alt_deg:.1f}° altitude: minimal atmospheric turbulence."
            else:
                turb_level = "Atmosphère stable (faible extinction)"
                turb_note = f"Masse d'air faible ({airmass}×) à {alt_deg:.1f}° de hauteur : très peu de turbulence atmosphérique."

    return {
        "date": d.isoformat(),
        "date_label": fr_date(d, lang=lang),
        "utc_offset": off,
        "context": context,
        "sunset": hm(sunset, off),
        "sunrise_next": hm(sunrise, off),
        "moonset": hm(moonset, off),
        "moonrise_tonight": hm(night_rises[0], off) if night_rises else None,
        "lag_minutes": round((moonset.tt - sunset.tt) * 1440) if moonset is not None else None,
        "phase": phase_name(ang, lang=lang),
        "phase_angle": round(ang, 2),
        "waxing": waxing,
        "illumination": round(illum, 2),
        "age_hours": round(age_h, 1),
        "age_days": round(age_h / 24.0, 2),
        "last_new_moon": iso_local(prev_nm, off),
        "next_new_moon": iso_local(next_nm, off),
        "elongation_deg": round(g["arcl"], 2),
        "altitude_deg": round(g["moon_alt"], 2),
        "moon_azimuth_deg": round(g["moon_az"], 1),
        "sun_azimuth_deg": round(g["sun_az"], 1),
        "daz_deg": round(g["daz"], 1),
        "cardinal_direction": cardinal,
        "airmass": airmass,
        "turbulence_level": turb_level,
        "turbulence_note": turb_note,
        "present_tonight": present_tonight,
        "moon_presence": presence,
        "crescent": _clean_crescent(crescent, off),
        "visible": visible,
        "visibility_score": round(score, 2),
        "badge_text": badge[0],
        "badge_level": badge[1],
        "observation_tip": tip,
        "ramadan_status": status,
        "hijri_month": hname,
        "hijri_year": hy,
        "sunset_utc": sunset.utc_datetime().strftime("%Y-%m-%dT%H:%M"),
        "lang": lang,
    }

# ─────────────────────────── Calendrier mensuel ───────────────────────────

def month_calendar(lat: float, lon: float, off: float, year: int, month: int, lang: str = "fr") -> dict:
    lang = resolve_lang(lang)
    is_en = lang == "en"
    obs = observer(lat, lon)
    first = dt.date(year, month, 1)
    nd = calendar.monthrange(year, month)[1]
    t0 = local_to_t(first, -12, off)
    t1 = local_to_t(first + dt.timedelta(days=nd), 36, off)
    sunsets = _events(almanac.find_settings, obs, SUN, t0, t1)
    mrises = _events(almanac.find_risings, obs, MOON, t0, t1)
    msets = _events(almanac.find_settings, obs, MOON, t0, t1)
    pt, py = almanac.find_discrete(shift(t0, -31), t1, MOON_PHASES)
    phases = [(pt[i], int(py[i])) for i in range(len(pt))]
    new_moons = [t for t, y in phases if y == 0]

    def local_date(t):
        return t_to_local(t, off).date()

    ev_names = PHASE_EVENT_NAMES_EN if is_en else PHASE_EVENT_NAMES
    at_word = "at" if is_en else "à"
    events = []
    for t, y in phases:
        ld = local_date(t)
        if ld.year == year and ld.month == month:
            events.append({"type": y, "name": ev_names[y], "date": ld.isoformat(),
                           "time": hm(t, off), "label": f"{fr_date(ld, lang=lang)} {at_word} {hm(t, off)}"})

    h_months = HIJRI_MONTHS_EN if is_en else HIJRI_MONTHS
    days = []
    for i in range(nd):
        d = first + dt.timedelta(days=i)
        ss = next((s for s in sunsets if local_date(s) == d), None)
        if ss is None:
            ss = local_to_t(d, 18.75, off)
        ang, illum, waxing = phase_info(ss)
        g = geometry(obs, ss)
        prevs = [t for t in new_moons if t.tt <= ss.tt]
        age_h = (ss.tt - prevs[-1].tt) * 24.0 if prevs else 999
        crescent = None
        if 0 < age_h <= 72:
            c = crescent_eval(obs, ss, _nearest(msets, ss), age_h, lang=lang)
            crescent = {"verdict_code": c["verdict_code"], "verdict_text": c["verdict_text"], "level": c["level"],
                        "odeh_v": c["odeh"]["v"] if c.get("possible") else None}
        rise_today = [hm(t, off) for t in mrises if local_date(t) == d]
        set_today = [hm(t, off) for t in msets if local_date(t) == d]
        present = g["moon_alt"] > 0 or any(ss.tt < r.tt < ss.tt + 0.5 for r in mrises)
        hy, hmo, hd = hijri_from_date(d)
        days.append({
            "date": d.isoformat(), "day": d.day, "weekday": d.weekday(),
            "phase": phase_name(ang, lang=lang), "phase_angle": round(ang, 1), "illumination": round(illum, 1),
            "waxing": waxing, "sunset": hm(ss, off),
            "moonrise": rise_today[0] if rise_today else None,
            "moonset": set_today[0] if set_today else None,
            "moon_alt_at_sunset": round(g["moon_alt"], 1), "present_tonight": present,
            "age_hours": round(age_h, 1) if age_h < 999 else None,
            "events": [e["name"] for e in events if e["date"] == d.isoformat()],
            "crescent": crescent,
            "hijri_estimate": f"{hd} {h_months[hmo - 1]} {hy}",
        })
    m_list = MONTHS_EN if is_en else MONTHS_FR
    return {"year": year, "month": month, "month_label": f"{m_list[month - 1].capitalize()} {year}",
            "utc_offset": off, "events": events, "days": days, "lang": lang}

# ─────────────────────────── Analyse Hilal (début de mois) ───────────────────────────

def _crescent_summary(lat, lon, off, d, nm, lang: str = "fr"):
    """Visibilité du croissant le soir du jour d, pour la conjonction nm."""
    obs = observer(lat, lon)
    sunset = _sunset_on(obs, d, off)
    moonset = _nearest(_events(almanac.find_settings, obs, MOON, shift(sunset, -0.5), shift(sunset, 0.6)), sunset)
    age_h = (sunset.tt - nm.tt) * 24.0  # négatif si la conjonction a lieu après le coucher du Soleil
    c = crescent_eval(obs, sunset, moonset, age_h, lang=lang)
    out = _clean_crescent(c, off)
    out.update({"date": d.isoformat(), "date_label": fr_date(d, lang=lang), "sunset": hm(sunset, off),
                "moonset": hm(moonset, off), "sunset_utc": sunset.utc_datetime().strftime("%Y-%m-%dT%H:%M")})
    return out


def _start_dates(evenings, lang: str = "fr"):
    naked = next((e for e in evenings if e["verdict_code"] == "naked_eye"), None)
    optical = next((e for e in evenings if e["verdict_code"] in ("naked_eye", "naked_eye_possible", "optical_only")),
                   None)
    last = dt.date.fromisoformat(evenings[-1]["date"])

    def nxt(e):
        return dt.date.fromisoformat(e["date"]) + dt.timedelta(days=1) if e else last + dt.timedelta(days=1)

    sn, so = nxt(naked), nxt(optical)
    return {"start_naked_eye": sn.isoformat(), "start_naked_eye_label": fr_date(sn, lang=lang),
            "start_with_instruments": so.isoformat(), "start_with_instruments_label": fr_date(so, lang=lang),
            "first_naked_eye_evening": naked["date"] if naked else None}


def country_main_cities(country_code: str, lang: str | None = None) -> list:
    """Retourne uniquement les villes principales du pays de l'utilisateur (1 à 2 par région)."""
    lang = resolve_lang(lang, country_code)
    cat = COUNTRIES_CATALOG.get((country_code or "SN").upper(), COUNTRIES_CATALOG["SN"])
    cname = country_display_name(cat["code"], cat["name"], lang=lang)
    flag = cat["flag"]
    default_tz = cat["tz"]
    out = []
    for reg in cat["regions"]:
        for idx, loc in enumerate(reg["localities"]):
            # On prend le chef-lieu de chaque région + les grandes cités religieuses
            if idx == 0 or "religieuse" in loc.get("type", "").lower() or "capitale" in loc.get("type", "").lower():
                out.append({
                    "name": loc["name"].split(" (")[0],
                    "full_name": loc["name"],
                    "region": reg["region"],
                    "country": cname,
                    "country_code": cat["code"],
                    "flag": flag,
                    "lat": loc["lat"],
                    "lon": loc["lon"],
                    "tz": loc.get("tz", default_tz),
                })
    return out


def hilal_from_new_moon(nm, lat, lon, off, country_code: str = "SN", lang: str | None = None):
    lang = resolve_lang(lang, country_code)
    is_en = lang == "en"
    at_word = "at" if is_en else "à"
    conj = t_to_local(nm, off)
    hy, hmo, hname = month_starting_after(conj.date(), lang=lang)
    evening_dates = [conj.date() + dt.timedelta(days=k) for k in range(3)]
    loc_evenings = [_crescent_summary(lat, lon, off, d, nm, lang=lang) for d in evening_dates]
    target_cities = country_main_cities(country_code, lang=lang)
    cities = []
    for c in target_cities:
        ev = [_crescent_summary(c["lat"], c["lon"], c["tz"], d, nm, lang=lang) for d in evening_dates]
        cities.append({**c, "evenings": ev, **_start_dates(ev, lang=lang)})
    return {
        "conjunction_local": conj.strftime("%Y-%m-%dT%H:%M"),
        "conjunction_label": f"{fr_date(conj.date(), lang=lang)} {at_word} {conj.strftime('%H:%M')}",
        "conjunction_utc": nm.utc_datetime().strftime("%Y-%m-%dT%H:%M"),
        "hijri_month": hname, "hijri_month_number": hmo, "hijri_year": hy,
        "country_code": (country_code or "SN").upper(),
        "evenings": [{"date": d.isoformat(), "label": fr_date(d, lang=lang)} for d in evening_dates],
        "location": {"evenings": loc_evenings, **_start_dates(loc_evenings, lang=lang)},
        "cities": cities,
        "lang": lang,
    }


def hilal_analysis(lat, lon, off, from_date: dt.date, country_code: str = "SN", lang: str | None = None):
    t0 = local_to_t(from_date - dt.timedelta(days=1), 0, off)
    nm = new_moons_between(t0, shift(t0, 32))[0]
    return hilal_from_new_moon(nm, lat, lon, off, country_code, lang=lang)


def hijri_month_analysis(lat, lon, off, target_month: int, from_date: dt.date, country_code: str = "SN", lang: str | None = None):
    t0 = local_to_t(from_date - dt.timedelta(days=27), 0, off)
    for nm in new_moons_between(t0, shift(t0, 420)):
        _, m, _ = month_starting_after(t_to_local(nm, off).date())
        if m == target_month:
            return hilal_from_new_moon(nm, lat, lon, off, country_code, lang=lang)
    raise ValueError("Mois introuvable")


# ─────────────────────────── 14 Régions du Sénégal & Pays (Afrique de l'Ouest & Monde) ───────────────────────────

COUNTRIES_CATALOG = {
    "SN": {
        "code": "SN",
        "name": "Sénégal (14 Régions)",
        "flag": "🇸🇳",
        "tz": 0,
        "regions": [
            {"region": "Dakar", "localities": [
                {"name": "Dakar (Pointe des Almadies)", "type": "Cap le plus à l'Ouest", "lat": 14.7442, "lon": -17.5293},
                {"name": "Dakar Plateau", "type": "Capitale", "lat": 14.6937, "lon": -17.4441},
                {"name": "Pikine", "type": "Département", "lat": 14.7546, "lon": -17.3907},
                {"name": "Guédiawaye", "type": "Département", "lat": 14.7761, "lon": -17.3964},
                {"name": "Rufisque", "type": "Département", "lat": 14.7153, "lon": -17.2733},
            ]},
            {"region": "Thiès", "localities": [
                {"name": "Thiès", "type": "Chef-lieu", "lat": 14.7886, "lon": -16.9260},
                {"name": "Tivaouane", "type": "Cité religieuse & Département", "lat": 14.9514, "lon": -16.8189},
                {"name": "Mbour", "type": "Département côtier", "lat": 14.4167, "lon": -16.9667},
                {"name": "Ndiassane", "type": "Foyer religieux", "lat": 14.8350, "lon": -16.8450},
                {"name": "Joal-Fadiouth", "type": "Commune côtière", "lat": 14.1667, "lon": -16.8333},
            ]},
            {"region": "Diourbel", "localities": [
                {"name": "Touba", "type": "Cité religieuse", "lat": 14.8647, "lon": -15.8756},
                {"name": "Diourbel", "type": "Chef-lieu", "lat": 14.6550, "lon": -16.2314},
                {"name": "Mbacké", "type": "Département", "lat": 14.7903, "lon": -15.9086},
                {"name": "Bambey", "type": "Département", "lat": 14.6989, "lon": -16.4533},
            ]},
            {"region": "Saint-Louis", "localities": [
                {"name": "Saint-Louis (Ndar)", "type": "Chef-lieu côtier", "lat": 16.0179, "lon": -16.4896},
                {"name": "Richard-Toll", "type": "Commune", "lat": 16.4625, "lon": -15.7008},
                {"name": "Dagana", "type": "Département", "lat": 16.5167, "lon": -15.5000},
                {"name": "Podor", "type": "Département", "lat": 16.6528, "lon": -14.9589},
            ]},
            {"region": "Louga", "localities": [
                {"name": "Louga", "type": "Chef-lieu", "lat": 15.6186, "lon": -16.2244},
                {"name": "Kébémer", "type": "Département", "lat": 15.3667, "lon": -16.4333},
                {"name": "Linguère", "type": "Département", "lat": 15.3953, "lon": -15.1192},
                {"name": "Dahra Djolof", "type": "Commune", "lat": 15.3483, "lon": -15.4792},
            ]},
            {"region": "Kaolack", "localities": [
                {"name": "Kaolack (Médina Baye)", "type": "Chef-lieu & Cité religieuse", "lat": 14.1520, "lon": -16.0726},
                {"name": "Nioro du Rip", "type": "Département", "lat": 13.7500, "lon": -15.7833},
                {"name": "Guinguinéo", "type": "Département", "lat": 14.2667, "lon": -15.9500},
            ]},
            {"region": "Fatick", "localities": [
                {"name": "Fatick", "type": "Chef-lieu", "lat": 14.3390, "lon": -16.4111},
                {"name": "Foundiougne", "type": "Département", "lat": 14.1333, "lon": -16.4667},
                {"name": "Gossas", "type": "Département", "lat": 14.4833, "lon": -16.0667},
                {"name": "Sokone", "type": "Commune", "lat": 13.8833, "lon": -16.3667},
            ]},
            {"region": "Kaffrine", "localities": [
                {"name": "Kaffrine", "type": "Chef-lieu", "lat": 14.1059, "lon": -15.5508},
                {"name": "Birkelane", "type": "Département", "lat": 14.1333, "lon": -15.7500},
                {"name": "Koungheul", "type": "Département", "lat": 13.9833, "lon": -14.8000},
                {"name": "Malem-Hodar", "type": "Département", "lat": 14.0886, "lon": -15.2914},
            ]},
            {"region": "Matam", "localities": [
                {"name": "Matam", "type": "Chef-lieu", "lat": 15.6559, "lon": -13.2554},
                {"name": "Ourossogui", "type": "Commune", "lat": 15.6058, "lon": -13.3214},
                {"name": "Kanel", "type": "Département", "lat": 15.4917, "lon": -13.1764},
                {"name": "Ranérou", "type": "Département", "lat": 15.3000, "lon": -13.9667},
            ]},
            {"region": "Tambacounda", "localities": [
                {"name": "Tambacounda", "type": "Chef-lieu", "lat": 13.7707, "lon": -13.6673},
                {"name": "Bakel", "type": "Département", "lat": 14.9019, "lon": -12.4583},
                {"name": "Koumpentoum", "type": "Département", "lat": 13.9833, "lon": -14.5500},
                {"name": "Goudiry", "type": "Département", "lat": 14.1833, "lon": -12.7167},
            ]},
            {"region": "Kédougou", "localities": [
                {"name": "Kédougou", "type": "Chef-lieu", "lat": 12.5579, "lon": -12.1743},
                {"name": "Saraya", "type": "Département", "lat": 12.8322, "lon": -11.7539},
                {"name": "Salémata", "type": "Département", "lat": 12.6300, "lon": -12.8150},
            ]},
            {"region": "Kolda", "localities": [
                {"name": "Kolda", "type": "Chef-lieu", "lat": 12.8939, "lon": -14.9412},
                {"name": "Vélingara", "type": "Département", "lat": 13.1500, "lon": -14.1167},
                {"name": "Médina Yoro Foulah", "type": "Département", "lat": 13.3100, "lon": -14.7167},
            ]},
            {"region": "Sédhiou", "localities": [
                {"name": "Sédhiou", "type": "Chef-lieu", "lat": 12.7081, "lon": -15.5569},
                {"name": "Bounkiling", "type": "Département", "lat": 13.0375, "lon": -15.6964},
                {"name": "Goudomp", "type": "Département", "lat": 12.5778, "lon": -15.8722},
            ]},
            {"region": "Ziguinchor", "localities": [
                {"name": "Cap Skirring", "type": "Pointe Sud-Ouest côtière", "lat": 12.3894, "lon": -16.7422},
                {"name": "Ziguinchor", "type": "Chef-lieu", "lat": 12.5681, "lon": -16.2719},
                {"name": "Bignona", "type": "Département", "lat": 12.8103, "lon": -16.2264},
                {"name": "Oussouye", "type": "Département", "lat": 12.4850, "lon": -16.5469},
            ]},
        ],
    },
    "ML": {
        "code": "ML", "name": "Mali", "flag": "🇲🇱", "tz": 0,
        "regions": [
            {"region": "Ouest & Kayes", "localities": [
                {"name": "Kayes", "type": "Chef-lieu", "lat": 14.4469, "lon": -11.4445},
                {"name": "Nioro du Sahel", "type": "Cité religieuse", "lat": 15.2281, "lon": -9.5767},
                {"name": "Kita", "type": "Cercle", "lat": 13.0349, "lon": -9.4895},
            ]},
            {"region": "Bamako & Centre", "localities": [
                {"name": "Bamako", "type": "Capitale", "lat": 12.6392, "lon": -8.0029},
                {"name": "Ségou", "type": "Chef-lieu", "lat": 13.4317, "lon": -6.2157},
                {"name": "Sikasso", "type": "Chef-lieu Sud", "lat": 11.3176, "lon": -5.6665},
                {"name": "Mopti", "type": "Chef-lieu", "lat": 14.4843, "lon": -4.1829},
            ]},
            {"region": "Nord & Est", "localities": [
                {"name": "Tombouctou", "type": "Cité historique", "lat": 16.7666, "lon": -3.0026},
                {"name": "Gao", "type": "Chef-lieu", "lat": 16.2717, "lon": -0.0447},
                {"name": "Kidal", "type": "Chef-lieu", "lat": 18.4411, "lon": 1.4078},
            ]},
        ],
    },
    "MR": {
        "code": "MR", "name": "Mauritanie", "flag": "🇲🇷", "tz": 0,
        "regions": [
            {"region": "Littoral & Fleuve", "localities": [
                {"name": "Nouadhibou", "type": "Cap Blanc (Ouest)", "lat": 20.9310, "lon": -17.0347},
                {"name": "Nouakchott", "type": "Capitale", "lat": 18.0735, "lon": -15.9582},
                {"name": "Rosso", "type": "Trarza", "lat": 16.5138, "lon": -15.8050},
                {"name": "Kaédi", "type": "Gorgol", "lat": 16.1503, "lon": -13.5037},
            ]},
            {"region": "Intérieur & Est", "localities": [
                {"name": "Atar", "type": "Adrar", "lat": 20.5169, "lon": -13.0499},
                {"name": "Kiffa", "type": "Assaba", "lat": 16.6207, "lon": -11.4021},
                {"name": "Néma", "type": "Hodh Ech Chargui", "lat": 16.6170, "lon": -7.2535},
            ]},
        ],
    },
    "CI": {
        "code": "CI", "name": "Côte d'Ivoire", "flag": "🇨🇮", "tz": 0,
        "regions": [
            {"region": "Sud & Littoral", "localities": [
                {"name": "San-Pédro", "type": "Sud-Ouest côtier", "lat": 4.7485, "lon": -6.6363},
                {"name": "Abidjan", "type": "Métropole", "lat": 5.3600, "lon": -4.0083},
                {"name": "Yamoussoukro", "type": "Capitale", "lat": 6.8276, "lon": -5.2893},
            ]},
            {"region": "Centre, Ouest & Nord", "localities": [
                {"name": "Man", "type": "Montagnes (Ouest)", "lat": 7.4125, "lon": -7.5538},
                {"name": "Odienné", "type": "Kabadougou (Nord-Ouest)", "lat": 9.5051, "lon": -7.5643},
                {"name": "Bouaké", "type": "Gbêkê", "lat": 7.6939, "lon": -5.0303},
                {"name": "Korhogo", "type": "Poro (Nord)", "lat": 9.4580, "lon": -5.6296},
            ]},
        ],
    },
    "GN": {
        "code": "GN", "name": "Guinée", "flag": "🇬🇳", "tz": 0,
        "regions": [
            {"region": "Basse-Guinée & Fouta", "localities": [
                {"name": "Conakry", "type": "Capitale côtière", "lat": 9.6412, "lon": -13.5784},
                {"name": "Boké", "type": "Nord-Ouest", "lat": 10.9409, "lon": -14.2967},
                {"name": "Kindia", "type": "Chef-lieu", "lat": 10.0569, "lon": -12.8658},
                {"name": "Labé", "type": "Fouta-Djalon", "lat": 11.3182, "lon": -12.2833},
            ]},
            {"region": "Haute-Guinée & Forêt", "localities": [
                {"name": "Kankan", "type": "Chef-lieu", "lat": 10.3854, "lon": -9.3057},
                {"name": "Nzérékoré", "type": "Guinée forestière", "lat": 7.7562, "lon": -8.8179},
            ]},
        ],
    },
    "BF": {
        "code": "BF", "name": "Burkina Faso", "flag": "🇧🇫", "tz": 0,
        "regions": [
            {"region": "Ouest & Centre", "localities": [
                {"name": "Banfora", "type": "Cascades (Sud-Ouest)", "lat": 10.6333, "lon": -4.7667},
                {"name": "Bobo-Dioulasso", "type": "Hauts-Bassins", "lat": 11.1771, "lon": -4.2979},
                {"name": "Ouagadougou", "type": "Capitale", "lat": 12.3714, "lon": -1.5197},
                {"name": "Ouahigouya", "type": "Nord", "lat": 13.5828, "lon": -2.4216},
                {"name": "Dori", "type": "Sahel (Est)", "lat": 14.0354, "lon": -0.0345},
            ]},
        ],
    },
    "NE": {
        "code": "NE", "name": "Niger", "flag": "🇳🇪", "tz": 1,
        "regions": [
            {"region": "Ouest, Centre & Est", "localities": [
                {"name": "Niamey", "type": "Capitale (Ouest)", "lat": 13.5116, "lon": 2.1254},
                {"name": "Dosso", "type": "Sud-Ouest", "lat": 13.0490, "lon": 3.1937},
                {"name": "Tahoua", "type": "Centre", "lat": 14.8888, "lon": 5.2692},
                {"name": "Maradi", "type": "Sud-Centre", "lat": 13.5000, "lon": 7.1017},
                {"name": "Agadez", "type": "Aïr (Nord)", "lat": 16.9733, "lon": 7.9911},
                {"name": "Zinder", "type": "Damagaram", "lat": 13.8069, "lon": 8.9881},
                {"name": "Diffa", "type": "Extrême-Est", "lat": 13.3154, "lon": 12.6113},
            ]},
        ],
    },
    "GM": {
        "code": "GM", "name": "Gambie", "flag": "🇬🇲", "tz": 0,
        "regions": [
            {"region": "Banjul & Kanifing", "localities": [
                {"name": "Banjul", "type": "Capitale", "lat": 13.4549, "lon": -16.5790},
                {"name": "Serekunda", "type": "Kanifing", "lat": 13.4383, "lon": -16.6781},
            ]},
            {"region": "West Coast & Lower River", "localities": [
                {"name": "Brikama", "type": "West Coast", "lat": 13.2714, "lon": -16.6494},
                {"name": "Mansa Konko", "type": "Lower River", "lat": 13.4667, "lon": -15.5500},
            ]},
            {"region": "North Bank, Central & Upper River", "localities": [
                {"name": "Kerewan", "type": "North Bank", "lat": 13.4898, "lon": -16.0888},
                {"name": "Farafenni", "type": "North Bank", "lat": 13.5667, "lon": -15.6000},
                {"name": "Janjanbureh", "type": "Central River", "lat": 13.5333, "lon": -14.7667},
                {"name": "Basse Santa Su", "type": "Upper River", "lat": 13.3099, "lon": -14.2137},
            ]},
        ],
    },
    "TG": {
        "code": "TG", "name": "Togo", "flag": "🇹🇬", "tz": 0,
        "regions": [
            {"region": "Maritime & Plateaux", "localities": [
                {"name": "Lomé", "type": "Capitale", "lat": 6.1375, "lon": 1.2125},
                {"name": "Kpalimé", "type": "Plateaux Ouest", "lat": 6.9000, "lon": 0.6333},
                {"name": "Atakpamé", "type": "Plateaux", "lat": 7.5333, "lon": 1.1333},
            ]},
            {"region": "Centrale, Kara & Savanes", "localities": [
                {"name": "Sokodé", "type": "Centrale", "lat": 8.9833, "lon": 1.1333},
                {"name": "Kara", "type": "Kara", "lat": 9.5511, "lon": 1.1861},
                {"name": "Dapaong", "type": "Savanes (Nord)", "lat": 10.8622, "lon": 0.2076},
            ]},
        ],
    },
    "BJ": {
        "code": "BJ", "name": "Bénin", "flag": "🇧🇯", "tz": 1,
        "regions": [
            {"region": "Sud & Littoral", "localities": [
                {"name": "Cotonou", "type": "Métropole", "lat": 6.3654, "lon": 2.4183},
                {"name": "Porto-Novo", "type": "Capitale", "lat": 6.4969, "lon": 2.6289},
                {"name": "Abomey", "type": "Zou", "lat": 7.1829, "lon": 1.9912},
            ]},
            {"region": "Centre & Nord", "localities": [
                {"name": "Parakou", "type": "Borgou", "lat": 9.3372, "lon": 2.6303},
                {"name": "Djougou", "type": "Donga (Nord-Ouest)", "lat": 9.7085, "lon": 1.6660},
                {"name": "Natitingou", "type": "Atacora", "lat": 10.3042, "lon": 1.3796},
                {"name": "Kandi", "type": "Alibori", "lat": 11.1342, "lon": 2.9386},
            ]},
        ],
    },
    "GW": {
        "code": "GW", "name": "Guinée-Bissau", "flag": "🇬🇼", "tz": 0,
        "regions": [
            {"region": "Littoral & Intérieur", "localities": [
                {"name": "Bissau", "type": "Capitale", "lat": 11.8636, "lon": -15.5977},
                {"name": "Cacheu", "type": "Nord-Ouest côtier", "lat": 12.2744, "lon": -16.1656},
                {"name": "Bafatá", "type": "Centre", "lat": 12.1719, "lon": -14.6575},
                {"name": "Gabú", "type": "Est", "lat": 12.2800, "lon": -14.2222},
            ]},
        ],
    },
    "CV": {
        "code": "CV", "name": "Cap-Vert", "flag": "🇨🇻", "tz": -1,
        "regions": [
            {"region": "Archipel (Sotavento & Barlavento)", "localities": [
                {"name": "Mindelo (São Vicente)", "type": "Nord-Ouest", "lat": 16.8901, "lon": -24.9804, "tz": -1},
                {"name": "Praia (Santiago)", "type": "Capitale", "lat": 14.9330, "lon": -23.5133, "tz": -1},
                {"name": "Espargos (Sal)", "type": "Est", "lat": 16.7552, "lon": -22.9446, "tz": -1},
            ]},
        ],
    },
    "GH": {
        "code": "GH", "name": "Ghana", "flag": "🇬🇭", "tz": 0,
        "regions": [
            {"region": "Sud, Centre & Nord", "localities": [
                {"name": "Accra", "type": "Capitale", "lat": 5.6037, "lon": -0.1870},
                {"name": "Takoradi", "type": "Sud-Ouest", "lat": 4.8845, "lon": -1.7554},
                {"name": "Kumasi", "type": "Ashanti", "lat": 6.6885, "lon": -1.6244},
                {"name": "Tamale", "type": "Nord", "lat": 9.4034, "lon": -0.8424},
            ]},
        ],
    },
    "NG": {
        "code": "NG", "name": "Nigeria", "flag": "🇳🇬", "tz": 1,
        "regions": [
            {"region": "Ouest, Centre & Nord", "localities": [
                {"name": "Lagos", "type": "Sud-Ouest", "lat": 6.5244, "lon": 3.3792},
                {"name": "Abuja", "type": "Capitale", "lat": 9.0765, "lon": 7.3986},
                {"name": "Sokoto", "type": "Nord-Ouest", "lat": 13.0059, "lon": 5.2476},
                {"name": "Kano", "type": "Nord", "lat": 12.0022, "lon": 8.5920},
                {"name": "Maiduguri", "type": "Nord-Est", "lat": 11.8311, "lon": 13.1510},
            ]},
        ],
    },
    "SL": {
        "code": "SL", "name": "Sierra Leone", "flag": "🇸🇱", "tz": 0,
        "regions": [
            {"region": "Ouest & Provinces", "localities": [
                {"name": "Freetown", "type": "Capitale", "lat": 8.4657, "lon": -13.2317},
                {"name": "Bo", "type": "Sud", "lat": 7.9647, "lon": -11.7383},
                {"name": "Makeni", "type": "Nord", "lat": 8.8861, "lon": -12.0442},
            ]},
        ],
    },
    "LR": {
        "code": "LR", "name": "Liberia", "flag": "🇱🇷", "tz": 0,
        "regions": [
            {"region": "Montserrado & Comtés", "localities": [
                {"name": "Monrovia", "type": "Capitale", "lat": 6.3156, "lon": -10.8074},
                {"name": "Buchanan", "type": "Grand Bassa", "lat": 5.8808, "lon": -10.0467},
                {"name": "Gbarnga", "type": "Bong", "lat": 6.9956, "lon": -9.4722},
            ]},
        ],
    },
    "WORLD": {
        "code": "WORLD", "name": "Monde & Lieux Saints", "flag": "🌍", "tz": 0,
        "regions": [
            {"region": "Lieux Saints & Monde Arabe", "localities": [
                {"name": "La Mecque (Makkah)", "type": "Arabie Saoudite 🇸🇦", "lat": 21.4225, "lon": 39.8262, "tz": 3},
                {"name": "Médine (Al-Madinah)", "type": "Arabie Saoudite 🇸🇦", "lat": 24.4672, "lon": 39.6112, "tz": 3},
                {"name": "Rabat", "type": "Maroc 🇲🇦", "lat": 34.0209, "lon": -6.8416, "tz": 1},
                {"name": "Casablanca", "type": "Maroc 🇲🇦", "lat": 33.5731, "lon": -7.5898, "tz": 1},
                {"name": "Alger", "type": "Algérie 🇩🇿", "lat": 36.7538, "lon": 3.0588, "tz": 1},
                {"name": "Tunis", "type": "Tunisie 🇹🇳", "lat": 36.8065, "lon": 10.1815, "tz": 1},
                {"name": "Le Caire", "type": "Égypte 🇪🇬", "lat": 30.0444, "lon": 31.2357, "tz": 2},
                {"name": "Istanbul", "type": "Turquie 🇹🇷", "lat": 41.0082, "lon": 28.9784, "tz": 3},
            ]},
            {"region": "Europe, Amériques & Asie", "localities": [
                {"name": "Dakar", "type": "Sénégal 🇸🇳", "lat": 14.6937, "lon": -17.4441, "tz": 0},
                {"name": "Paris", "type": "France 🇫🇷", "lat": 48.8566, "lon": 2.3522, "tz": 1},
                {"name": "Londres", "type": "Royaume-Uni 🇬🇧", "lat": 51.5072, "lon": -0.1276, "tz": 0},
                {"name": "New York", "type": "États-Unis 🇺🇸", "lat": 40.7128, "lon": -74.0060, "tz": -5},
                {"name": "Jakarta", "type": "Indonésie 🇮🇩", "lat": -6.2088, "lon": 106.8456, "tz": 7},
            ]},
        ],
    },
}


def scan_country_regions(country_code: str, d: dt.date, hijri_month: int = 0, day_offset: int = -1, lang: str | None = None) -> dict:
    """
    Analyse complète de toutes les régions/villes d'un pays.
    - Si hijri_month in 1..12 : cible la conjonction de ce mois hégirien (ex: 9 = Ramadan).
    - Si day_offset in (0, 1, 2) : choisit le soir J+day_offset après la conjonction.
    """
    lang = resolve_lang(lang, country_code)
    is_en = lang == "en"
    cat = COUNTRIES_CATALOG.get(country_code.upper(), COUNTRIES_CATALOG["SN"])
    default_tz = cat["tz"]

    if 1 <= hijri_month <= 12:
        t0 = local_to_t(d - dt.timedelta(days=27), 0, default_tz)
        nm = None
        for cand in new_moons_between(t0, shift(t0, 420)):
            _, m, _ = month_starting_after(t_to_local(cand, default_tz).date(), lang=lang)
            if m == hijri_month:
                nm = cand
                break
        if nm is None:
            nm = new_moons_between(t0, shift(t0, 35))[0]
    else:
        ref_t = local_to_t(d, 19, default_tz)
        prev_nm, next_nm = surrounding_new_moons(shift(ref_t, 0.05))
        age_prev_d = (ref_t.tt - prev_nm.tt)
        nm = prev_nm if age_prev_d <= 4.0 else next_nm

    conj_local = t_to_local(nm, default_tz)
    evening_dates = [conj_local.date() + dt.timedelta(days=k) for k in range(3)]
    if day_offset in (0, 1, 2):
        d = evening_dates[day_offset]
    elif hijri_month > 0 and d not in evening_dates:
        d = evening_dates[1]  # par défaut J+1 (soirée décisive)

    all_locs = []
    regions_out = []

    for reg in cat["regions"]:
        loc_list = []
        for loc in reg["localities"]:
            tz = loc.get("tz", default_tz)
            c = _crescent_summary(loc["lat"], loc["lon"], tz, d, nm, lang=lang)
            odeh_v = c["odeh"]["v"] if c.get("possible") and c.get("odeh") else -99.0
            yallop_q = c["yallop"]["q"] if c.get("possible") and c.get("yallop") else -9.9
            item = {
                "name": loc["name"],
                "type": translate_locality_type(loc["type"], lang=lang),
                "region": reg["region"],
                "lat": loc["lat"],
                "lon": loc["lon"],
                "tz": tz,
                "sunset": c["sunset"],
                "moonset": c["moonset"],
                "lag_minutes": c["lag_minutes"],
                "age_hours": c["age_hours"],
                "possible": c["possible"],
                "verdict_code": c["verdict_code"],
                "verdict_text": c["verdict_text"],
                "level": c["level"],
                "odeh_v": odeh_v if odeh_v > -90 else None,
                "odeh_code": c["odeh"]["code"] if c.get("possible") and c.get("odeh") else "D",
                "yallop_q": yallop_q if yallop_q > -9 else None,
                "yallop_code": c["yallop"]["code"] if c.get("possible") and c.get("yallop") else "F",
                "moon_alt": c.get("moon_alt"),
                "arcl": c.get("arcl"),
                "_score": odeh_v if c.get("possible") else (-50.0 + (c.get("lag_minutes") or -60) * 0.1),
            }
            loc_list.append(item)
            all_locs.append(item)

        best_reg = max(loc_list, key=lambda x: x["_score"])
        regions_out.append({
            "region": reg["region"],
            "best_locality": best_reg["name"],
            "verdict_code": best_reg["verdict_code"],
            "verdict_text": best_reg["verdict_text"],
            "level": best_reg["level"],
            "odeh_v": best_reg["odeh_v"],
            "localities": loc_list,
        })

    # Point Sentinelle = localité ayant le score astronomique maximal dans tout le pays
    sentinel = max(all_locs, key=lambda x: x["_score"])
    worst = min(all_locs, key=lambda x: x["_score"])

    counts = {
        "naked_eye": sum(1 for x in all_locs if x["verdict_code"] == "naked_eye"),
        "naked_eye_possible": sum(1 for x in all_locs if x["verdict_code"] == "naked_eye_possible"),
        "optical_only": sum(1 for x in all_locs if x["verdict_code"] == "optical_only"),
        "not_visible": sum(1 for x in all_locs if x["verdict_code"] == "not_visible"),
        "total": len(all_locs),
    }

    clean_country = country_display_name(cat["code"], cat["name"], lang=lang)
    if sentinel["verdict_code"] == "not_visible":
        if is_en:
            rule_title = f"IMPOSSIBLE TO SEE ANYWHERE IN THE COUNTRY ({clean_country})"
            rule_text = (
                f"The most geographically favorable point is {sentinel['name']} ({sentinel['region']} Region). "
                f"Even at this National Sentinel Point, the crescent is scientifically invisible "
                f"({sentinel['verdict_text'].lower()}). By the laws of celestial mechanics, "
                f"if the Moon cannot be seen at the most favorable location, it is mathematically impossible "
                f"to sight it in any other region, city, or village tonight."
            )
        else:
            rule_title = f"IMPOSSIBLE À VOIR DANS TOUT LE PAYS ({clean_country})"
            rule_text = (
                f"Le point géographiquement le plus favorable est {sentinel['name']} (Région de {sentinel['region']}). "
                f"Même en ce Point Sentinelle, le croissant est scientifiquement invisible "
                f"({sentinel['verdict_text'].lower()}). D'après les lois de la mécanique céleste, "
                f"si la Lune n'est pas visible au point le plus favorable, il est mathématiquement impossible "
                f"de l'apercevoir dans aucune autre région, ville ou village ce soir-là."
            )
        rule_level = "bad"
    elif counts["naked_eye"] == counts["total"]:
        if is_en:
            rule_title = f"VISIBLE TO THE NAKED EYE IN ALL REGIONS ({clean_country})"
            rule_text = (
                f"The crescent is visible to the naked eye across all {counts['total']} analyzed localities "
                f"(from Sentinel Point {sentinel['name']} to {worst['name']}), provided the sky is clear."
            )
        else:
            rule_title = f"VISIBLE À L'ŒIL NU DANS TOUTES LES RÉGIONS ({clean_country})"
            rule_text = (
                f"Le croissant est visible à l'œil nu dans les {counts['total']} localités analysées "
                f"(du Point Sentinelle {sentinel['name']} jusqu'à {worst['name']}), sous réserve d'un ciel dégagé."
            )
        rule_level = "good"
    else:
        if is_en:
            rule_title = f"REGIONAL VISIBILITY VARIATION ({clean_country})"
            rule_text = (
                f"The most favorable Sentinel Point is {sentinel['name']} ({sentinel['region']}) with "
                f"V = {sentinel['odeh_v'] if sentinel['odeh_v'] is not None else '—'} ({sentinel['verdict_text']}). "
                f"Summary: {counts['naked_eye']} locality(ies) visible to the naked eye, "
                f"{counts['naked_eye_possible']} possible with optical aid, "
                f"{counts['optical_only']} with instruments only, and {counts['not_visible']} not visible."
            )
        else:
            rule_title = f"VISIBILITÉ DIFFÉRENCIÉE SELON LES RÉGIONS ({clean_country})"
            rule_text = (
                f"Le Point Sentinelle le plus favorable est {sentinel['name']} ({sentinel['region']}) avec "
                f"V = {sentinel['odeh_v'] if sentinel['odeh_v'] is not None else '—'} ({sentinel['verdict_text']}). "
                f"Bilan : {counts['naked_eye']} localité(s) visible(s) à l'œil nu, "
                f"{counts['naked_eye_possible']} possible(s) avec repérage optique, "
                f"{counts['optical_only']} aux instruments uniquement, et {counts['not_visible']} non visible(s)."
            )
        rule_level = "maybe" if (counts["naked_eye"] + counts["naked_eye_possible"]) > 0 else "optical"

    for x in all_locs:
        x.pop("_score", None)

    hy, _, hname = month_starting_after(conj_local.date(), lang=lang)
    at_word = "at" if is_en else "à"
    era = "AH" if is_en else "H"

    return {
        "country_code": cat["code"],
        "country_name": clean_country,
        "flag": cat["flag"],
        "date": d.isoformat(),
        "date_label": fr_date(d, lang=lang),
        "evenings": [{"date": ed.isoformat(), "label": fr_date(ed, lang=lang), "index": idx}
                     for idx, ed in enumerate(evening_dates)],
        "hijri_target": f"{hname} {hy} {era}",
        "conjunction_label": f"{fr_date(conj_local.date(), lang=lang)} {at_word} {conj_local.strftime('%H:%M')} (UTC{default_tz:+d})",
        "sentinel": sentinel,
        "rule_title": rule_title,
        "rule_text": rule_text,
        "rule_level": rule_level,
        "counts": counts,
        "regions": regions_out,
        "lang": lang,
    }


def nearest_locality(lat: float, lon: float, lang: str | None = None) -> dict:
    """Trouve la localité répertoriée la plus proche des coordonnées GPS (formule de Haversine)."""
    best = None
    best_dist = 1e9
    for ccode, cat in COUNTRIES_CATALOG.items():
        if ccode == "WORLD":
            continue
        for reg in cat["regions"]:
            for loc in reg["localities"]:
                dlat = math.radians(loc["lat"] - lat)
                dlon = math.radians(loc["lon"] - lon)
                a = (math.sin(dlat / 2) ** 2
                     + math.cos(math.radians(lat)) * math.cos(math.radians(loc["lat"])) * math.sin(dlon / 2) ** 2)
                dist = 6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
                if dist < best_dist:
                    best_dist = dist
                    resolved_lang = resolve_lang(lang, ccode)
                    best = {
                        "name": loc["name"].split(" (")[0],
                        "full_name": loc["name"],
                        "region": reg["region"],
                        "country": country_display_name(ccode, cat["name"], lang=resolved_lang),
                        "country_code": ccode,
                        "flag": cat["flag"],
                        "lat": round(lat, 4),
                        "lon": round(lon, 4),
                        "nearest_name": loc["name"],
                        "distance_km": round(dist, 1),
                        "tz": loc.get("tz", cat["tz"]),
                        "region_count": len(cat["regions"]),
                        "country_cities": country_main_cities(ccode, lang=resolved_lang),
                        "lang": resolved_lang,
                    }
    return best
