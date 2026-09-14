#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cuts the OSM extracts out of Geofabrik .pbf files — the same JSON shape
Overpass returns ('elements': ways with tags, node ids and geometry), so
build.mjs cannot tell the difference. Written 14.09.2026, when the RER and
Transilien joined the map:

  data/osm/paris.json       roads, the bus box (48.58-49.07 N, 1.89-2.96 E)
                            — as download.sh has always asked Overpass;
  data/osm/paris-rail.json  trams, metro tunnels, tram-trains — same box;
  data/osm/idf-rail.json    the RER and Transilien network to its real ends
                            (Montargis, Dreux, Gisors, Crépy-en-Valois,
                            Château-Thierry: 47.95-49.35 N, 1.30-3.50 E), plus
                            the Montmartre funicular, the Câble C1 gondola and
                            the CDGVAL / ORLYVAL people movers.

Île-de-France alone does not reach those termini, so the rail box also reads
picardie (Creil, Crépy, Château-Thierry, La Ferté-Milon), centre (Dreux,
Montargis, Malesherbes) and haute-normandie (Gisors, Vernon). Way ids are
OSM's own, so the overlap of neighbouring extracts is deduped here.
"""
import json, os, re, sys
import osmium

ROOT = os.path.join(os.path.dirname(__file__), '..')
NAMES = ['ile-de-france', 'picardie', 'centre', 'haute-normandie']
PBFS = [os.path.join(ROOT, 'data', f'{n}-latest.osm.pbf') for n in NAMES]

ROAD_BOX = (48.58, 1.89, 49.07, 2.96)    # S, W, N, E — as download.sh
IDF_BOX = (47.95, 1.30, 49.35, 3.50)
HW = re.compile(r'^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$')
CITY_RAIL = re.compile(r'^(subway|tram|light_rail|rail)$')
IDF_RAIL = re.compile(r'^(rail|light_rail|subway|funicular|monorail|tram)$')
AERIAL = re.compile(r'^(gondola|cable_car|mixed_lift)$')

files = {k: os.path.join(ROOT, f'data/osm/{k}.json') for k in ('paris', 'paris-rail', 'idf-rail')}
need = {k: not os.path.exists(f) for k, f in files.items()}
print('potrzebne:', need, flush=True)
if not any(need.values()):
    sys.exit(0)
os.makedirs(os.path.join(ROOT, 'data/osm'), exist_ok=True)
out = {k: {} for k in files}


def inside(box, la0, la1, lo0, lo1):
    s, w, n, e = box
    return la1 >= s and la0 <= n and lo1 >= w and lo0 <= e


class H(osmium.SimpleHandler):
    def __init__(self, first):
        super().__init__()
        self.first = first   # roads and city rails come from ile-de-france alone

    def way(self, w):
        tags = w.tags
        hw, rw, aw = tags.get('highway'), tags.get('railway'), tags.get('aerialway')
        road = self.first and need['paris'] and hw is not None and HW.match(hw)
        city = self.first and need['paris-rail'] and rw is not None and CITY_RAIL.match(rw)
        idf = need['idf-rail'] and ((rw is not None and IDF_RAIL.match(rw)) or (aw is not None and AERIAL.match(aw)))
        if not (road or city or idf):
            return
        geom, ids = [], []
        la0, la1, lo0, lo1 = 90.0, -90.0, 180.0, -180.0
        for n in w.nodes:
            try:
                lo, la = n.lon, n.lat
            except osmium.InvalidLocationError:
                continue
            ids.append(n.ref)
            geom.append({'lat': la, 'lon': lo})
            if la < la0: la0 = la
            if la > la1: la1 = la
            if lo < lo0: lo0 = lo
            if lo > lo1: lo1 = lo
        if len(geom) < 2:
            return
        el = {'type': 'way', 'id': w.id, 'nodes': ids, 'tags': {t.k: t.v for t in tags}, 'geometry': geom}
        if road and inside(ROAD_BOX, la0, la1, lo0, lo1):
            out['paris'][w.id] = el
        if city and inside(ROAD_BOX, la0, la1, lo0, lo1):
            out['paris-rail'][w.id] = el
        if idf and inside(IDF_BOX, la0, la1, lo0, lo1):
            # a way cut at an extract border arrives with fewer located nodes:
            # keep the most complete copy
            old = out['idf-rail'].get(w.id)
            if old is None or len(old['nodes']) < len(ids):
                out['idf-rail'][w.id] = el


for k, pbf in enumerate(PBFS):
    if not os.path.exists(pbf):
        sys.exit(f'brak {pbf} — pobierz go (pipeline/download.sh)')
    if k > 0 and not need['idf-rail']:
        break
    print('czytam', os.path.basename(pbf), flush=True)
    H(k == 0).apply_file(pbf, locations=True, idx='flex_mem')

GEN = 'pbf-cut.py (Geofabrik: ' + ', '.join(NAMES) + ')'
for k, f in files.items():
    if not need[k]:
        continue
    json.dump({'version': 0.6, 'generator': GEN, 'elements': list(out[k].values())}, open(f, 'w'))
    print(f'{k}: {len(out[k])} ways', flush=True)
print('gotowe', flush=True)
