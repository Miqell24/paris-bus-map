# Paris Public Transport — interactive map

Interactive, poster-grade map of the public transport network of **Paris and
the petite couronne**: 399 bus lines, the trams T1–T14 and the whole metro
M1–M14 + 3bis/7bis in the official line colors — 430 lines / 9 400 km drawn
along the real street and track geometry, weighted mean matching error 0.13 m.

## Live

**https://miqell24.github.io/paris-bus-map/** — GitHub Pages from `main:/docs`. Local build on port 8152 (`npm run serve`).

Everything comes from ONE feed — the IDFM regional GTFS
(https://eu.ftp.opendatasoft.com/stif/GTFS/IDFM-gtfs.zip, the whole
Île-de-France, ~2000 lines) — so the map's scope is a precomputed allowlist
(`pipeline/scope.mjs` → `data/scope.json`):

| mode | route_type | scope | graph |
|---|---|---|---|
| buses | 3 | ≥50% of stops within 15 km of Notre-Dame, no stop past 35 km | OSM roadways |
| trams | 0 | all T1–T14 (CDG VAL / ORLYVAL excluded) | `railway=tram` + `light_rail` + plain `rail` for T12's RER-C stretch |
| metro | 1 | all 16, keyed M1…M14, official colors from `routes.txt` | `railway=subway` |

Cut deliberately: RER and Transilien (route_type 2), the Montmartre funicular
(7), the Câble C1 gondola (6), rail-replacement buses (agencies RER /
Transilien and "Remplacement …" long names), the Beauvais airport coaches
(Aérobus), zone-based TàD demand-responsive services, and two outer locals
("31" Roissy, "6" Vallée Sud) whose numbers collide with the inner-city lines
the map keys by. One raw ~120 m stretch near Strasbourg–Saint-Denis and a few
like it are drawn from the GTFS shape where OSM lacks the bus-only roadway.

## Pipeline

`npm run download` fetches the IDFM feed, computes the scope, and pulls OSM roadways and rails (Overpass,
bbox 48.58–49.07 N / 1.89–2.96 E) and MapLibre GL. `npm run build`
map-matches every line (HMM/Viterbi on the OSM graphs) and writes GeoJSON to
`data/out/`. `npm run serve` hosts the map at http://localhost:8152.

Data: IDFM (Île-de-France Mobilités) ·
base map © OpenFreeMap / OpenMapTiles / OpenStreetMap contributors.
