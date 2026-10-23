#!/usr/bin/env python3
"""Synthetic GPS fixture tracks for the track pipeline's tests (design §11.2, ADR 0003).

Stdlib only, seeded, deterministic: the same command writes the same bytes. The tracks are synthetic paths at
public places, so they contain no one's real location.

    python3 scripts/make-tracks.py            # writes RyftTests/Fixtures/Tracks/*.json and *.gpx
    python3 scripts/make-tracks.py --check    # fails when a committed file differs from what the script writes

Tracks:
- road-5k: 5.000 km at 3.0 m/s, gentle curves, a 20 s traffic light, a 25 s tunnel gap, 2 outliers; open sky.
- trail-switchbacks: 8.0 km, 12 hairpins of radius 15 m, +400/-400 m, canopy, 30 bad fixes, 3 multipath jumps
  (2 fixes each), a 45 s gap; with barometer samples.
- stationary: 10 min on a table, accuracy 5-30 m.

Ground truth. The path is integrated from its curvature in 5 cm steps on the WGS84 ellipsoid (meridional and
prime-vertical radii at the current latitude), so its length is the integrated arc length. The JSON carries the
length, ascent and descent, the times the path crosses each kilometre, the stops, and stretches of constant speed.

Fixes, 1 Hz. An error level moves smoothly inside the regime's accuracy range (open 4-8 m, urban 8-20 m, canopy
10-30 m), and each fix reports that level with +-20 % scatter (log-normal), clipped to the range: Core Location's
accuracy jitters from fix to fix around how good the signal is. Error per axis (east, north, up), with
sigma = level / 2 (design §11.2):

    error = slow(t) + multipath(t) + jitter,  with variances w * sigma(t)^2 and (1 - w) * sigma(t)^2

- slow: first-order Gauss-Markov, tau 600 s (atmosphere and orbits);
- multipath: second-order Gauss-Markov with tau = 90 m / speed, clamped to 30-300 s. The receiver's own filter
  smooths its output over about 30 s; below 3 m/s the surroundings change too slowly to decorrelate the error, and a
  phone lying still keeps its error for minutes. The slow share w is 0.7 / 0.4 / 0.3 for open / urban / canopy;
- jitter: white receiver noise, 0.3 / 0.5 / 0.7 m.
Real receivers smooth their output (Doppler-aided), so position errors wander rather than jump from fix to fix;
white noise of sigma = accuracy / 2 at 1 Hz would make every second's step mostly noise, which no phone reports.
A process's sigma enters through its innovations, so the error drifts toward a new level instead of jumping with it.
The level moves with twice the multipath time constant. Vertical: the level times a smooth factor in 0.5-1.0 (Core
Location's altitude is barometer-aided), with the same scatter.

Faults: outliers report 40-80 m and are off by that much; a multipath jump is 60 m off with a falsely good 10 m
accuracy; a gap has no fixes at all. Their indices are in `faults`.

The trail's barometer reports the true
altitude change since the start plus 0.12 m of white noise and a drift of 1 m per hour.
"""

import argparse
import json
import math
import os
import random
import sys

A = 6378137.0
F = 1 / 298.257223563
E2 = F * (2 - F)
EPOCH = 1781420400.0  # 2026-06-14T07:00:00Z

REGIMES = {
    #           acc range    slow share  jitter (m)
    "open": ((4.0, 8.0), 0.7, 0.3),
    "urban": ((8.0, 20.0), 0.4, 0.5),
    "canopy": ((10.0, 30.0), 0.3, 0.7),
}
# Multipath correlation: the receiver smooths over about 30 s; slower than 90 m / speed, the surroundings change
# too little to decorrelate it (a phone lying still: 300 s).
RECEIVER_SMOOTHING_S = 30.0
DECORRELATION_M = 90.0
STILL_S = 300.0


def radii(lat_deg):
    s = math.sin(math.radians(lat_deg))
    w = 1 - E2 * s * s
    return A * (1 - E2) / (w * math.sqrt(w)), A / math.sqrt(w)


