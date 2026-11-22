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
HIJRI_MONTHS = [
    "Mouharram", "Safar", "Rabi al-Awwal", "Rabi ath-Thani", "Joumada al-Oula", "Joumada ath-Thania",
    "Rajab", "Chaabane", "Ramadan", "Chawwal", "Dhou al-Qi'da", "Dhou al-Hijja",
]
MONTHS_FR = [
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
]
DAYS_FR = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

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


def fr_date(d: dt.date, with_day=True) -> str:
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


def month_starting_after(conj_local_date: dt.date):
    """Mois hégirien qui commence juste après une conjonction (3 jours après = au cœur du nouveau mois)."""
    y, m, _ = hijri_from_date(conj_local_date + dt.timedelta(days=3))
    return y, m, HIJRI_MONTHS[m - 1]

# ─────────────────────────── Phases ───────────────────────────

def phase_info(t):
    ang = float(almanac.moon_phase(eph, t).degrees)
    illum = float(almanac.fraction_illuminated(eph, "moon", t)) * 100.0
    return ang, illum, ang < 180.0


def phase_name(ang: float) -> str:
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


def yallop(width, arcv):
    q = (arcv - (11.8371 - 6.3226 * width + 0.7319 * width ** 2 - 0.1018 * width ** 3)) / 10.0
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


def odeh(width, arcv):
    v = arcv - (7.1651 - 6.3226 * width + 0.7319 * width ** 2 - 0.1018 * width ** 3)
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
_ODEH_TO_VERDICT = {"A": "naked_eye", "B": "naked_eye_possible", "C": "optical_only", "D": "not_visible"}


def crescent_eval(obs, sunset, moonset, age_h):
    """Évalue la visibilité du croissant au meilleur moment après le coucher du Soleil."""
    lag = (moonset.tt - sunset.tt) * 1440.0 if moonset is not None else None
    base = {"lag_minutes": round(lag) if lag is not None else None, "age_hours": round(age_h, 1)}
    if age_h <= 0:
        return {**base, "possible": False, "verdict_code": "not_visible",
                "verdict_text": "Conjonction après le coucher du Soleil : aucun croissant possible",
                "level": "bad"}
    if lag is None or lag <= 0:
        return {**base, "possible": False, "verdict_code": "not_visible",
                "verdict_text": "La Lune se couche avant le Soleil : croissant impossible à voir",
                "level": "bad"}
    tb = shift(sunset, lag * 4.0 / 9.0 / 1440.0)
    g = geometry(obs, tb)
    y = yallop(g["width"], g["arcv_geo"])
    o = odeh(g["width"], g["arcv_topo"])
    code = _ODEH_TO_VERDICT[o["code"]]
    text, level = VERDICTS[code]
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


