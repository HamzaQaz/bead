pragma Singleton

import QtQuick
import Quickshell
import qs.config

// Weather from Open-Meteo, located by IP (ip-api.com), the same sources
// Caelestia uses. Fetched on demand (refresh()), at most every 20 minutes.
Singleton {
    id: root

    property bool ready: false
    property bool failed: false     // the last try didn't get through (offline, or the service is down)
    function retry(): void { failed = false; lastFetch = 0; refresh(); }
    property string city: ""
    property string country: ""
    // Settings.units, or by country (°F in the US, Liberia, Myanmar)
    readonly property bool fahrenheit: Settings.units === "fahrenheit" || Settings.units === "auto" && ["US", "LR", "MM"].includes(country)
    onFahrenheitChanged: if (coords) { lastFetch = 0; refresh(); }
    property real temp: 0
    property real feels: 0
    property real humidity: 0
    property real wind: 0
    property int code: 0
    property bool isDay: true
    property real high: 0
    property real low: 0
    property list<var> hourly: []   // [{ time: Date, temp, code, isDay, rain (%) }]
    property list<var> daily: []    // [{ date: Date, max, min, code, rain (%) }], today first
    property var sunrise: null      // Date (today)
    property var sunset: null
    property real lastFetch: 0
    property var coords: null

    function refresh(): void {
        if (Date.now() - lastFetch < 20 * 60 * 1000) return;
        lastFetch = Date.now();
        if (coords) forecast();
        else get("http://ip-api.com/json?fields=status,city,lat,lon,countryCode", r => {
            if (r.status !== "success") { failed = true; lastFetch = 0; return; }
            // country first: with no coords yet, the units change doesn't fetch twice
            country = r.countryCode ?? "";
            coords = { lat: r.lat, lon: r.lon };
            city = r.city ?? "";
            forecast();
        });
    }

    function forecast(): void {
        const u = fahrenheit ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "";
        get(`https://api.open-meteo.com/v1/forecast?latitude=${coords.lat}&longitude=${coords.lon}`
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset"
            + "&timezone=auto&forecast_days=6" + u, r => {
            const c = r.current;
            if (!c) return;
            temp = c.temperature_2m;
            feels = c.apparent_temperature;
            humidity = c.relative_humidity_2m;
            wind = c.wind_speed_10m;
            code = c.weather_code;
            isDay = c.is_day === 1;
            high = r.daily.temperature_2m_max[0];
            low = r.daily.temperature_2m_min[0];
            const now = Date.now(), out = [];
            for (let i = 0; i < r.hourly.time.length && out.length < 12; i++) {
                const t = new Date(r.hourly.time[i]);
                if (t.getTime() < now - 3600000) continue;
                out.push({ time: t, temp: r.hourly.temperature_2m[i], code: r.hourly.weather_code[i], isDay: r.hourly.is_day[i] === 1,
                    rain: r.hourly.precipitation_probability?.[i] ?? 0 });
            }
            hourly = out;
            const d = r.daily, days = [];
            for (let i = 0; i < d.time.length; i++)
                days.push({ date: new Date(d.time[i] + "T12:00"), max: d.temperature_2m_max[i], min: d.temperature_2m_min[i],
                    code: d.weather_code?.[i] ?? 0, rain: d.precipitation_probability_max?.[i] ?? 0 });
            daily = days;
            sunrise = d.sunrise?.[0] ? new Date(d.sunrise[0]) : null;
            sunset = d.sunset?.[0] ? new Date(d.sunset[0]) : null;
            ready = true;
        });
    }

    function get(url: string, cb: var): void {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            if (x.status === 200) { root.failed = false; try { cb(JSON.parse(x.responseText)); } catch (e) { root.failed = true; } }
            else { root.failed = true; lastFetch = 0; } // retry next time
        };
        x.open("GET", url);
        x.send();
    }

    // WMO weather code -> Material Symbols icon / words
    function icon(c: int, day: bool): string {
        if (c === 0) return day ? "sunny" : "clear_night";
        if (c <= 2) return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (c === 3) return "cloud";
        if (c <= 48) return "foggy";
        if (c <= 57) return "rainy_light";
        if (c <= 67) return "rainy";
        if (c <= 77) return "weather_snowy";
        if (c <= 82) return "rainy_heavy";
        if (c <= 86) return "weather_snowy";
        return "thunderstorm";
    }
    function describe(c: int): string {
        if (c === 0) return "Clear";
        if (c <= 2) return "Partly cloudy";
        if (c === 3) return "Overcast";
        if (c <= 48) return "Fog";
        if (c <= 57) return "Drizzle";
        if (c <= 67) return "Rain";
        if (c <= 77) return "Snow";
        if (c <= 82) return "Showers";
        if (c <= 86) return "Snow showers";
        return "Thunderstorm";
    }
}
