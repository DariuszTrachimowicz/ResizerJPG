# Copyright (c) 2026 Dariusz Trachimowicz / Digital Xperts
# SPDX-License-Identifier: GPL-3.0-only
# See LICENSE for terms. Distributed WITHOUT ANY WARRANTY.
"""Convert the original logo and Lucide vectors to native application assets."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--logo', type=Path, required=True)
parser.add_argument('--lucide', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with Image.open(args.logo) as logo:
    logo.convert('RGBA').save(args.output / 'digital-xperts-logo.png')
    icon = logo.convert('RGBA')
    canvas = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    icon.thumbnail((232, 232), Image.Resampling.LANCZOS)
    canvas.alpha_composite(icon, ((256-icon.width)//2, (256-icon.height)//2))
    canvas.save(args.output / 'resizer-jpg.ico', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])

names = ['folder-plus','images','trash-2','play','square','folder-open','refresh-cw','settings-2','chevron-left','chevron-right','external-link','download','scan','image','list','sliders-horizontal','check','x','zoom-in','zoom-out','crop','circle-question-mark']
geometries = {}
for name in names:
    source_name = {'trash-2': 'trash', 'settings-2': 'sliders-horizontal'}.get(name, name)
    tree = ET.parse(args.lucide / 'icons' / (source_name + '.svg'))
    paths = []
    for element in tree.getroot():
        tag = element.tag.rsplit('}',1)[-1]
        a = element.attrib
        if tag == 'path':
            data = a['d']
            # Independent SVG paths start at the origin. Joining them must not
            # offset an initial relative moveto by the previous path's endpoint.
            # Keep m lowercase: its repeated pairs are relative lineto commands.
            if paths and data.lstrip().startswith('m'):
                data = 'M0 0 ' + data
            paths.append(data)
        elif tag == 'line':
            paths.append(f"M{a['x1']},{a['y1']} L{a['x2']},{a['y2']}")
        elif tag in ('polyline','polygon'):
            paths.append('M' + a['points'] + (' Z' if tag == 'polygon' else ''))
        elif tag == 'circle':
            cx,cy,r = (float(a[k]) for k in ('cx','cy','r'))
            paths.append(f'M{cx-r},{cy} A{r},{r} 0 1 0 {cx+r},{cy} A{r},{r} 0 1 0 {cx-r},{cy}')
        elif tag == 'rect':
            x,y,w,h = (float(a.get(k,'0')) for k in ('x','y','width','height'))
            paths.append(f'M{x},{y} H{x+w} V{y+h} H{x} Z')
        else:
            raise ValueError(f'Unsupported SVG element {tag} in {name}')
    geometries[name] = ' '.join(paths)
(args.output / 'lucide-paths.json').write_text(json.dumps(geometries,indent=2), encoding='ascii')
(args.output / 'THIRD-PARTY-NOTICES.txt').write_text((args.lucide / 'LICENSE').read_text(encoding='utf-8') + '\n\nDigital Xperts logo: supplied from the owner project, used by instruction of Dariusz Trachimowicz.\n', encoding='utf-8')