def evening_report(lat: float, lon: float, d: dt.date, off: float) -> dict:
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
        crescent = crescent_eval(obs, sunset, moonset, age_h)
        hy, hmo, hname = month_starting_after(t_to_local(prev_nm, off).date())
    elif to_next_h <= 48:
        context = "pre_conjunction"
        hy, hmo, hname = month_starting_after(t_to_local(next_nm, off).date())
    else:
        context = "general"
        hy, hmo, hname = month_starting_after(t_to_local(prev_nm, off).date())

    tomorrow = d + dt.timedelta(days=1)
    if context == "crescent":
        code = crescent["verdict_code"]
        badge = {
            "naked_eye": ("CROISSANT VISIBLE À L'ŒIL NU", "good"),
            "naked_eye_possible": ("CROISSANT : ŒIL NU POSSIBLE, JUMELLES CONSEILLÉES", "maybe"),
            "optical_only": ("CROISSANT VISIBLE AUX INSTRUMENTS SEULEMENT", "optical"),
            "not_visible": ("CROISSANT NON VISIBLE CE SOIR", "bad"),
        }[code]
        visible = code == "naked_eye"
        if crescent["possible"]:
            tip = (f"Regardez vers l'ouest (azimut ≈ {g['moon_az']:.0f}°) entre {hm(sunset, off)} et "
                   f"{hm(moonset, off)}. Meilleur moment : {_clean_crescent(crescent, off)['best_time']}. "
                   f"Odeh : {crescent['odeh']['text'].lower()}. Yallop ({crescent['yallop']['code']}) : "
                   f"{crescent['yallop']['text'].lower()}.")
        else:
            tip = crescent["verdict_text"] + "."
        if code in ("naked_eye", "naked_eye_possible"):
            status = (f"Soirée d'observation du croissant de {hname} {hy} H. S'il est aperçu ce soir, "
                      f"le 1er {hname} sera le {fr_date(tomorrow)}.")
        else:
            status = (f"Soirée d'observation du croissant de {hname} {hy} H. Croissant non visible à l'œil nu : "
                      f"le mois en cours devrait compléter 30 jours (ou débuter après une observation le lendemain).")
    elif context == "pre_conjunction":
        badge = ("PAS DE CROISSANT : NOUVELLE LUNE À VENIR", "bad")
        visible = False
        nm_local = t_to_local(next_nm, off)
        tip = (f"La conjonction (nouvelle lune astronomique) aura lieu le {fr_date(nm_local.date())} à "
               f"{nm_local.strftime('%H:%M')}. Aucun nouveau croissant n'est possible avant cet instant.")
        status = (f"Fin du mois lunaire. Le croissant de {hname} {hy} H pourra être recherché à partir du soir "
                  f"du {fr_date(nm_local.date() if nm_local.hour < 12 else nm_local.date() + dt.timedelta(days=1))}.")
    else:
        badge = ("LUNE PRÉSENTE DANS LE CIEL CETTE NUIT", "good") if present_tonight else (
            "LUNE ABSENTE DU CIEL CE SOIR", "bad")
        visible = present_tonight
        tip = presence
        nm_local = t_to_local(next_nm, off)
        status = (f"Mois lunaire en cours ({hname} {hy} H, estimation) — {age_h / 24:.1f} jours après la "
                  f"nouvelle lune. Prochaine nouvelle lune : {fr_date(nm_local.date())} à {nm_local.strftime('%H:%M')}.")

    if crescent and crescent.get("possible"):
        score = max(0.0, min(1.0, (crescent["odeh"]["v"] + 0.96) / 8.0))
    else:
        score = 1.0 if visible else 0.0

    return {
        "date": d.isoformat(),
        "date_label": fr_date(d),
        "utc_offset": off,
        "context": context,
        "sunset": hm(sunset, off),
        "sunrise_next": hm(sunrise, off),
        "moonset": hm(moonset, off),
        "moonrise_tonight": hm(night_rises[0], off) if night_rises else None,
        "lag_minutes": round((moonset.tt - sunset.tt) * 1440) if moonset is not None else None,
        "phase": phase_name(ang),
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
    }

# ─────────────────────────── Calendrier mensuel ───────────────────────────

def month_calendar(lat: float, lon: float, off: float, year: int, month: int) -> dict:
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

    events = []
    for t, y in phases:
        ld = local_date(t)
        if ld.year == year and ld.month == month:
            events.append({"type": y, "name": PHASE_EVENT_NAMES[y], "date": ld.isoformat(),
                           "time": hm(t, off), "label": f"{fr_date(ld)} à {hm(t, off)}"})

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
            c = crescent_eval(obs, ss, _nearest(msets, ss), age_h)
            crescent = {"verdict_code": c["verdict_code"], "verdict_text": c["verdict_text"], "level": c["level"],
                        "odeh_v": c["odeh"]["v"] if c.get("possible") else None}
        rise_today = [hm(t, off) for t in mrises if local_date(t) == d]
        set_today = [hm(t, off) for t in msets if local_date(t) == d]
        present = g["moon_alt"] > 0 or any(ss.tt < r.tt < ss.tt + 0.5 for r in mrises)
        hy, hmo, hd = hijri_from_date(d)
        days.append({
            "date": d.isoformat(), "day": d.day, "weekday": d.weekday(),
            "phase": phase_name(ang), "phase_angle": round(ang, 1), "illumination": round(illum, 1),
            "waxing": waxing, "sunset": hm(ss, off),
            "moonrise": rise_today[0] if rise_today else None,
            "moonset": set_today[0] if set_today else None,
            "moon_alt_at_sunset": round(g["moon_alt"], 1), "present_tonight": present,
            "age_hours": round(age_h, 1) if age_h < 999 else None,
            "events": [e["name"] for e in events if e["date"] == d.isoformat()],
            "crescent": crescent,
            "hijri_estimate": f"{hd} {HIJRI_MONTHS[hmo - 1]} {hy}",
        })
    return {"year": year, "month": month, "month_label": f"{MONTHS_FR[month - 1].capitalize()} {year}",
            "utc_offset": off, "events": events, "days": days}

