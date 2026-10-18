// Stall watcher for the router's Clash (Nikki/mihomo). A port of os-admin's PC watcher (OS-Admin 3be54ab, NODESTALL).
//
// Why: on 2026-10-18 a provider's US nodes delivered the first ~16 KB of every response, then stalled. mihomo's
// health checks only send HEAD requests, so the nodes stayed "alive" and the fallback group never left them.
//
// Every EVERY s it reads the live connections from the local controller (no test traffic). A node is suspect when
// TCP connections to STUCK_HOSTS+ different sites have sat STUCK_AGE..STUCK_MAX_AGE s under STUCK_BYTES, unchanged
// since the last look (older idle ones are push channels), and none of its connections delivered more than that
// in the last PROGRESS s. One probe page through the router's own mixed port confirms it; then the node's fallback
// group is fixed on its next member that delivers (same group = same country, at most 4 tried). Never url-test or
// load-balance (exit-IP hopping got accounts flagged). A node picked by hand in a select group is only logged.
// Every LIFT_EVERY s a fix of ours is lifted and stays lifted when the group's own pick delivers again.
//
// Run:  ucode stall-watcher.uc              (the service; logs to syslog, tag stall-watcher)
//       ucode stall-watcher.uc test FILE    (a scenario with a fake controller; exit 1 when an expectation fails)
'use strict';

import * as fs from 'fs';

const EVERY = 15, STUCK_AGE = 20, STUCK_MAX_AGE = 120, STUCK_BYTES = 20000, STUCK_HOSTS = 3, PROGRESS = 60;
const COOLDOWN = 1800, LIFT_EVERY = 1800, WARN_EVERY = 3600;
const API = 'http://127.0.0.1:9090', MIXED = 'http://127.0.0.1:7890', STATE = '/etc/nikki/stall-watcher.json';
// Pages of 85-300 KB that Union's rules send through each group; read whole, they show a stall a HEAD check misses.
const PROBES = [['🔰 Proxy', 'https://en.wikipedia.org/wiki/Main_Page'], ['🤖 AI', 'https://www.anthropic.com/'],
                ['🔎 Google', 'https://www.google.com/?hl=en'], ['🐙 GitHub', 'https://github.com/about']];

// ---------------------------------------------------------------------------------------------- helpers
function shq(s) { return "'" + replace('' + s, "'", "'\\''") + "'"; }

function urlenc(s) {
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = ord(s, i);
		if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 46 || c == 95 || c == 126)
			out += chr(c);
		else
			out += sprintf('%%%02X', c);
	}
	return out;
}

function days_from_civil(y, m, d) {
	y -= m <= 2 ? 1 : 0;
	let era = int(y / 400), yoe = y - era * 400;
	let doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
	return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468;
}

// A connection's start time (RFC 3339 from the controller, nanoseconds and zone allowed) as epoch seconds, or null.
function rfc3339(s) {
	let m = match('' + s, /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?(Z|([+-])([0-9]{2}):([0-9]{2}))$/);
	if (!m)
		return null;
	let t = days_from_civil(int(m[1]), int(m[2]), int(m[3])) * 86400 + int(m[4]) * 3600 + int(m[5]) * 60 + int(m[6]);
	if (m[8] != 'Z')
		t -= (m[9] == '-' ? -1 : 1) * (int(m[10]) * 3600 + int(m[11]) * 60);
	return t;
}

function q(group) { return '/proxies/' + urlenc(group); }

// ------------------------------------------------------------------------------------------- real I/O
function sh(cmd) {
	let p = fs.popen(cmd, 'r');
	if (!p)
		return null;
	let out = p.read('all');
	p.close();
	return out;
}

const real = {
	now: () => time(),
	get: (path) => {
		let out = sh(`curl -s -m 5 ${shq(API + path)}`);
		try { return out ? json(out) : null; } catch (e) { return null; }
	},
	put: (path, body) => int(sh(`curl -s -m 5 -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -d ${shq(sprintf('%J', body))} ${shq(API + path)}`)),
	del: (path) => int(sh(`curl -s -m 5 -o /dev/null -w '%{http_code}' -X DELETE ${shq(API + path)}`)),
	// The whole page within 12 s (an error page is still a page): curl exits 0 only when the body ended in time.
	probe: (url) => {
		let out = sh(`curl -s -o /dev/null -m 12 --connect-timeout 6 -x ${shq(MIXED)} -A 'Mozilla/5.0 stall-watcher' -w '%{http_code}' ${shq(url)}; echo " $?"`);
		let m = match(out || '', /([0-9]{3}) ([0-9]+)\s*$/);
		return !!m && m[1] != '000' && m[2] == '0';
	},
	log: (msg) => { system(['logger', '-t', 'stall-watcher', msg]); },
	load: () => { try { return json(fs.readfile(STATE) || '{}') || {}; } catch (e) { return {}; } },
	save: (st) => { fs.writefile(STATE, sprintf('%J', st)); },
};

