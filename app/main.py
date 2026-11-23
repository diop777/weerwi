import asyncio
import datetime as dt
import html
import os
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import astro

app = FastAPI(
    title="WeerWi API",
    description="Observatoire scientifique du croissant lunaire pour le Sénégal, l'Afrique de l'Ouest et le Monde "
                "(NASA JPL DE421, critères Yallop & Odeh, météo Open-Meteo)",
    version="2.5.0",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

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


def _weather_note(cloud):
    if cloud is None:
        return "Prévision météo indisponible pour cette date (au-delà de 15 jours ou dans le passé)."
    c = cloud["total"]
    if c < 20:
        return f"Ciel dégagé au coucher du Soleil ({c:.0f} % de nuages)."
    if c < 50:
        return f"Quelques nuages au coucher du Soleil ({c:.0f} %) : horizon ouest probablement exploitable."
    if c < 80:
        return f"Ciel nuageux au coucher du Soleil ({c:.0f} %) : l'observation risque d'être gênée."
    return f"Ciel couvert au coucher du Soleil ({c:.0f} %) : observation très compromise."

# ─────────────────────────── Modèles ───────────────────────────

class MoonRequest(BaseModel):
    latitude: float
    longitude: float
    date: Optional[str] = None
    utc_offset: Optional[float] = None


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
):
    """Scan complet de toutes les régions/villes d'un pays + Point Sentinelle le plus favorable."""
    d = _parse_date(date)
    return await asyncio.to_thread(astro.scan_country_regions, country, d, hijri_month, day_offset)


@app.get("/gps-locate")
async def gps_locate(lat: Optional[float] = None, lon: Optional[float] = None):
    """Détecte la localité la plus proche des coordonnées GPS (ou géolocalisation IP en secours)."""
    source = "gps"
    if lat is None or lon is None:
        source = "ip_fallback"
        lat, lon = 14.6937, -17.4441  # Dakar par défaut
        try:
            async with httpx.AsyncClient() as client:
                r = await client.get("http://ip-api.com/json/?fields=status,lat,lon,city,country", timeout=5)
                if r.status_code == 200:
                    j = r.json()
                    if j.get("status") == "success" and j.get("lat") is not None:
                        lat, lon = float(j["lat"]), float(j["lon"])
        except Exception:
            pass
    info = await asyncio.to_thread(astro.nearest_locality, lat, lon)
    info["source"] = source
    return info


@app.post("/moon")
async def moon(req: MoonRequest):
    """Rapport complet d'une soirée : présence de la Lune, croissant (Yallop/Odeh), boussole, turbulence, météo."""
    d = _parse_date(req.date)
    off = _offset(req.utc_offset, req.longitude)
    rep = await asyncio.to_thread(astro.evening_report, req.latitude, req.longitude, d, off)
    async with httpx.AsyncClient() as client:
        w = await _clouds(client, req.latitude, req.longitude, [rep["sunset_utc"]])
    cloud = w.get(rep["sunset_utc"])
    rep["cloud_cover"] = cloud["total"] if cloud else None
    rep["cloud_cover_low"] = cloud["low"] if cloud else None
    rep["weather_note"] = _weather_note(cloud)
    if cloud and cloud["total"] >= 80 and rep["badge_level"] in ("good", "maybe"):
        rep["observation_tip"] += " ⚠️ Attention : le ciel prévu est couvert, l'observation réelle sera difficile."
    return rep


@app.get("/month")
async def month(lat: float, lon: float, year: int, month: int = Query(ge=1, le=12),
                utc_offset: Optional[float] = None):
    """Calendrier lunaire du mois : phase chaque jour, lever/coucher, présence, croissants."""
    return await asyncio.to_thread(astro.month_calendar, lat, lon, _offset(utc_offset, lon), year, month)


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
async def hilal(lat: float, lon: float, date: Optional[str] = None, utc_offset: Optional[float] = None):
    """Prochaine nouvelle lune à partir d'une date : visibilité du croissant sur 3 soirées, toutes villes."""
    res = await asyncio.to_thread(astro.hilal_analysis, lat, lon, _offset(utc_offset, lon), _parse_date(date))
    return await _with_weather(res)


