import os
import math
import ssl
import datetime
from typing import Optional

import certifi
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import skyfield.iokit
from skyfield.api import load, Topos

# Assure SSL verification works on Windows
skyfield.iokit.create_default_context = lambda *a, **k: ssl.create_default_context(cafile=certifi.where())

app = FastAPI(
    title="WeerWi API & App",
    description="API astronomique et météo pour le suivi lunaire en Afrique de l'Ouest",
    version="1.1.0"
)

# Enable CORS for Flutter Web / Mobile apps
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ephemerides (lazy loaded on startup)
ephem = None
earth = None
moon = None
sun = None
ts = None

@app.on_event("startup")
def load_ephemeris():
    global ephem, earth, moon, sun, ts
    ts = load.timescale()
    ephemeris_path = os.path.join(os.path.dirname(__file__), 'de421.bsp')
    if os.path.exists(ephemeris_path):
        ephem = load(ephemeris_path)
    else:
        ephem = load('de421.bsp')
    earth, moon, sun = ephem['earth'], ephem['moon'], ephem['sun']

class MoonRequest(BaseModel):
    latitude: float
    longitude: float
    date: Optional[str] = None  # Accepts "YYYY-MM-DD" or None for today

class MoonResponse(BaseModel):
    date: str
    phase: str
    illumination: float
    age_days: float
    elongation_deg: float
    altitude_deg: float
    visible: bool
    visibility_score: float
    cloud_cover: Optional[float] = None
    observation_tip: Optional[str] = None
    ramadan_status: Optional[str] = None

def compute_phase(lat: float, lon: float, target_date: datetime.date):
    t = ts.utc(target_date.year, target_date.month, target_date.day)
    loc = earth + Topos(latitude_degrees=lat, longitude_degrees=lon)
    
    # Altitude and azimuth of moon
    alt = loc.at(t).observe(moon).apparent().altaz()[0].degrees
    
    # Apparent positions
    e = earth.at(t)
    moon_vec = e.observe(moon).apparent()
    sun_vec = e.observe(sun).apparent()
    elong = moon_vec.separation_from(sun_vec).degrees
    
    # Synodic month approximation (29.53 days)
    age = (elong / 360.0) * 29.53
    illumination = ((1 - math.cos(math.radians(elong))) / 2) * 100
    
    # Visibility criteria (Yallop / Danjon heuristic)
    # Crescent visible if elongation > 7.5°, altitude above horizon > 0°, age > 0.6 day
    visible = (age > 0.6) and (elong > 7.5) and (alt > 0)
    score = min(1.0, max(0.0, (elong - 7.0) / 15.0 * (alt / 10.0 if alt > 0 else 0)))
    
    if age < 1:
        phase = "Nouvelle lune (Conjonction)"
    elif age < 7.4:
        phase = "Premier croissant (Hilal)"
    elif age < 14.8:
        phase = "Premier quartier"
    elif age < 22.1:
        phase = "Lune gibbeuse croissante"
    elif age < 23.5:
        phase = "Pleine lune"
    elif age < 28.0:
        phase = "Lune gibbeuse décroissante"
    else:
        phase = "Dernier croissant"
        
    return phase, illumination, age, elong, alt, visible, score

async def fetch_weather(lat: float, lon: float, target_date: datetime.date):
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": lat,
        "longitude": lon,
        "hourly": "cloudcover",
        "start_date": target_date.isoformat(),
        "end_date": target_date.isoformat(),
        "timezone": "UTC",
    }
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, params=params, timeout=8)
            if resp.status_code == 200:
                data = resp.json()
                clouds = data.get("hourly", {}).get("cloudcover", [])
                if clouds:
                    # evening cloud cover (around sunset ~18h-20h UTC) is most critical
                    evening_slice = clouds[17:21] if len(clouds) >= 21 else clouds
                    return sum(evening_slice) / len(evening_slice)
    except Exception:
        pass
    return None

@app.get("/api/info")
def api_info():
    return {
        "app": "WeerWi - Suivi Lunaire & Astronomie",
        "status": "online",
        "endpoints": {
            "docs": "/docs",
            "moon_post": "/moon"
        },
        "description": "Calculs astronomiques exacts de la lune et prévisions météo pour l'Afrique de l'Ouest"
    }

@app.post("/moon", response_model=MoonResponse)
async def get_moon(info: MoonRequest):
    if info.date and info.date.strip():
        try:
            target = datetime.date.fromisoformat(info.date.strip())
        except ValueError:
            raise HTTPException(status_code=400, detail="Format de date invalide. Utilisez YYYY-MM-DD.")
    else:
        target = datetime.date.today()

    phase, illum, age, elong, alt, visible, score = compute_phase(info.latitude, info.longitude, target)
    cloud = await fetch_weather(info.latitude, info.longitude, target)
    
    # Observation diagnostic
    if visible:
        if cloud is not None and cloud > 75:
            tip = f"Le croissant est au-dessus de l'horizon, mais le ciel est très nuageux ({int(cloud)}%). Privilégiez un endroit dégagé ou des instruments optiques."
        elif cloud is not None and cloud > 35:
            tip = f"Croissant théoriquement visible ! Nuages partiels ({int(cloud)}%). Surveillez l'horizon ouest juste après le coucher du soleil."
        else:
            tip = "Excellentes conditions ! Ciel dégagé et croissant favorable pour une observation nette à l'œil nu à l'ouest."
    else:
        if alt <= 0:
            tip = "La lune se couche avant ou avec le soleil. Impossible à observer ce soir-là (sous l'horizon)."
        elif elong <= 7.5:
            tip = "La lune est trop proche du disque solaire (élongation < 7.5°). Le croissant est noyé dans l'éclat du crépuscule (Limite de Danjon)."
        else:
            tip = "Croissant non visible à l'œil nu selon les critères astronomiques rigoureux."

    # Statut Ramadan / Hilal
    if "croissant" in phase.lower() or visible:
        ramadan_status = "Nouveau mois lunaire visible (1er jour du mois dès le lendemain si observé au coucher)."
    elif "nouvelle lune" in phase.lower() or age < 1.0:
        ramadan_status = "Jour de conjonction astronomique (29e jour du mois : observation du croissant ce soir)."
    else:
        ramadan_status = f"Phase intermédiaire ({phase})."

    return MoonResponse(
        date=target.isoformat(),
        phase=phase,
        illumination=round(illum, 2),
        age_days=round(age, 2),
        elongation_deg=round(elong, 2),
        altitude_deg=round(alt, 2),
        visible=visible,
        visibility_score=round(score, 2),
        cloud_cover=round(cloud, 2) if cloud is not None else None,
        observation_tip=tip,
        ramadan_status=ramadan_status,
    )

# Mount Flutter Web app at root /
web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "flutter", "build", "web"))
if os.path.exists(web_dir):
    app.mount("/", StaticFiles(directory=web_dir, html=True), name="static")
