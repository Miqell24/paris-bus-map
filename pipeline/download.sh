#!/usr/bin/env bash
# Downloads input data: IDFM GTFS feed, OSM networks (Geofabrik extracts, Overpass as fallback), MapLibre GL.
# Everything is cached — re-running only fetches what is missing.
#
# ONE feed covers the whole Île-de-France (~2000 lines, all operators after
# the market opening — RATP alone runs only 76 bus routes now), so the map's
# scope is computed by pipeline/scope.mjs into data/scope.json: buses of the
# city + petite couronne, all trams, the whole metro, the RER and Transilien
# with the funicular, the C1 and the two VALs. Modes are separated by
# route_type at build time.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs data/osm web/vendor

# A downloaded extract is only accepted if it PARSES and carries a plausible
# number of elements. `grep -q '"elements"'` — the guard this family used
# everywhere — passes on a truncated response too: Brașov's roads arrived as a
# 65 kB fragment that still contained the string, was taken for complete, and
# silently skipped the city (16.08.2026).
# The minimum differs by extract: a road network runs to tens of thousands of
# ways, a city rail network to a few hundred, so the caller passes its own floor
# rather than sharing one.
# A rejected file is deleted rather than left behind — the `[ ! -f … ]` gates
# below only ask whether the file exists, so a fragment on disk would be taken
# for a finished download on the next run.
ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

# 1) GTFS — the regional bundle (stable URL, refreshed in place by TPBI)
if [ ! -f data/gtfs/routes.txt ]; then
  echo "== IDFM GTFS (Île-de-France) =="
  curl -fL --retry 3 --max-time 900 -o data/idfm.zip \
    "https://eu.ftp.opendatasoft.com/stif/GTFS/IDFM-gtfs.zip"
  unzip -o data/idfm.zip -d data/gtfs \
    agency.txt routes.txt trips.txt stop_times.txt stops.txt shapes.txt calendar.txt calendar_dates.txt
fi

# 1b) scope: which of the ~2000 regional lines belong on a PARIS map
if [ ! -f data/scope.json ]; then
  node pipeline/scope.mjs
fi

# 2) OSM from the Geofabrik extracts (14.09.2026): the RER and the Transilien
#    run to Montargis, Dreux, Gisors, Crépy-en-Valois and Château-Thierry, a
#    rail box no Overpass mirror serves, so pipeline/pbf-cut.py cuts all three
#    files (roads, city rails, the regional rail network) out of Île-de-France
#    plus the three neighbouring regions those termini lie in. The Overpass
#    queries below stay as the fallback for the two city files.
for R in ile-de-france picardie centre haute-normandie; do
  if [ ! -f "data/$R-latest.osm.pbf" ]; then
    echo "== Geofabrik $R =="
    curl -fL --retry 3 --max-time 3600 -o "data/$R-latest.osm.pbf" \
      "https://download.geofabrik.de/europe/france/$R-latest.osm.pbf" || rm -f "data/$R-latest.osm.pbf"
  fi
done
if [ ! -f data/osm/idf-rail.json ] || [ ! -f data/osm/paris.json ] || [ ! -f data/osm/paris-rail.json ]; then
  python3 pipeline/pbf-cut.py || echo "pbf-cut.py failed — falling back to Overpass for the city files" >&2
fi

# 2a) OSM — roadways over the scope extent (48.62–49.03 N, 1.94–2.91 E plus
#    margin; the T13 tram-train reaches Saint-Germain in the west, N142 exits
#    to Marne-la-Vallée in the east)
if [ ! -f data/osm/paris.json ]; then
  echo "== Overpass (roads) =="
  Q='[out:json][timeout:900];way(48.58,1.89,49.07,2.96)["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];out geom;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 900 -o data/osm/paris.json --data-urlencode "data=$Q" "$EP" \
       && ok_json "data/osm/paris.json" 2000; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/paris.json; echo "Overpass: all mirrors failed" >&2; exit 1; }
fi

# 2b) OSM — rails for the tram+metro modes: tram tracks, metro tunnels
#     (railway=subway — the viaduct stretches of M2/M6 carry the same tag) and
#     light_rail for the T4/T11/T12/T13 tram-trains. Same bbox as the roads.
if [ ! -f data/osm/paris-rail.json ]; then
  echo "== Overpass (rails) =="
  QT='[out:json][timeout:600];way(48.58,1.89,49.07,2.96)["railway"~"^(subway|tram|light_rail|rail)$"];out geom;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 300 -o data/osm/paris-rail.json --data-urlencode "data=$QT" "$EP" \
       && ok_json "data/osm/paris-rail.json" 40; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/paris-rail.json; echo "Overpass (rails): all mirrors failed" >&2; exit 1; }
fi

# 3) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

[ -f data/osm/idf-rail.json ] || { echo "data/osm/idf-rail.json missing — the RER and Transilien need pipeline/pbf-cut.py" >&2; exit 1; }
echo "OK — data ready:"
du -sh data/osm/paris.json data/osm/paris-rail.json data/osm/idf-rail.json 2>/dev/null || true
