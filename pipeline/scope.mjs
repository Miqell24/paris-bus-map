// Wyznacza zakres mapy Paryża z regionalnego feedu IDFM (całe Île-de-France,
// ~2000 linii) i zapisuje listę route_id do data/scope.json. Reguły:
//
//  autobusy (route_type 3):
//   - linia należy do mapy, gdy >=50% jej przystanków leży w promieniu 15 km
//     od centrum (Notre-Dame) — miasto + petite couronne, z pełną narysowaną
//     trasą także tam, gdzie ogon wybiega dalej;
//   - odpadają agencje RER / Transilien (autobusy zastępcze za kolej — jak
//     pótló w Budapeszcie) i Aérobus (autokary lotniskowe do Beauvais, 69 km);
//   - odpadają linie z JAKIMKOLWIEK przystankiem dalej niż 35 km (dwa
//     podmiejskie ekspresy 7823 i 3754 z paryską głową);
//   - odpadają IDFM:C00208 („31" z Roissy) i IDFM:C00343 („6" z Vallée Sud):
//     mapa kluczuje linie numerem, a te dublują numery linii śródmiejskich.
//  tramwaje (0): wszystkie T1–T14; odpadają lotniskowe CDG VAL i ORLYVAL.
//  metro (1): wszystkie (M1–M14 + 3bis/7bis).
//  poza mapą w całości: RER/Transilien (2), funikular Montmartre (7),
//  kolejka linowa Câble C1 (6).
//
// Uruchamiane przez download.sh po pobraniu GTFS; build.mjs wymaga wyniku.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { iterCsv, readCsv } from './lib/csv.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GD = join(ROOT, 'data/gtfs');

const CX = 2.3488, CY = 48.8534;      // Notre-Dame
const CORE_KM = 15, CORE_SHARE = 0.5, CAP_KM = 35;
const BAD_AGENCIES = new Set(['RER', 'Transilien', 'Aérobus']);
const BAD_ROUTES = new Set(['IDFM:C00208', 'IDFM:C00343']);
const BAD_TRAMS = new Set(['CDG VAL', 'ORLYVAL']);
// zastępcze za tramwaj (long_name „Remplacement …": busy T1/T2/T4 w feedzie)
// i strefowy transport na żądanie — to nie są linie o stałej trasie
const isReplacement = (r) => /^Remplacement/i.test(r.route_long_name || '');
const isTaD = (r) => /^TàD/i.test(r.route_short_name || '');

const t0 = Date.now();
const log = (m) => console.log(`[scope ${((Date.now() - t0) / 1000).toFixed(0)}s] ${m}`);

const agency = new Map();
for (const a of await readCsv(join(GD, 'agency.txt'))) agency.set(a.agency_id, a.agency_name);

const busCand = new Set(), tram = [], metro = [];
for (const r of await readCsv(join(GD, 'routes.txt'))) {
  const an = agency.get(r.agency_id) || '';
  if (r.route_type === '3') {
    if (BAD_AGENCIES.has(an) || BAD_ROUTES.has(r.route_id)) continue;
    if (isReplacement(r) || isTaD(r)) continue;
    busCand.add(r.route_id);
  } else if (r.route_type === '0') {
    if (!BAD_TRAMS.has((r.route_short_name || '').trim())) tram.push(r.route_id);
  } else if (r.route_type === '1') metro.push(r.route_id);
}
log(`kandydatów bus: ${busCand.size}, tram: ${tram.length}, metro: ${metro.length}`);

const mx = 111320 * Math.cos(48.85 * Math.PI / 180), my = 111132;
const stopKm = new Map();
for await (const s of iterCsv(join(GD, 'stops.txt'))) {
  const lat = Number(s.stop_lat), lon = Number(s.stop_lon);
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    stopKm.set(s.stop_id, Math.hypot((lon - CX) * mx, (lat - CY) * my) / 1000);
  }
}
const t2r = new Map();
for await (const t of iterCsv(join(GD, 'trips.txt'))) {
  if (busCand.has(t.route_id)) t2r.set(t.trip_id, t.route_id);
}
log(`kursów autobusowych do zmierzenia: ${t2r.size}`);
// jeden strumień przez stop_times: per trasa zbiór przystanków → udział <=15 km i maksimum
const rStops = new Map();
for await (const st of iterCsv(join(GD, 'stop_times.txt'))) {
  const rid = t2r.get(st.trip_id);
  if (!rid) continue;
  let s = rStops.get(rid);
  if (!s) rStops.set(rid, (s = new Set()));
  s.add(st.stop_id);
}
const bus = [];
let cut = 0;
for (const [rid, stops] of rStops) {
  let n = 0, inside = 0, max = 0;
  for (const sid of stops) {
    const d = stopKm.get(sid);
    if (d === undefined) continue;
    n++; if (d <= CORE_KM) inside++; if (d > max) max = d;
  }
  if (!n) continue;
  if (inside / n < CORE_SHARE) continue;
  if (max > CAP_KM) { cut++; continue; }
  bus.push(rid);
}
log(`wybrano bus: ${bus.length} (odrzucone limitem ${CAP_KM} km: ${cut})`);
writeFileSync(join(ROOT, 'data/scope.json'),
  JSON.stringify({ bus: bus.sort(), tram: tram.sort(), metro: metro.sort() }, null, 0));
log('zapisano data/scope.json');
