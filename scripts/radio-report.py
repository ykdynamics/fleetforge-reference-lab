#!/usr/bin/env python3
"""Turn a captured MQTT stream into a device report with freshness verdicts.

Reads the capture on stdin. ROLE and WINDOW come from the environment.
Separated from radio-devices.sh so the capture can be piped in: a heredoc and a
pipe cannot both own stdin.
"""
import json, os, sys, time, collections

role   = os.environ['ROLE']
window = os.environ['WINDOW']
msgs   = collections.defaultdict(list)

for line in sys.stdin:
    line = line.strip()
    if not line or ' ' not in line:
        continue
    topic, _, payload = line.partition(' ')
    try:
        msgs[topic].append(json.loads(payload))
    except Exception:
        msgs[topic].append(payload)

# freshness(values) -> verdict. Several distinct values over the window means the field
# is being re-measured; one value repeated means it is not, whatever the message rate.
def freshness(values):
    """Classify how confident we can be that a field is being re-measured.

    A field that CHANGES during the window is definitely live. A field that does not
    change is genuinely ambiguous: a switch nobody touched, an energy counter at 10 W,
    and a cached voltage all look identical from here. Reporting that as a warning
    would fire constantly on healthy data and train people to ignore it, so it is
    UNKNOWN -- not measurable by this check -- which is what it actually is.
    """
    if not values:
        return 'UNKNOWN', 'never seen in this window'
    distinct = {json.dumps(v, sort_keys=True) for v in values}
    if len(values) == 1:
        return 'UNKNOWN', '1 report — too few to judge'
    if len(distinct) > 1:
        return 'PASS', f'{len(values)} reports, {len(distinct)} distinct — re-measured'
    return 'UNKNOWN', f'{len(values)} reports, unchanged — constant or cached, indistinguishable here'

print('\n-- service --')
if role == 'zigbee':
    info = msgs.get('zigbee2mqtt/bridge/info', [])
    if info:
        i = info[-1]
        co = (i.get('coordinator') or {})
        print(f"PASS    coordinator: {co.get('type')} (zigbee2mqtt {i.get('version')})")
        pj = i.get('permit_join')
        print(f"{'WARN' if pj else 'PASS':<7} pairing window: {'OPEN — devices can join this gateway' if pj else 'closed'}")
    else:
        print('UNKNOWN service info not published in this window')
else:
    st = msgs.get('zwavejs/driver/status', [])
    print(f"PASS    driver status: {st[-1]}" if st else 'UNKNOWN driver status not published in this window')
    for t, v in msgs.items():
        if t.endswith('/status') and '_CLIENTS' in t:
            print(f"PASS    gateway client online: {v[-1].get('value') if isinstance(v[-1], dict) else v[-1]}")

print('\n-- devices --')

def age_of(stamps):
    """Human age of the newest timestamp, when the payload carried one.

    Z-Wave ValueID payloads carry the time the value was recorded, which beats
    counting reports: it distinguishes a value measured seconds ago from a retained
    one republished at subscribe time. Zigbee2MQTT payloads carry no per-field
    timestamp, so this stays absent there rather than being invented.
    """
    if not stamps:
        return ''
    newest = max(stamps) / 1000.0
    secs = int(time.time() - newest)
    if secs < 90:
        return f', measured {secs}s ago'
    if secs < 5400:
        return f', measured {secs // 60}m ago'
    return f', measured {secs // 3600}h ago'


def report(name, ident, fields):
    print(f"\n  {name}")
    if ident:
        print(f"    {ident}")
    for entry in fields:
        label, values = entry[0], entry[1]
        stamps = entry[2] if len(entry) > 2 else []
        verdict, why = freshness(values)
        last = values[-1] if values else None
        print(f"    {verdict:<7} {label:<10} last={last!s:<10} ({why}{age_of(stamps)})")