let io = real;

// ------------------------------------------------------------------------------------------------ logic
function groups() { let r = io.get('/proxies'); return (r && r.proxies) || {}; }

// group -> ... -> node, following each group's live pick
function chain(name, px) {
	let hops = [name];
	while (px[hops[-1]] && length(px[hops[-1]].all || []) && px[hops[-1]].now && length(hops) < 6)
		push(hops, px[hops[-1]].now);
	return hops;
}

// The probe page whose route runs through `group`, or null.
function probe_for(group, px) {
	for (let p in PROBES)
		if (px[p[0]] && index(chain(p[0], px), group) >= 0)
			return p[1];
	return null;
}

// Fix fallback group `fb` on its next member (the group's order, same country, at most 4) that delivers `url`.
function stall_switch(fb, node, url, px) {
	let ours = io.load();
	for (let cand in slice(filter(px[fb].all || [], (m) => m != node), 0, 4)) {
		if (io.put(q(fb), { name: cand }) == 204 && io.probe(url)) {
			ours[fb] = cand;
			io.save(ours);
			return cand;
		}
	}
	io.del(q(fb));
	delete ours[fb];
	io.save(ours);
	return null;
}

// Lift our fix on `fb`; keep it lifted when the group's own pick delivers again. Returns [lifted, own pick].
function stall_lift(fb, url) {
	let ours = io.load();
	io.del(q(fb));
	let own = chain(fb, groups())[-1];
	if (io.probe(url)) {
		delete ours[fb];
		io.save(ours);
		return [true, own];
	}
	io.put(q(fb), { name: ours[fb] });
	return [false, own];
}

function tick(st) {
	let r = io.get('/connections');
	if (!r)
		return;
	let now = io.now(), seen = {}, stuck = {}, conns = r.connections || [];
	for (let c in conns) {
		let md = c.metadata || {}, ch = c.chains || [];
		if (md.network != 'tcp' || !length(ch) || ch[0] == 'DIRECT' || ch[0] == 'REJECT')
			continue;
		let node = ch[0], down = c.download || 0, up = c.upload || 0, prev = st.seen[c.id];
		let first = prev ? prev[0] : (rfc3339(c.start) ?? now), last = prev ? prev[1] : null;
		seen[c.id] = [first, down];
		if (last != null && down > last && down >= STUCK_BYTES)
			st.progress_at[node] = now;                   // this node delivered real data just now
		if (last != null && down == last && down < STUCK_BYTES && up > 0 && now - first >= STUCK_AGE && now - first <= STUCK_MAX_AGE) {
			stuck[node] ??= {};
			stuck[node][md.host || md.sniffHost || md.destinationIP || '?'] = true;
		}
	}
	st.seen = seen;
	for (let node in stuck) {
		let hosts = sort(keys(stuck[node]));
		if (length(hosts) < STUCK_HOSTS || now - (st.progress_at[node] || 0) < PROGRESS || (st.cooldown[node] || 0) > now)
			continue;
		let px = groups(), ch = [];
		for (let c in conns)
			if (c.chains && c.chains[0] == node) { ch = c.chains; break; }
		let fb = null;
		for (let g in slice(ch, 1))
			if (px[g] && px[g].type == 'Fallback') { fb = g; break; }
		let url = probe_for(fb ?? ch[1] ?? '', px), sites = join(', ', slice(hosts, 0, 4));
		if (!url) {
			st.cooldown[node] = now + COOLDOWN;
			continue;
		}
		if (io.probe(url)) {
			st.cooldown[node] = now + COOLDOWN;
			io.log(`${node}: ${length(hosts)} sites looked stuck (${sites}) but a probe page came through: left alone`);
			continue;
		}
		if (!fb) {
			if ((st.warned[node] || 0) < now) {
				st.warned[node] = now + WARN_EVERY;
				io.log(`${node} (picked by hand in ${ch[1]}) stalls (${sites}): pick another node there`);
			}
			continue;
		}
		let fixed = stall_switch(fb, node, url, px);
		st.cooldown[node] = now + COOLDOWN;
		io.log(fixed ? `${fb}: ${node} stalls (${sites}), switched to ${fixed}`
		             : `${fb}: ${node} stalls (${sites}) and so do its next members; left on its own pick`);
	}
}

function lift_all() {
	let px = groups(), ours = io.load();
	for (let fb in keys(ours)) {
		if (!px[fb] || px[fb].fixed != ours[fb]) {         // gone (Nikki restarted, or changed by hand): forget it
			delete ours[fb];
			io.save(ours);
			continue;
		}
		let url = probe_for(fb, px);
		if (!url)
			continue;
		let node = ours[fb], res = stall_lift(fb, url);
		io.log(res[0] ? `${fb} delivers again on its own pick ${res[1]}: fix on ${node} lifted`
		              : `${fb}: its own pick ${res[1]} still stalls, staying on ${node}`);
	}
}