def offset(lat, lon, east, north):
    m, n = radii(lat)
    return lat + math.degrees(north / m), lon + math.degrees(east / (n * math.cos(math.radians(lat))))


class GaussMarkov:
    """Gauss-Markov process, first or second order, with a time constant and a target sigma that may vary. The
    sigma enters through the innovations, so the error drifts toward a new level instead of jumping with it."""

    def __init__(self, rng, order):
        self.rng = rng
        self.order = order
        self.x = rng.gauss(0, 1)
        self.y = self.x

    def step(self, dt, tau, sigma=1.0):
        rho = math.exp(-dt / tau)
        self.x = rho * self.x + math.sqrt(1 - rho * rho) * sigma * self.rng.gauss(0, 1)
        if self.order == 1:
            return self.x
        # A second stage over the first, scaled so the output keeps the first stage's variance.
        c = (1 - rho * rho) / math.sqrt(1 + rho * rho)
        self.y = rho * self.y + c * self.x
        return self.y


class Path:
    """Arc-length parametrised path: pieces of (length m, turn degrees); positive turns are clockwise."""

    def __init__(self, pieces):
        self.pieces = pieces
        self.length = sum(p[0] for p in pieces)

    def curvature(self, s):
        start = 0.0
        for length, turn in self.pieces:
            if s < start + length:
                return math.radians(turn) / length if turn else 0.0
            start += length
        return 0.0


def simulate(path, speed_at, stops, lat0, lon0, heading0, alt_at, rest_end=0.0, accel=1.0):
    """Integrates the path in time. `speed_at(s)` is the cruise speed; `stops` are (s, seconds) standing still.
    Returns per-second truth samples (t, lat, lon, alt, s, speed) and the exact kilometre crossing times."""
    dt = 0.01
    t, s, v, heading = 0.0, 0.0, 0.0, math.radians(heading0)
    lat, lon = lat0, lon0
    samples, crossings, stop_windows = [], [], []
    next_km = 1000.0
    pending_stops = sorted(stops)
    standing_until = None
    next_sample = 0.0
    done_at = None
    while True:
        if t + 1e-9 >= next_sample:
            samples.append((round(next_sample, 6), lat, lon, alt_at(s), s, v))
            next_sample += 1.0
            if done_at is not None and t >= done_at + rest_end:
                break
        # Speed control: brake for the next stop or the end, else accelerate to cruise.
        if standing_until is not None:
            if t >= standing_until:
                standing_until = None
            else:
                v = 0.0
        if standing_until is None and done_at is None:
            target = speed_at(s)
            stop_s = pending_stops[0][0] if pending_stops else path.length
            to_go = stop_s - s
            if to_go <= v * v / (2 * accel) + 1e-6:
                v = max(0.0, v - accel * dt)
                if to_go <= 1e-3 or v == 0.0:
                    v = 0.0
                    if pending_stops:
                        _, seconds = pending_stops.pop(0)
                        standing_until = t + seconds
                        stop_windows.append((t, t + seconds))
                    else:
                        done_at = t
                        while next_km <= path.length + 1e-6:
                            crossings.append(t)
                            next_km += 1000.0
            elif v < target:
                v = min(target, v + accel * dt)
            else:
                v = max(target, v - accel * dt)
        ds = v * dt
        if ds > 0:
            if pending_stops:
                ds = min(ds, pending_stops[0][0] - s)
            ds = min(ds, path.length - s)
            k = path.curvature(s + ds / 2)
            heading += k * ds / 2
            m, n = radii(lat)
            lat += math.degrees(ds * math.cos(heading) / m)
            lon += math.degrees(ds * math.sin(heading) / (n * math.cos(math.radians(lat))))
            heading += k * ds / 2
            before = s
            s += ds
            while s >= next_km - 1e-9 and next_km <= path.length + 1e-9:
                crossings.append(t + dt * (next_km - before) / ds)
                next_km += 1000.0
        t += dt
    return samples, crossings, stop_windows