found = 0
if role == 'zigbee':
    devices = msgs.get('zigbee2mqtt/bridge/devices', [])
    defs = {}
    if devices:
        for d in devices[-1]:
            if d.get('type') != 'Coordinator':
                defs[d.get('friendly_name')] = d
    for fname, d in defs.items():
        states = [m for t, ms in msgs.items() if t == f'zigbee2mqtt/{fname}' for m in ms if isinstance(m, dict)]
        found += 1
        report(
            fname,
            f"{d.get('manufacturer')} {(d.get('definition') or {}).get('model')} — {(d.get('definition') or {}).get('description')}",
            [('state',   [s.get('state')   for s in states if 'state'   in s]),
             ('power',   [s.get('power')   for s in states if 'power'   in s]),
             ('current', [s.get('current') for s in states if 'current' in s]),
             ('voltage', [s.get('voltage') for s in states if 'voltage' in s]),
             ('energy',  [s.get('energy')  for s in states if 'energy'  in s])],
        )
else:
    # ValueID topics: <prefix>/<loc>/<node>/<commandClass>/<endpoint>/<property>
    # ValueID topics are <prefix>/[location]/<node>/<commandClass>/<endpoint>/<property...>.
    # The location is optional and the property can span several segments, so the depth
    # varies -- parsing from the right reads a command class as a node id and invents
    # devices that do not exist. Parse from the left instead: after the prefix, the first
    # numeric segment is the node, and the one after it is the command class.
    def split_valueid(topic):
        parts = topic.split('/')[1:]          # drop the prefix
        for i, seg in enumerate(parts):
            if seg.isdigit():
                if i + 1 < len(parts) and parts[i + 1].isdigit():
                    return seg, parts[i + 1], '/'.join(parts[i + 3:])
                return seg, None, None
        return None, None, None

    nodes = {}
    for t, ms in msgs.items():
        if '_CLIENTS' in t or t.endswith('/driver/status'):
            continue
        node, cc, prop = split_valueid(t)
        # 255 is the broadcast pseudo-node, not a device.
        if node is None or node == '255':
            continue
        if t.endswith('/nodeinfo') and isinstance(ms[-1], dict):
            nodes.setdefault(node, {})['info'] = ms[-1]
        elif cc and prop:
            entry = nodes.setdefault(node, {})
            entry.setdefault('values', collections.defaultdict(list))
            entry.setdefault('times', collections.defaultdict(list))
            for m in ms:
                key = f"{cc}/{prop}"
                entry['values'][key].append(m.get('value') if isinstance(m, dict) else m)
                if isinstance(m, dict) and isinstance(m.get('time'), (int, float)):
                    entry['times'][key].append(m['time'])
    for node, data in sorted(nodes.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
        info = data.get('info') or {}
        if info.get('isControllerNode'):
            continue
        found += 1
        vals = data.get('values', {})
        times = data.get('times', {})
        # CC 37 = Binary Switch, CC 49 = Meter. Named explicitly: a command class is not
        # self-describing, and this mapping is the Z-Wave control contract.
        report(
            f"node {node} — {info.get('name') or '(unnamed)'}",
            f"{info.get('manufacturer')} {info.get('productLabel')} — {info.get('productDescription')}"
            + (f" | security: {info.get('security')}" if info.get('security') else ''),
            [('switch', vals.get('37/currentValue', []), times.get('37/currentValue', [])),
             ('target', vals.get('37/targetValue', []), times.get('37/targetValue', [])),
             ('power',  vals.get('49/Power', []),        times.get('49/Power', []))],
        )

if not found:
    print('  UNKNOWN no devices were reported in this window')

print("""
-- how to read this --
  PASS    the field changed during the window, so it is definitely being re-measured
  UNKNOWN the field never changed, or was seen too few times. A switch nobody
          touched, an energy counter at 10 W and a cached reading all look the
          same from here — this check cannot tell them apart, so it does not guess

An UNKNOWN is not a fault. To decide whether an unchanging field is constant or
cached, change the thing it measures and watch, or read it explicitly.

Service health above is not device health, and neither is proof that any device
responded to anything. A zero reading is a measurement: a load below the plug's
resolution reports 0 W truthfully.""")
