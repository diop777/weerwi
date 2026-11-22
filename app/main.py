import asyncio
import datetime as dt
import os
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import astro

app = FastAPI(
    title="WeerWi API",
    description="Observatoire scientifique du croissant lunaire pour l'Afrique de l'Ouest "
                "(NASA JPL DE421, critères Yallop & Odeh, météo Open-Meteo)",
    version="2.0.0",
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
    return {"app": "WeerWi", "version": app.version, "status": "online",
            "endpoints": ["/moon", "/month", "/hilal", "/hijri-month", "/cities", "/docs"]}


@app.get("/cities")
def cities():
    return astro.CITIES


@app.post("/moon")
async def moon(req: MoonRequest):
    """Rapport complet d'une soirée : présence de la Lune, croissant (Yallop/Odeh), météo."""
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


# Application Flutter Web servie à la racine
web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "flutter", "build", "web"))
if os.path.exists(web_dir):
    app.mount("/", StaticFiles(directory=web_dir, html=True), name="static")