def ascent_descent(values):
    up = sum(max(0.0, b - a) for a, b in zip(values, values[1:]))
    down = sum(max(0.0, a - b) for a, b in zip(values, values[1:]))
    return up, down


def make_fixes(rng, truth, regime_at, gaps, outliers, multipath):
    """Noisy fixes for each truth sample, with the faults applied. Returns (fixes, fault indices)."""
    slow = [GaussMarkov(rng, 1) for _ in range(3)]
    fast = [GaussMarkov(rng, 2) for _ in range(3)]
    acc_process = GaussMarkov(rng, 2)
    vfactor = GaussMarkov(rng, 2)
    fixes = []
    faults = {"outliers": [], "multipath": []}
    jump = None
    for t, lat, lon, alt, s, v in truth:
        (lo, hi), w, jitter = REGIMES[regime_at(s)]
        tau = min(STILL_S, max(RECEIVER_SMOOTHING_S, DECORRELATION_M / max(v, 1e-3)))
        level = lo + (hi - lo) / (1 + math.exp(-1.5 * acc_process.step(1.0, 2 * tau)))
        vlevel = level * (0.5 + 0.5 / (1 + math.exp(-1.5 * vfactor.step(1.0, 2 * tau))))
        sigmas = (level / 2, level / 2, vlevel / 2)
        acc = min(hi, max(lo, level * math.exp(rng.gauss(0, 0.2))))
        vacc = max(1.0, vlevel * math.exp(rng.gauss(0, 0.2)))
        err = [slow[i].step(1.0, 600.0, math.sqrt(w) * sigmas[i]) + fast[i].step(1.0, tau, math.sqrt(1 - w) * sigmas[i])
               for i in range(3)]
        if any(g0 <= t < g1 for g0, g1 in gaps):
            continue
        east = err[0] + rng.gauss(0, jitter)
        north = err[1] + rng.gauss(0, jitter)
        up = err[2] + rng.gauss(0, jitter)
        index = len(fixes)
        if any(abs(t - o) < 0.5 for o in outliers):
            acc = rng.uniform(40, 80)
            vacc = acc * 1.5
            bearing = rng.uniform(0, 2 * math.pi)
            east, north = acc * math.sin(bearing), acc * math.cos(bearing)
            faults["outliers"].append(index)
        elif any(m <= t < m + 2 for m in multipath):
            if jump is None:
                bearing = rng.uniform(0, 2 * math.pi)
                jump = (60 * math.sin(bearing), 60 * math.cos(bearing))
            east, north = east + jump[0], north + jump[1]
            acc = 10.0
            faults["multipath"].append(index)
        else:
            jump = None
        flat, flon = offset(lat, lon, east, north)
        fixes.append([round(t, 3), round(flat, 8), round(flon, 8), round(alt + up, 2), round(acc, 2),
                      round(vacc, 2), 0])
    return fixes, faults


def kilometre_crossings(crossings):
    return [round(EPOCH + c, 3) for c in crossings]


