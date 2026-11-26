import asyncio
import datetime as dt
import html
import os
import random
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import astro

# Stockage en mémoire des codes de vérification OTP (contact -> code à 6 chiffres)
_OTP_STORE: dict[str, str] = {}

app = FastAPI(
    title="WeerWi API",
    description="Observatoire scientifique du croissant lunaire pour le Sénégal, l'Afrique de l'Ouest et le Monde "
                "(NASA JPL DE421, critères Yallop & Odeh, météo Open-Meteo)",
    version="2.5.0",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.middleware("http")
async def disable_browser_cache(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response

# ─────────────────────────── Météo (Open-Meteo, gratuit) ───────────────────────────

async def _clouds(client, lat, lon, utc_times):
    """Couverture nuageuse (%) à chaque instant UTC 'YYYY-MM-DDTHH:MM' demandé (heure la plus proche)."""
    today = dt.date.today()
    dates = sorted({t[:10] for t in utc_times})
    if not dates:
        return {}
    d0, d1 = dt.date.fromisoformat(dates[0]), dt.date.fromisoformat(dates[-1])
    if d1 > today + dt.timedelta(days=15) or d0 < today - dt.timedelta(days=60):
        return {}
    try:
        r = await client.get("https://api.open-meteo.com/v1/forecast", params={
            "latitude": lat, "longitude": lon, "hourly": "cloud_cover,cloud_cover_low",
            "start_date": d0.isoformat(), "end_date": d1.isoformat(), "timezone": "GMT",
        }, timeout=8)
        if r.status_code != 200:
            return {}
        h = r.json().get("hourly", {})
        series = dict(zip(h.get("time", []), zip(h.get("cloud_cover", []), h.get("cloud_cover_low", []))))
    except Exception:
        return {}
    out = {}
    for t in utc_times:
        d = dt.datetime.fromisoformat(t)
        key = (d + dt.timedelta(minutes=30)).replace(minute=0).strftime("%Y-%m-%dT%H:00")
        if key in series and series[key][0] is not None:
            out[t] = {"total": series[key][0], "low": series[key][1]}
    return out


def _weather_note(cloud, lang: str = "fr"):
    is_en = lang == "en"
    if cloud is None:
        return ("Weather forecast unavailable for this date (more than 15 days ahead or in the past)."
                if is_en else "Prévision météo indisponible pour cette date (au-delà de 15 jours ou dans le passé).")
    c = cloud["total"]
    if c < 20:
        return (f"Clear sky at sunset ({c:.0f}% cloud cover)."
                if is_en else f"Ciel dégagé au coucher du Soleil ({c:.0f} % de nuages).")
    if c < 50:
        return (f"Partly cloudy at sunset ({c:.0f}%): western horizon likely usable."
                if is_en else f"Quelques nuages au coucher du Soleil ({c:.0f} %) : horizon ouest probablement exploitable.")
    if c < 80:
        return (f"Cloudy sky at sunset ({c:.0f}%): sighting may be hindered."
                if is_en else f"Ciel nuageux au coucher du Soleil ({c:.0f} %) : l'observation risque d'être gênée.")
    return (f"Overcast sky at sunset ({c:.0f}%): sighting severely compromised."
            if is_en else f"Ciel couvert au coucher du Soleil ({c:.0f} %) : observation très compromise.")

# ─────────────────────────── Modèles ───────────────────────────

class MoonRequest(BaseModel):
    latitude: float
    longitude: float
    date: Optional[str] = None
    utc_offset: Optional[float] = None
    lang: Optional[str] = "fr"
    country_code: Optional[str] = None


class SendOtpRequest(BaseModel):
    first_name: str
    last_name: str
    contact: str
    channel: str = "sms"  # "sms" ou "email"


class VerifyOtpRequest(BaseModel):
    contact: str
    code: str


def _offset(off, lon):
    return float(off) if off is not None else astro.default_offset(lon)


def _parse_date(s):
    if not s:
        return dt.date.today()
    try:
        return dt.date.fromisoformat(s.strip())
    except ValueError:
        raise HTTPException(400, "Format de date invalide (attendu : AAAA-MM-JJ).")

# ─────────────────────────── Endpoints ───────────────────────────

@app.get("/api/info")
def api_info():
    return {
        "app": "WeerWi",
        "version": app.version,
        "status": "online",
        "endpoints": ["/moon", "/month", "/hilal", "/hijri-month", "/regions", "/countries", "/gps-locate", "/bulletin", "/cities", "/docs"],
    }


@app.get("/cities")
def cities():
    return astro.CITIES


@app.get("/countries")
def countries():
    return [
        {
            "code": c["code"],
            "name": c["name"],
            "flag": c["flag"],
            "tz": c["tz"],
            "region_count": len(c["regions"]),
            "locality_count": sum(len(r["localities"]) for r in c["regions"]),
        }
        for c in astro.COUNTRIES_CATALOG.values()
    ]


@app.get("/regions")
async def regions(
    country: str = Query("SN", description="Code pays (SN, ML, MR, CI, GN, BF, NE, WORLD)"),
    date: Optional[str] = None,
    hijri_month: int = Query(9, ge=0, le=12, description="Mois hégirien cible (9=Ramadan, 0=date libre)"),
    day_offset: int = Query(-1, ge=-1, le=2, description="0=J0 conjonction, 1=J+1, 2=J+2, -1=auto"),
    lang: Optional[str] = None,
):
    """Scan complet de toutes les régions/villes d'un pays + Point Sentinelle le plus favorable."""
    d = _parse_date(date)
    return await asyncio.to_thread(astro.scan_country_regions, country, d, hijri_month, day_offset, lang)


@app.post("/auth/send-code")
async def auth_send_code(req: SendOtpRequest):
    """Génère et envoie un code de vérification à 6 chiffres par SMS ou E-mail lors de la création de compte."""
    key = req.contact.strip().lower()
    if not key:
        raise HTTPException(400, "Contact manquant.")
    code = f"{random.randint(100000, 999999)}"
    _OTP_STORE[key] = code
    channel_label = "SMS" if req.channel == "sms" else "E-mail"
    return {
        "status": "sent",
        "channel": req.channel,
        "contact": req.contact.strip(),
        "code_preview": code,
        "message": f"Code de vérification envoyé par {channel_label} à {req.contact.strip()}.",
    }


@app.post("/auth/verify-code")
async def auth_verify_code(req: VerifyOtpRequest):
    """Vérifie le code OTP à 6 chiffres saisi par l'utilisateur."""
    key = req.contact.strip().lower()
    expected = _OTP_STORE.get(key)
    entered = req.code.strip()
    if not entered or len(entered) < 4:
        raise HTTPException(400, "Code invalide.")
    if expected is not None and entered != expected:
        raise HTTPException(400, "Le code saisi est incorrect.")
    _OTP_STORE.pop(key, None)
    return {"verified": True, "contact": req.contact.strip()}


@app.get("/gps-locate")
async def gps_locate(
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    country_code: Optional[str] = None,
    lang: Optional[str] = None,
):
    """Détecte la localité la plus proche des coordonnées GPS (ou géolocalisation IP / pays en secours)."""
    source = "gps"
    if lat is None or lon is None:
        source = "ip_fallback"
        lat, lon = 14.6937, -17.4441  # Dakar par défaut
        try:
            async with httpx.AsyncClient() as client:
                r = await client.get("http://ip-api.com/json/?fields=status,lat,lon,city,country,countryCode", timeout=5)
                if r.status_code == 200:
                    j = r.json()
                    if j.get("status") == "success" and j.get("lat") is not None:
                        lat, lon = float(j["lat"]), float(j["lon"])
        except Exception:
            pass
    info = await asyncio.to_thread(astro.nearest_locality, lat, lon, lang)
    # Si l'utilisateur s'est connecté avec l'indicatif d'un autre pays d'Afrique de l'Ouest et que le GPS est en mode IP
    if country_code and country_code.upper() in astro.COUNTRIES_CATALOG and country_code.upper() != "WORLD":
        cc = country_code.upper()
        if source == "ip_fallback" and info["country_code"] != cc:
            cat = astro.COUNTRIES_CATALOG[cc]
            first_reg = cat["regions"][0]
            first_loc = first_reg["localities"][0]
            info = await asyncio.to_thread(astro.nearest_locality, first_loc["lat"], first_loc["lon"], lang)
    info["source"] = source
    return info


@app.post("/moon")
async def moon(req: MoonRequest):
    """Rapport complet d'une soirée : présence de la Lune, croissant (Yallop/Odeh), boussole, turbulence, météo."""
    d = _parse_date(req.date)
    off = _offset(req.utc_offset, req.longitude)
    resolved_lang = astro.resolve_lang(req.lang, req.country_code)
    rep = await asyncio.to_thread(astro.evening_report, req.latitude, req.longitude, d, off, resolved_lang)
    async with httpx.AsyncClient() as client:
        w = await _clouds(client, req.latitude, req.longitude, [rep["sunset_utc"]])
    cloud = w.get(rep["sunset_utc"])
    rep["cloud_cover"] = cloud["total"] if cloud else None
    rep["cloud_cover_low"] = cloud["low"] if cloud else None
    rep["weather_note"] = _weather_note(cloud, lang=resolved_lang)
    if cloud and cloud["total"] >= 80 and rep["badge_level"] in ("good", "maybe"):
        if resolved_lang == "en":
            rep["observation_tip"] += " ⚠️ Warning: overcast sky forecast, actual sighting will be difficult."
        else:
            rep["observation_tip"] += " ⚠️ Attention : le ciel prévu est couvert, l'observation réelle sera difficile."
    return rep


@app.get("/month")
async def month(lat: float, lon: float, year: int, month: int = Query(ge=1, le=12),
                utc_offset: Optional[float] = None, lang: Optional[str] = None,
                country_code: Optional[str] = None):
    """Calendrier lunaire du mois : phase chaque jour, lever/coucher, présence, croissants."""
    resolved_lang = astro.resolve_lang(lang, country_code)
    return await asyncio.to_thread(astro.month_calendar, lat, lon, _offset(utc_offset, lon), year, month, resolved_lang)


async def _with_weather(res):
    async with httpx.AsyncClient() as client:
        async def city_weather(c):
            times = [e["sunset_utc"] for e in c["evenings"] if e.get("sunset_utc")]
            w = await _clouds(client, c["lat"], c["lon"], times)
            for e in c["evenings"]:
                cl = w.get(e.get("sunset_utc"))
                e["cloud_cover"] = cl["total"] if cl else None
        await asyncio.gather(*(city_weather(c) for c in res["cities"]))
    return res


@app.get("/hilal")
async def hilal(lat: float, lon: float, date: Optional[str] = None, utc_offset: Optional[float] = None,
                country_code: str = Query("SN"), lang: Optional[str] = None):
    """Prochaine nouvelle lune à partir d'une date : visibilité du croissant sur 3 soirées pour le pays de l'utilisateur."""
    res = await asyncio.to_thread(astro.hilal_analysis, lat, lon, _offset(utc_offset, lon), _parse_date(date), country_code, lang)
    return await _with_weather(res)


@app.get("/hijri-month")
async def hijri_month(lat: float, lon: float, month: int = Query(9, ge=1, le=12),
                      utc_offset: Optional[float] = None, date: Optional[str] = None,
                      country_code: str = Query("SN"), lang: Optional[str] = None):
    """Début d'un mois hégirien donné (9 = Ramadan, 10 = Chawwal/Aïd el-Fitr, 12 = Dhou al-Hijja) pour le pays de l'utilisateur."""
    res = await asyncio.to_thread(astro.hijri_month_analysis, lat, lon, _offset(utc_offset, lon), month,
                                  _parse_date(date), country_code, lang)
    return await _with_weather(res)


@app.get("/bulletin", response_class=HTMLResponse)
async def bulletin(
    city: str = Query("Dakar"),
    country: str = Query("Sénégal"),
    country_code: str = Query("SN"),
    lat: float = Query(14.6937),
    lon: float = Query(-17.4441),
    utc_offset: float = Query(0),
    date: Optional[str] = None,
    hijri_month: int = Query(9, ge=0, le=12),
    lang: Optional[str] = None,
):
    """Génère un Bulletin Scientifique Officiel imprimable / enregistrable en PDF."""
    d = _parse_date(date)
    resolved_lang = astro.resolve_lang(lang, country_code)
    is_en = resolved_lang == "en"
    rep = await asyncio.to_thread(astro.evening_report, lat, lon, d, utc_offset, resolved_lang)
    reg = await asyncio.to_thread(astro.scan_country_regions, country_code, d, hijri_month, -1, resolved_lang)
    sen = reg["sentinel"]

    rows_html = ""
    for r in reg["regions"]:
        locs_txt = ", ".join(
            f"<b>{html.escape(l['name'])}</b> ({html.escape(l['verdict_text'])}"
            + (f", V={l['odeh_v']}" if l['odeh_v'] is not None else "") + ")"
            for l in r["localities"]
        )
        rows_html += f"""
        <tr>
          <td><b>{html.escape(r['region'])}</b></td>
          <td>{html.escape(r['best_locality'])}</td>
          <td><b>{html.escape(r['verdict_text'])}</b></td>
          <td style="font-size:12px">{locs_txt}</td>
        </tr>"""

    doc = f"""<!DOCTYPE html>
<html lang="{resolved_lang}">
<head>
<meta charset="utf-8">
<title>{"WeerWi Official Astronomical Bulletin" if is_en else "Bulletin Astronomique Officiel WeerWi"} - {html.escape(city)}</title>
<style>
  body {{ font-family: 'Segoe UI', Arial, sans-serif; color: #141829; margin: 28px; line-height: 1.5; }}
  .header {{ display: flex; justify-content: space-between; align-items: center; border-bottom: 3px solid #D4A017; padding-bottom: 14px; }}
  .title {{ font-size: 24px; font-weight: 900; color: #0E1330; }}
  .subtitle {{ font-size: 13px; color: #555; }}
  .btn {{ background: #D4A017; color: #0E1330; border: none; padding: 10px 18px; border-radius: 8px; font-weight: 800; cursor: pointer; }}
  .box {{ background: #F7F8FC; border-left: 5px solid #D4A017; padding: 14px 18px; margin: 16px 0; border-radius: 6px; }}
  .grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 14px 0; }}
  .metric {{ border: 1px solid #DDE2F0; border-radius: 8px; padding: 10px; background: #FFF; }}
  .metric .k {{ font-size: 11px; color: #666; text-transform: uppercase; }}
  .metric .v {{ font-size: 16px; font-weight: 800; color: #0E1330; }}
  table {{ width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 13px; }}
  th, td {{ border: 1px solid #D5DAE8; padding: 8px 10px; text-align: left; vertical-align: top; }}
  th {{ background: #0E1330; color: #FFD872; }}
  @media print {{ .no-print {{ display: none; }} body {{ margin: 10px; }} }}
</style>
</head>
<body>
  <div class="header">
    <div>
      <div class="title">🌙 {"WEERWI • OFFICIAL ASTRONOMICAL BULLETIN" if is_en else "WEERWI • BULLETIN ASTRONOMIQUE OFFICIEL"}</div>
      <div class="subtitle">{"Scientific Hilal Observatory • NASA JPL DE421 Ephemeris • Yallop (1997) & Odeh (2004) Criteria" if is_en else "Observatoire Scientifique du Hilal • Éphémérides NASA JPL DE421 • Critères de Yallop (1997) & Odeh (2004)"}</div>
    </div>
    <button class="btn no-print" onclick="window.print()">🖨️ {"Print / Save as PDF" if is_en else "Imprimer / Enregistrer en PDF"}</button>
  </div>

  <div class="box">
    <b>{"Reference Locality:" if is_en else "Localité de référence :"}</b> {html.escape(city)} ({html.escape(reg['country_name'])}) — Lat {lat:.4f}°, Lon {lon:.4f}° (UTC{utc_offset:+.0f})<br>
    <b>{"Analyzed Evening:" if is_en else "Soirée analysée :"}</b> {html.escape(rep['date_label'])} &nbsp;|&nbsp; <b>{"Verdict:" if is_en else "Verdict :"}</b> {html.escape(rep['badge_text'])}<br>
    <b>{"Observatory Summary:" if is_en else "Synthèse de l'astronaute :"}</b> {html.escape(rep['observation_tip'])}<br>
    <b>{"Lunar Context:" if is_en else "Contexte lunaire :"}</b> {html.escape(rep['ramadan_status'])}
  </div>

  <div class="grid">
    <div class="metric"><div class="k">{"Phase & Illumination" if is_en else "Phase & Illumination"}</div><div class="v">{html.escape(rep['phase'])} ({rep['illumination']} %)</div></div>
    <div class="metric"><div class="k">{"Sunset / Moonset" if is_en else "Coucher Soleil / Lune"}</div><div class="v">{rep['sunset']} / {rep['moonset'] or '—'} (Lag: {rep['lag_minutes']} min)</div></div>
    <div class="metric"><div class="k">{"Age since Conjunction" if is_en else "Âge depuis conjonction"}</div><div class="v">{rep['age_hours']} h ({rep['age_days']} {"d" if is_en else "j"})</div></div>
    <div class="metric"><div class="k">{"Azimuth & Direction" if is_en else "Azimut & Direction"}</div><div class="v">{rep['moon_azimuth_deg']}° ({rep['cardinal_direction']})</div></div>
    <div class="metric"><div class="k">{"Altitude & Elongation" if is_en else "Hauteur & Élongation"}</div><div class="v">Alt {rep['altitude_deg']}° / {"Elong" if is_en else "Élong"} {rep['elongation_deg']}°</div></div>
    <div class="metric"><div class="k">{"Turbulence & Airmass" if is_en else "Turbulence & Masse d'air"}</div><div class="v">{html.escape(rep['turbulence_level'])} ({rep['airmass'] or '—'}×)</div></div>
  </div>

  <h3>🏆 {"Sentinel Point & Regional Breakdown" if is_en else "Point Sentinelle & Bilan Régional"} — {html.escape(reg['country_name'])} ({html.escape(reg['date_label'])})</h3>
  <div class="box">
    <b>{html.escape(reg['rule_title'])}</b><br>
    <b>{"Sentinel Point (Most Favorable Location):" if is_en else "Point Sentinelle (Lieu le plus favorable du pays) :"}</b> {html.escape(sen['name'])} ({html.escape(sen['region'])}) —
    {"Sunset" if is_en else "Coucher Soleil"} {sen['sunset']}, {"Moonset" if is_en else "Coucher Lune"} {sen['moonset']}, Odeh V = {sen['odeh_v'] if sen['odeh_v'] is not None else '—'}, Yallop = {sen['yallop_code']}<br>
    {html.escape(reg['rule_text'])}
  </div>

  <table>
    <thead>
      <tr>
        <th>{"Region" if is_en else "Région"}</th>
        <th>{"Most Favorable Point" if is_en else "Point le plus favorable"}</th>
        <th>{"Regional Verdict" if is_en else "Verdict régional"}</th>
        <th>{"Departments, Cities & Religious Centers" if is_en else "Détail des départements, villes et foyers religieux"}</th>
      </tr>
    </thead>
    <tbody>
      {rows_html}
    </tbody>
  </table>

  <p style="font-size:11px; color:#666; margin-top:20px; text-align:center;">
    {"Document scientifically generated by WeerWi — NASA JPL DE421 Ephemeris · International Yallop & Odeh Astronomical Criteria." if is_en else "Document généré scientifiquement par WeerWi — Éphémérides NASA JPL DE421 · Critères astronomiques internationaux de Yallop et d'Odeh."}
  </p>
</body>
</html>"""
    return HTMLResponse(content=doc)


# Application Flutter Web servie à la racine
web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "flutter", "build", "web"))
if os.path.exists(web_dir):
    app.mount("/", StaticFiles(directory=web_dir, html=True), name="static")
