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
import subprocess
import sys
from pathlib import Path

import yaml

# Where the template and the links live; override with UNION_TEMPLATE / UNION_SUBS, the router with ROUTER.
OS_ADMIN = Path.home() / 'Projects/BrainStorm/OS-Admin/clash'
TEMPLATE = Path(os.environ.get('UNION_TEMPLATE', OS_ADMIN / 'Union.template.yaml'))
SUBS = Path(os.environ.get('UNION_SUBS', OS_ADMIN / 'subscriptions.yaml'))
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

rc, out = router(f'umask 077 && cat > {NEW} && mihomo -t -d /etc/nikki/run -f {NEW} 2>&1 | tail -3', text)
if rc or 'successful' not in out:
    router(f'rm -f {NEW}')
    sys.exit(f'Union failed the check on the router, nothing changed:\n{out}')
router(f'mv {NEW} {DEST}')
print(f'Union installed on the router ({len(text.splitlines())} lines, {len(used)} links filled in), check passed.')

if '--no-restart' not in sys.argv:
    rc, out = router('service nikki restart 2>&1; sleep 5; pidof mihomo >/dev/null && echo running || echo NOT running')
    print(f'Nikki: {out.splitlines()[-1] if out else "?"}')