def road_5k():
    rng = random.Random(5000)
    pieces = [(350, 0), (200 * math.pi / 3, -60), (520, 0), (300 * math.pi / 2, 90), (900, 0),
              (250 * math.radians(75), -75), (500, 0), (400 * math.pi / 6, -30), (420, 0),
              (220 * math.radians(80), 80)]
    pieces.append((5000 - sum(p[0] for p in pieces), 0))
    path = Path(pieces)

    def alt_at(s):
        return 38 + 5 * math.sin(2 * math.pi * s / 1700) + 2 * math.sin(2 * math.pi * s / 600)

    truth, crossings, stops = simulate(path, lambda s: 3.0, [(2300.0, 20.0)], 52.4731, 13.4015, 20.0, alt_at,
                                       rest_end=5.0)
    tunnel_start = next(t for t, *_rest in truth if _rest[3] >= 3520)
    gaps = [(tunnel_start, tunnel_start + 25)]
    outliers = [next(t for t, *_rest in truth if _rest[3] >= s) for s in (1200, 4100)]
    fixes, faults = make_fixes(rng, truth, lambda s: "open", gaps, outliers, [])
    up, down = ascent_descent([alt_at(x[4]) for x in truth])
    constant = [next(t for t, *_rest in truth if _rest[3] >= 650), next(t for t, *_rest in truth if _rest[3] >= 2280)]
    return {
        "name": "road-5k",
        "profile": "run",
        "seed": 5000,
        "fixes": fixes,
        "faults": {**faults, "gaps": [[round(EPOCH + g0, 3), 25.0] for g0, _ in gaps]},
        "truth": {
            "distance_m": path.length,
            "ascent_m": round(up, 2),
            "descent_m": round(down, 2),
            "split_times": kilometre_crossings(crossings),
            "stops": [[round(EPOCH + a, 3), round(EPOCH + b, 3)] for a, b in stops],
            "constant_speed": [[round(EPOCH + constant[0], 3), round(EPOCH + constant[1], 3), 3.0]],
        },
    }


def trail_switchbacks():
    rng = random.Random(8000)
    hairpin = 15 * math.pi
    ridge = 120.0
    leg = (8000 - 12 * hairpin - ridge) / 14
    pieces = []
    for i in range(7):
        pieces.append((leg, 0))
        if i < 6:
            pieces.append((hairpin, 180 if i % 2 == 0 else -180))
    pieces.append((ridge / 2, 0))
    pieces.append((ridge / 2, 45))
    for i in range(7):
        pieces.append((leg, 0))
        if i < 6:
            pieces.append((hairpin, -180 if i % 2 == 0 else 180))
    path = Path(pieces)
    summit = 4000.0

    def alt_at(s):
        return 900 + 400 * s / summit if s <= summit else 1300 - 400 * (s - summit) / (path.length - summit)

    truth, crossings, stops = simulate(path, lambda s: 2.2 if s < summit else 3.0, [], 47.8705, 8.0010, 35.0,
                                       alt_at, rest_end=5.0, accel=0.5)
    # A 45 s gap in the middle of the down section's third leg (a straight).
    third_leg_mid = 4000 + 60 + 2 * (leg + hairpin) + leg / 2
    gap_start = next(t for t, *_rest in truth if _rest[3] >= third_leg_mid - 60)
    gaps = [(gap_start, gap_start + 45)]
    duration = truth[-1][0]
    picks = [duration * (i + 0.5) / 30 for i in range(30)]
    outliers = [round(p + rng.uniform(-10, 10)) for p in picks]
    outliers = [o for o in outliers if not any(g0 - 2 <= o < g1 + 2 for g0, g1 in gaps)]
    multipath = [round(duration * f) + 0.0 for f in (0.21, 0.52, 0.83)]
    fixes, faults = make_fixes(rng, truth, lambda s: "canopy", gaps, outliers, multipath)
    up, down = ascent_descent([alt_at(x[4]) for x in truth])
    baro = []
    drift_per_s = 1.0 / 3600
    for t, _lat, _lon, alt, _s, _v in truth:
        baro.append([round(t + 0.5, 3), round(alt - 900 + drift_per_s * t + rng.gauss(0, 0.12), 3)])
    constant = [next(t for t, *_rest in truth if _rest[3] >= 4400), next(t for t, *_rest in truth if _rest[3] >= 4800)]
    return {
        "name": "trail-switchbacks",
        "profile": "trail",
        "seed": 8000,
        "fixes": fixes,
        "altimeter": baro,
        "faults": {**faults, "gaps": [[round(EPOCH + g0, 3), 45.0] for g0, _ in gaps]},
        "truth": {
            "distance_m": path.length,
            "ascent_m": round(up, 2),
            "descent_m": round(down, 2),
            "split_times": kilometre_crossings(crossings),
            "stops": [],
            "constant_speed": [[round(EPOCH + constant[0], 3), round(EPOCH + constant[1], 3), 3.0]],
        },
    }


