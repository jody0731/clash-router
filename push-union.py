#!/usr/bin/env python3
"""Copy Union to the router's Nikki (Klaude, 2026-10-18).

Renders OS-Admin's Union template with the subscription links (never printed), checks it on the router with
`mihomo -t`, installs it as /etc/nikki/profiles/union.yaml and restarts Nikki. The template stays the one source:
never edit Union on the router. Router-only settings (China bypass, DNS filter, IPv6 off, DT-26 excluded) live
in Nikki's own settings (/etc/config/nikki), see RUNBOOK.md Phase 3.

Usage: ./push-union.py               render, check, install, restart Nikki
       ./push-union.py --no-restart  render, check, install only
"""
import os
import re
import json
import subprocess
import sys
from pathlib import Path

import yaml

# Where the template and the links live; override with UNION_TEMPLATE / UNION_SUBS, the router with ROUTER.
OS_ADMIN = Path.home() / 'Projects/BrainStorm/OS-Admin/clash'
TEMPLATE = Path(os.environ.get('UNION_TEMPLATE', OS_ADMIN / 'Union.template.yaml'))
SUBS = Path(os.environ.get('UNION_SUBS', OS_ADMIN / 'subscriptions.yaml'))
NODES = Path(os.environ.get('UNION_NODES', OS_ADMIN / 'nodes.yaml'))
SSH = ['ssh', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no', '-o', 'LogLevel=ERROR',
       '-o', 'ConnectTimeout=5', os.environ.get('ROUTER', 'root@192.168.3.1')]
NEW, DEST = '/etc/nikki/profiles/union.yaml.new', '/etc/nikki/profiles/union.yaml'


def router(cmd, stdin=None):
    r = subprocess.run(SSH + [cmd], input=stdin, capture_output=True, text=True)
    # Mask any link before showing output: it must never reach the screen or a log.
    out = re.sub(r'(https?|tcp)://\S+', r'\1://<masked>', (r.stdout + r.stderr).strip())
    return r.returncode, out


subs = yaml.safe_load(SUBS.read_text())
text = TEMPLATE.read_text()
used = sorted(set(re.findall(r'@SUB:([^@]+)@', text)))
for name in used:
    if not subs.get(name):
        sys.exit(f'No link for {name} in {SUBS}')
    text = text.replace(f'@SUB:{name}@', subs[name])
# Nodes carried inline for an airport whose link only opens briefly (E-IX, OS-Admin's clash/nodes.yaml, 2026-10-21).
nodes = yaml.safe_load(NODES.read_text()) if NODES.is_file() else {}
for name in sorted(set(re.findall(r'@NODES:([^@]+)@', text))):
    if not (nodes.get(name) or {}).get('proxies'):
        sys.exit(f'No nodes for {name} in {NODES}')
    text = text.replace(f'@NODES:{name}@', json.dumps(nodes[name]['proxies'], ensure_ascii=False, separators=(',', ':')))

rc, out = router(f'umask 077 && cat > {NEW} && mihomo -t -d /etc/nikki/run -f {NEW} 2>&1 | tail -3', text)
if rc or 'successful' not in out:
    router(f'rm -f {NEW}')
    sys.exit(f'Union failed the check on the router, nothing changed:\n{out}')
router(f'mv {NEW} {DEST}')
print(f'Union installed on the router ({len(text.splitlines())} lines, {len(used)} links filled in), check passed.')

if '--no-restart' not in sys.argv:
    rc, out = router('service nikki restart 2>&1; sleep 5; pidof mihomo >/dev/null && echo running || echo NOT running')
    print(f'Nikki: {out.splitlines()[-1] if out else "?"}')