function step(st) {
	try {
		tick(st);
		if (io.now() - st.last_lift >= LIFT_EVERY) {
			st.last_lift = io.now();
			lift_all();
		}
	} catch (e) {
		io.log(`tick failed: ${e}`);
	}
}

function fresh_state() { return { seen: {}, cooldown: {}, warned: {}, progress_at: {}, last_lift: io.now() }; }

// --------------------------------------------------------------------------------------- test harness
// Scenario: { px: {group: {type, now, all}}, chains: {node: [node, group, ...]}, stalled: [nodes],
//             ticks: [{ t, conns: [{id, node, host, start (s, relative), down, up}], stalled? }],
//             expect: [substrings of log lines], expect_not: [...] }
function civil(t) {
	let z = int(t / 86400) + 719468, era = int(z / 146097), doe = z - era * 146097;
	let yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365);
	let doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100)), mp = int((5 * doy + 2) / 153);
	let d = doy - int((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9, s = t % 86400;
	return sprintf('%04d-%02d-%02dT%02d:%02d:%02d.123456789Z', yoe + era * 400 + (m <= 2 ? 1 : 0), m, d,
	               int(s / 3600), int(s / 60) % 60, s % 60);
}

function run_test(file) {
	let sc = json(fs.readfile(file)), T0 = 1792300000, now = T0, conns = [], logs = [], state = {};
	let stalled = sc.stalled || [], px = sc.px;
	for (let g in keys(px)) {
		px[g].own = px[g].now;
		px[g].fixed = '';
	}
	io = {
		now: () => now,
		get: (path) => path == '/proxies' ? { proxies: px } : { connections: conns },
		put: (path, body) => {
			for (let g in keys(px))
				if (q(g) == path) { px[g].fixed = body.name; px[g].now = body.name; }
			return 204;
		},
		del: (path) => {
			for (let g in keys(px))
				if (q(g) == path) { px[g].fixed = ''; px[g].now = px[g].own; }
			return 204;
		},
		probe: (url) => {
			for (let p in PROBES)
				if (p[1] == url) {
					let node = chain(p[0], px)[-1];
					push(logs, `(probe ${url} via ${node})`);
					return index(stalled, node) < 0;
				}
			return false;
		},
		log: (msg) => push(logs, msg),
		load: () => json(sprintf('%J', state)),
		save: (st) => { state = json(sprintf('%J', st)); },
	};
	let st = fresh_state();
	for (let tk in sc.ticks) {
		now = T0 + tk.t;
		if (tk.stalled)
			stalled = tk.stalled;
		conns = map(tk.conns || [], (c) => ({
			id: c.id, start: civil(T0 + c.start), download: c.down, upload: c.up ?? 300,
			metadata: { network: 'tcp', host: c.host }, chains: sc.chains[c.node],
		}));
		step(st);
	}
	let ok = true;
	for (let l in logs)
		print(`  log: ${l}\n`);
	for (let e in sc.expect || [])
		if (!length(filter(logs, (l) => index(l, e) >= 0))) { ok = false; print(`  FAIL: expected "${e}"\n`); }
	for (let e in sc.expect_not || [])
		if (length(filter(logs, (l) => index(l, e) >= 0))) { ok = false; print(`  FAIL: did not expect "${e}"\n`); }
	print(ok ? `PASS ${sc.name}\n` : `FAIL ${sc.name}\n`);
	return ok;
}

// ----------------------------------------------------------------------------------------------- main
if (ARGV[0] == 'test') {
	exit(run_test(ARGV[1]) ? 0 : 1);
}

// One look with the real controller, and one probe page per group: `ucode stall-watcher.uc check`
if (ARGV[0] == 'check') {
	let r = io.get('/connections'), px = groups(), now = io.now(), ages = [];
	for (let c in (r && r.connections) || [])
		push(ages, now - (rfc3339(c.start) ?? now));
	ages = sort(ages, (a, b) => a - b);
	print(`controller: ${r ? 'ok' : 'NOT reachable'}, ${length(ages)} connections, ages ${ages[0] ?? '-'}..${ages[-1] ?? '-'} s\n`);
	for (let p in PROBES)
		if (px[p[0]])
			print(`${join(' → ', chain(p[0], px))}: probe ${p[1]} ${io.probe(p[1]) ? 'delivered' : 'FAILED'}\n`);
	exit(0);
}

let st = fresh_state();
io.log(`watcher started (every ${EVERY} s; stuck = ${STUCK_HOSTS}+ sites, ${STUCK_AGE}-${STUCK_MAX_AGE} s old, under ${STUCK_BYTES} B)`);
while (true) {
	step(st);
	sleep(EVERY * 1000);
}
