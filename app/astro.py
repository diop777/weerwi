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

    # Direction cardinale & turbulence atmosphérique (masse d'air près de l'horizon)
    dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]
    cardinal = dirs[int(((g["moon_az"] + 11.25) % 360) / 22.5)]
    alt_deg = g["moon_alt"]
    if alt_deg <= 0:
        airmass = None
        turb_level = "Sous l'horizon"
        turb_note = "La Lune est sous l'horizon au coucher du Soleil : aucune lumière directe n'atteint l'observateur."
    else:
        # Formule de Kasten & Young (1989) pour la masse d'air atmosphérique
        airmass = round(1.0 / (math.sin(math.radians(alt_deg)) + 0.50572 * ((alt_deg + 6.07995) ** -1.6364)), 2)
        if alt_deg < 6:
            turb_level = "Forte turbulence d'horizon"
            turb_note = (f"Masse d'air élevée ({airmass}×) à {alt_deg:.1f}° de hauteur : forte absorption, brume, "
                         f"poussière (Harmattan) et scintillation près de l'horizon. Un horizon ouest parfaitement dégagé est indispensable.")
        elif alt_deg < 15:
            turb_level = "Turbulence modérée"
            turb_note = (f"Masse d'air modérée ({airmass}×) à {alt_deg:.1f}° de hauteur : transparence atmosphérique "
                         f"correcte si l'horizon ouest est sans poussière ni brume.")
        else:
            turb_level = "Atmosphère stable (faible extinction)"
            turb_note = f"Masse d'air faible ({airmass}×) à {alt_deg:.1f}° de hauteur : très peu de turbulence atmosphérique."

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


def scan_country_regions(country_code: str, d: dt.date, hijri_month: int = 0, day_offset: int = -1) -> dict:
    """
    Analyse complète de toutes les régions/villes d'un pays.
    - Si hijri_month in 1..12 : cible la conjonction de ce mois hégirien (ex: 9 = Ramadan).
    - Si day_offset in (0, 1, 2) : choisit le soir J+day_offset après la conjonction.
    """
    cat = COUNTRIES_CATALOG.get(country_code.upper(), COUNTRIES_CATALOG["SN"])
    default_tz = cat["tz"]

    if 1 <= hijri_month <= 12:
        t0 = local_to_t(d - dt.timedelta(days=27), 0, default_tz)
        nm = None
        for cand in new_moons_between(t0, shift(t0, 420)):
            _, m, _ = month_starting_after(t_to_local(cand, default_tz).date())
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
            c = _crescent_summary(loc["lat"], loc["lon"], tz, d, nm)
            odeh_v = c["odeh"]["v"] if c.get("possible") and c.get("odeh") else -99.0
            yallop_q = c["yallop"]["q"] if c.get("possible") and c.get("yallop") else -9.9
            item = {
                "name": loc["name"],
                "type": loc["type"],
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

    if sentinel["verdict_code"] == "not_visible":
        rule_title = f"IMPOSSIBLE À VOIR DANS TOUT LE PAYS ({cat['name']})"
        rule_text = (
            f"Le point géographiquement le plus favorable est {sentinel['name']} (Région de {sentinel['region']}). "
            f"Même en ce Point Sentinelle, le croissant est scientifiquement invisible "
            f"({sentinel['verdict_text'].lower()}). D'après les lois de la mécanique céleste, "
            f"si la Lune n'est pas visible au point le plus favorable, il est mathématiquement impossible "
            f"de l'apercevoir dans aucune autre région, ville ou village ce soir-là."
        )
        rule_level = "bad"
    elif counts["naked_eye"] == counts["total"]:
        rule_title = f"VISIBLE À L'ŒIL NU DANS TOUTES LES RÉGIONS ({cat['name']})"
        rule_text = (
            f"Le croissant est visible à l'œil nu dans les {counts['total']} localités analysées "
            f"(du Point Sentinelle {sentinel['name']} jusqu'à {worst['name']}), sous réserve d'un ciel dégagé."
        )
        rule_level = "good"
    else:
        rule_title = f"VISIBILITÉ DIFFÉRENCIÉE SELON LES RÉGIONS ({cat['name']})"
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

    hy, _, hname = month_starting_after(conj_local.date())

    return {
        "country_code": cat["code"],
        "country_name": cat["name"],
        "flag": cat["flag"],
        "date": d.isoformat(),
        "date_label": fr_date(d),
        "evenings": [{"date": ed.isoformat(), "label": fr_date(ed), "index": idx}
                     for idx, ed in enumerate(evening_dates)],
        "hijri_target": f"{hname} {hy} H",
        "conjunction_label": f"{fr_date(conj_local.date())} à {conj_local.strftime('%H:%M')} (UTC{default_tz:+d})",
        "sentinel": sentinel,
        "rule_title": rule_title,
        "rule_text": rule_text,
        "rule_level": rule_level,
        "counts": counts,
        "regions": regions_out,
    }


def nearest_locality(lat: float, lon: float) -> dict:
    """Trouve la localité répertoriée la plus proche des coordonnées GPS (formule de Haversine)."""
    best = None
    best_dist = 1e9
    for ccode, cat in COUNTRIES_CATALOG.items():
        for reg in cat["regions"]:
            for loc in reg["localities"]:
                dlat = math.radians(loc["lat"] - lat)
                dlon = math.radians(loc["lon"] - lon)
                a = (math.sin(dlat / 2) ** 2
                     + math.cos(math.radians(lat)) * math.cos(math.radians(loc["lat"])) * math.sin(dlon / 2) ** 2)
                dist = 6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
                if dist < best_dist:
                    best_dist = dist
                    best = {
                        "name": loc["name"],
                        "region": reg["region"],
                        "country": cat["name"].split(" (")[0],
                        "country_code": ccode,
                        "flag": cat["flag"],
                        "lat": round(lat, 4),
                        "lon": round(lon, 4),
                        "nearest_name": loc["name"],
                        "distance_km": round(dist, 1),
                        "tz": loc.get("tz", cat["tz"]),
                    }
    return best