def stationary():
    rng = random.Random(600)
    truth = [(float(t), 52.4750, 13.4050, 41.0, 0.0, 0.0) for t in range(600)]
    fixes, faults = make_fixes(rng, truth, lambda s: "table", [], [], [])
    return {
        "name": "stationary",
        "profile": "run",
        "seed": 600,
        "fixes": fixes,
        "faults": {**faults, "gaps": []},
        "truth": {"distance_m": 0.0, "ascent_m": 0.0, "descent_m": 0.0, "split_times": [], "stops": [],
                  "constant_speed": []},
    }


REGIMES["table"] = ((5.0, 30.0), 0.4, 0.5)


def finish(track):
    fixes = track["fixes"]
    track["start"] = EPOCH
    track["expected"] = {
        "fixes": len(fixes),
        "accuracy_rejections": sum(1 for f in fixes if f[4] > 25),
    }
    track["format"] = "fixes: [t (s since start), latitude, longitude, altitude, h_acc, v_acc, stationary]; " \
                      "altimeter: [t, relative altitude]; times in truth are seconds since 1970"
    ordered = {k: track[k] for k in ("name", "format", "profile", "seed", "start", "truth", "expected", "faults")}
    ordered["fixes"] = fixes
    if "altimeter" in track:
        ordered["altimeter"] = track["altimeter"]
    return ordered


def to_json(track):
    head = {k: v for k, v in track.items() if k not in ("fixes", "altimeter")}
    lines = ["{"]
    for key, value in head.items():
        lines.append(f'  "{key}": {json.dumps(value, separators=(",", ":"))},')
    for key in ("fixes", "altimeter"):
        if key in track:
            rows = ",\n    ".join(json.dumps(r, separators=(",", ":")) for r in track[key])
            lines.append(f'  "{key}": [\n    {rows}\n  ],')
    lines[-1] = lines[-1].rstrip(",")
    lines.append("}")
    return "\n".join(lines) + "\n"


def to_gpx(track):
    import datetime

    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<gpx version="1.1" creator="RYFT scripts/make-tracks.py" xmlns="http://www.topografix.com/GPX/1/1">',
           f"  <!-- Synthetic {track['name']} (seed {track['seed']}): fixes as recorded, faults included. -->"]
    for t, lat, lon, alt, _acc, _vacc, _st in track["fixes"]:
        stamp = datetime.datetime.fromtimestamp(EPOCH + t, datetime.timezone.utc)
        iso = stamp.strftime("%Y-%m-%dT%H:%M:%S") + f".{int(round((t % 1) * 1000)):03d}Z"
        out.append(f'  <wpt lat="{lat:.8f}" lon="{lon:.8f}"><ele>{alt:.2f}</ele><time>{iso}</time></wpt>')
    out.append("</gpx>")
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser.add_argument("--out", default=os.path.join(root, "RyftTests", "Fixtures", "Tracks"))
    parser.add_argument("--check", action="store_true", help="compare with the files on disk instead of writing")
    args = parser.parse_args()
    files = {}
    for make in (road_5k, trail_switchbacks, stationary):
        track = finish(make())
        files[f"{track['name']}.json"] = to_json(track)
        files[f"{track['name']}.gpx"] = to_gpx(track)
    stale = []
    for name, text in files.items():
        path = os.path.join(args.out, name)
        if args.check:
            try:
                with open(path, encoding="utf-8") as f:
                    if f.read() != text:
                        stale.append(name)
            except FileNotFoundError:
                stale.append(name)
        else:
            os.makedirs(args.out, exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
    if stale:
        print("make-tracks: out of date: " + ", ".join(stale) + " (run python3 scripts/make-tracks.py)")
        return 1
    if not args.check:
        print("make-tracks: wrote " + ", ".join(sorted(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