# ─────────────────────────── Analyse Hilal (début de mois) ───────────────────────────

def _crescent_summary(lat, lon, off, d, nm):
    """Visibilité du croissant le soir du jour d, pour la conjonction nm."""
    obs = observer(lat, lon)
    sunset = _sunset_on(obs, d, off)
    moonset = _nearest(_events(almanac.find_settings, obs, MOON, shift(sunset, -0.5), shift(sunset, 0.6)), sunset)
    age_h = (sunset.tt - nm.tt) * 24.0  # négatif si la conjonction a lieu après le coucher du Soleil
    c = crescent_eval(obs, sunset, moonset, age_h)
    out = _clean_crescent(c, off)
    out.update({"date": d.isoformat(), "date_label": fr_date(d), "sunset": hm(sunset, off),
                "moonset": hm(moonset, off), "sunset_utc": sunset.utc_datetime().strftime("%Y-%m-%dT%H:%M")})
    return out


def _start_dates(evenings):
    naked = next((e for e in evenings if e["verdict_code"] == "naked_eye"), None)
    optical = next((e for e in evenings if e["verdict_code"] in ("naked_eye", "naked_eye_possible", "optical_only")),
                   None)
    last = dt.date.fromisoformat(evenings[-1]["date"])

    def nxt(e):
        return dt.date.fromisoformat(e["date"]) + dt.timedelta(days=1) if e else last + dt.timedelta(days=1)

    sn, so = nxt(naked), nxt(optical)
    return {"start_naked_eye": sn.isoformat(), "start_naked_eye_label": fr_date(sn),
            "start_with_instruments": so.isoformat(), "start_with_instruments_label": fr_date(so),
            "first_naked_eye_evening": naked["date"] if naked else None}


def hilal_from_new_moon(nm, lat, lon, off):
    conj = t_to_local(nm, off)
    hy, hmo, hname = month_starting_after(conj.date())
    evening_dates = [conj.date() + dt.timedelta(days=k) for k in range(3)]
    loc_evenings = [_crescent_summary(lat, lon, off, d, nm) for d in evening_dates]
    cities = []
    for c in CITIES:
        ev = [_crescent_summary(c["lat"], c["lon"], c["tz"], d, nm) for d in evening_dates]
        cities.append({**c, "evenings": ev, **_start_dates(ev)})
    return {
        "conjunction_local": conj.strftime("%Y-%m-%dT%H:%M"),
        "conjunction_label": f"{fr_date(conj.date())} à {conj.strftime('%H:%M')}",
        "conjunction_utc": nm.utc_datetime().strftime("%Y-%m-%dT%H:%M"),
        "hijri_month": hname, "hijri_month_number": hmo, "hijri_year": hy,
        "evenings": [{"date": d.isoformat(), "label": fr_date(d)} for d in evening_dates],
        "location": {"evenings": loc_evenings, **_start_dates(loc_evenings)},
        "cities": cities,
    }


def hilal_analysis(lat, lon, off, from_date: dt.date):
    t0 = local_to_t(from_date - dt.timedelta(days=1), 0, off)
    nm = new_moons_between(t0, shift(t0, 32))[0]
    return hilal_from_new_moon(nm, lat, lon, off)


def hijri_month_analysis(lat, lon, off, target_month: int, from_date: dt.date):
    t0 = local_to_t(from_date - dt.timedelta(days=27), 0, off)
    for nm in new_moons_between(t0, shift(t0, 420)):
        _, m, _ = month_starting_after(t_to_local(nm, off).date())
        if m == target_month:
            return hilal_from_new_moon(nm, lat, lon, off)
    raise ValueError("Mois introuvable")
