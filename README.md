# Paris Public Transport — interactive map

Interactive, poster-grade map of the public transport network of **Paris and
the petite couronne**: 401 bus lines, the trams T1–T14, the whole metro
M1–M14 + 3bis/7bis and — since 14.09.2026 — the **RER A–E** and the
**Transilien H, J, K, L, N, P, R, U, V** to their real ends, with the
Montmartre funicular, the Câble C1 and the CDGVAL / Orlyval airport shuttles,
all rail in the official line colors — 450 lines drawn along the real street
and track geometry, weighted mean matching error 0.27 m.

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
| RER, Transilien | 2 | RER A–E and Transilien H–V whole (TER out), keyed RER-A… / TN-H…, printed as the letter | `railway=rail` over 47.95–49.35 N / 1.30–3.50 E |
| funicular, C1, VALs | 7, 6, 0 | the Montmartre funicular, the Câble C1, CDGVAL, ORLYVAL | `railway=funicular` / `subway`, `aerialway=gondola` |

Cut deliberately: rail-replacement buses (agencies RER /
Transilien and "Remplacement …" long names), the Beauvais airport coaches
(Aérobus), zone-based TàD demand-responsive services, and two outer locals
("31" Roissy, "6" Vallée Sud) whose numbers collide with the inner-city lines
the map keys by. One raw ~120 m stretch near Strasbourg–Saint-Denis and a few
like it are drawn from the GTFS shape where OSM lacks the bus-only roadway.

## The RER and the Transilien (14.09.2026)

The fourteen lines ride the metro's treatment — wide ribbon in the IDFM colour,
station discs, always-on names — under the same toggle, and are drawn to their
real ends: Cergy, Saint-Germain, Marne-la-Vallée, Saint-Rémy, the CDG terminals,
Dourdan, Saint-Martin-d'Étampes, Malesherbes, Creil, Montargis, Dreux, Gisors,
Vernon, Crépy-en-Valois, Château-Thierry, La Ferté-Milon, Provins.

* **Branches.** One letter serves many branches (RER C ends at eight places), so
  these lines do not get the one-representative-per-direction rule: the build
  takes the smallest set of stopping patterns that calls at **every station**
  of the line (greedy set cover over station names, the longest trunk first).
  Express patterns add no station and are never drawn; RER C comes out as 5
  patterns, RER D as 4, the Transilien P as 5, the U and V as one.
* **Headsigns.** IDFM's rail headsigns are mission codes (NARA, PIBU…); the
  pattern's last station is used instead.
* **Wandering shapes.** Two P patterns (Provins, Coulommiers) have shapes drawn
  through the RER tunnels under Châtelet (159 km for a 95 km run). A rail shape
  more than 1.4× the chain of its own stations is dropped and the stop sequence
  is routed along the tracks instead.
* **Rails.** The network leaves Île-de-France, so the rails come from the
  Geofabrik extracts `ile-de-france`, `picardie`, `centre` and
  `haute-normandie`, cut by `pipeline/pbf-cut.py` (which now also cuts the
  roads and the city rails; Overpass stays the fallback). About 20 m of raw
  chord remain at a dozen station throats where OSM's crossovers (excluded
  from the rail graph) are the only connection.

## Pipeline

`npm run download` fetches the IDFM feed, computes the scope, and cuts OSM roadways and rails from the Geofabrik
extracts (`pipeline/pbf-cut.py`; the city boxes 48.58–49.07 N / 1.89–2.96 E, the regional rail box
47.95–49.35 N / 1.30–3.50 E; Overpass as the fallback) and MapLibre GL. `npm run build`
map-matches every line (HMM/Viterbi on the OSM graphs) and writes GeoJSON to
`data/out/`. `npm run serve` hosts the map at http://localhost:8152.

Data: IDFM (Île-de-France Mobilités) ·
base map © OpenFreeMap / OpenMapTiles / OpenStreetMap contributors.