@app.get("/hijri-month")
async def hijri_month(lat: float, lon: float, month: int = Query(9, ge=1, le=12),
                      utc_offset: Optional[float] = None, date: Optional[str] = None):
    """Début d'un mois hégirien donné (9 = Ramadan, 10 = Chawwal/Aïd el-Fitr, 12 = Dhou al-Hijja)."""
    res = await asyncio.to_thread(astro.hijri_month_analysis, lat, lon, _offset(utc_offset, lon), month,
                                  _parse_date(date))
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
):
    """Génère un Bulletin Scientifique Officiel imprimable / enregistrable en PDF."""
    d = _parse_date(date)
    rep = await asyncio.to_thread(astro.evening_report, lat, lon, d, utc_offset)
    reg = await asyncio.to_thread(astro.scan_country_regions, country_code, d, hijri_month, -1)
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
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Bulletin Astronomique Officiel WeerWi - {html.escape(city)}</title>
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
      <div class="title">🌙 WEERWI • BULLETIN ASTRONOMIQUE OFFICIEL</div>
      <div class="subtitle">Observatoire Scientifique du Hilal • Éphémérides NASA JPL DE421 • Critères de Yallop (1997) & Odeh (2004)</div>
    </div>
    <button class="btn no-print" onclick="window.print()">🖨️ Imprimer / Enregistrer en PDF</button>
  </div>

  <div class="box">
    <b>Localité de référence :</b> {html.escape(city)} ({html.escape(country)}) — Lat {lat:.4f}°, Lon {lon:.4f}° (UTC{utc_offset:+.0f})<br>
    <b>Soirée analysée :</b> {html.escape(rep['date_label'])} &nbsp;|&nbsp; <b>Verdict :</b> {html.escape(rep['badge_text'])}<br>
    <b>Synthèse de l'astronaute :</b> {html.escape(rep['observation_tip'])}<br>
    <b>Contexte lunaire :</b> {html.escape(rep['ramadan_status'])}
  </div>

  <div class="grid">
    <div class="metric"><div class="k">Phase & Illumination</div><div class="v">{html.escape(rep['phase'])} ({rep['illumination']} %)</div></div>
    <div class="metric"><div class="k">Coucher Soleil / Lune</div><div class="v">{rep['sunset']} / {rep['moonset'] or '—'} (Lag: {rep['lag_minutes']} min)</div></div>
    <div class="metric"><div class="k">Âge depuis conjonction</div><div class="v">{rep['age_hours']} h ({rep['age_days']} j)</div></div>
    <div class="metric"><div class="k">Azimut & Direction</div><div class="v">{rep['moon_azimuth_deg']}° ({rep['cardinal_direction']})</div></div>
    <div class="metric"><div class="k">Hauteur & Élongation</div><div class="v">Alt {rep['altitude_deg']}° / Élong {rep['elongation_deg']}°</div></div>
    <div class="metric"><div class="k">Turbulence & Masse d'air</div><div class="v">{html.escape(rep['turbulence_level'])} ({rep['airmass'] or '—'}×)</div></div>
  </div>

  <h3>🏆 Point Sentinelle & Bilan Régional — {html.escape(reg['country_name'])} ({html.escape(reg['date_label'])})</h3>
  <div class="box">
    <b>{html.escape(reg['rule_title'])}</b><br>
    <b>Point Sentinelle (Lieu le plus favorable du pays) :</b> {html.escape(sen['name'])} (Région de {html.escape(sen['region'])}) —
    Coucher Soleil {sen['sunset']}, Coucher Lune {sen['moonset']}, Indice Odeh V = {sen['odeh_v'] if sen['odeh_v'] is not None else '—'}, Yallop = {sen['yallop_code']}<br>
    {html.escape(reg['rule_text'])}
  </div>

  <table>
    <thead>
      <tr>
        <th>Région</th>
        <th>Point le plus favorable</th>
        <th>Verdict régional</th>
        <th>Détail des départements, villes et foyers religieux</th>
      </tr>
    </thead>
    <tbody>
      {rows_html}
    </tbody>
  </table>

  <p style="font-size:11px; color:#666; margin-top:20px; text-align:center;">
    Document généré scientifiquement par WeerWi — Éphémérides NASA JPL DE421 · Critères astronomiques internationaux de Yallop et d'Odeh.
  </p>
</body>
</html>"""
    return HTMLResponse(content=doc)


# Application Flutter Web servie à la racine
web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "flutter", "build", "web"))
if os.path.exists(web_dir):
    app.mount("/", StaticFiles(directory=web_dir, html=True), name="static")
