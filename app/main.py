import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from skyfield.api import load, Topos
from datetime import date, datetime
import httpx

app = FastAPI()

# Load ephemerides once
ephem = load('de421.bsp')
earth, moon, sun = ephem['earth'], ephem['moon'], ephem['sun']
ts = load.timescale()

class MoonRequest(BaseModel):
    latitude: float
    longitude: float
    date: date | None = None  # default today

class MoonResponse(BaseModel):
    phase: str
    illumination: float
    age_days: float
    elongation_deg: float
    altitude_deg: float
    visible: bool
    visibility_score: float
    cloud_cover: float | None = None

def compute_phase(lat, lon, target_date: date):
    t = ts.utc(target_date.year, target_date.month, target_date.day)
    loc = earth + Topos(latitude_degrees=lat, longitude_degrees=lon)
    # altitude of moon
    alt = loc.at(t).observe(moon).apparent().altaz()[0].degrees
    # phase calculations
    e = earth.at(t)
    moon_vec = e.observe(moon).apparent()
    sun_vec = e.observe(sun).apparent()
    elong = moon_vec.separation_from(sun_vec).degrees
    age = (elong / 360.0) * 29.53
    illumination = (1 + math.cos(math.radians(elong))) / 2 * 100
    # simple visibility heuristic (Yallop simplified)
    visible = (age > 0.5) and (elong > 7) and (alt > 5)
    score = min(1.0, (age * 2) / 24)  # placeholder
    # phase name
    if age < 1:
        phase = "Nouvelle lune"
    elif age < 7:
        phase = "Croissant croissant"
    elif age < 14:
        phase = "Premier quartier"
    elif age < 21:
        phase = "Gibbeuse croissante"
    elif age < 28:
        phase = "Pleine lune"
    else:
        phase = "Dernier croissant"
    return phase, illumination, age, elong, alt, visible, score

async def fetch_weather(lat: float, lon: float, target_date: date):
    # Open-Meteo: retrieve cloudcover for the day (hourly)
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": lat,
        "longitude": lon,
        "hourly": "cloudcover",
        "start_date": target_date.isoformat(),
        "end_date": target_date.isoformat(),
        "timezone": "UTC",
    }
    async with httpx.AsyncClient() as client:
        resp = await client.get(url, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        # take average cloud cover for the day
        clouds = data.get("hourly", {}).get("cloudcover", [])
        if clouds:
            return sum(clouds) / len(clouds)
    return None

@app.post("/moon", response_model=MoonResponse)
async def get_moon(info: MoonRequest):
    target = info.date or date.today()
    phase, illum, age, elong, alt, visible, score = compute_phase(info.latitude, info.longitude, target)
    cloud = await fetch_weather(info.latitude, info.longitude, target)
    return MoonResponse(
        phase=phase,
        illumination=round(illum, 2),
        age_days=round(age, 2),
        elongation_deg=round(elong, 2),
        altitude_deg=round(alt, 2),
        visible=visible,
        visibility_score=round(score, 2),
        cloud_cover=round(cloud, 2) if cloud is not None else None,
    )
