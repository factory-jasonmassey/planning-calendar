#!/usr/bin/env bash
# Smoke test for the Planning Calendar. Drives the real page in a browser.
# All test data lives under an isolated storage key (?store=smoke), so real
# calendar data is never read, changed, or deleted by this script.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PAGE="file://$DIR/index.html?store=smoke"
SHOTS="$DIR/screenshots"
KEY="planning-calendar.v1.smoke"
AB=(agent-browser)
if [ -n "${FACTORY_DESKTOP_CDP_PORT:-}" ] && [ -n "${AGENT_BROWSER_CDP:-}" ]; then
  AB+=(--cdp "$AGENT_BROWSER_CDP")
fi
export AGENT_BROWSER_SESSION="${AGENT_BROWSER_SESSION:-planning-calendar-smoke}"
ab() { "${AB[@]}" "$@"; }
fail() { echo "FAIL: $*"; exit 1; }
expect() { [ "$1" = "$2" ] || fail "$3 (expected $2, got $1)"; }
clear_test_keys() { ab eval "Object.keys(localStorage).filter(k => k.startsWith('$KEY')).forEach(k => localStorage.removeItem(k)); 1" >/dev/null; }
reload() { ab open "$PAGE" >/dev/null; ab wait --load domcontentloaded >/dev/null; }

Y=$(date +%Y); M=$(date +%m)
D1="$Y-$M-10"; D2="$Y-$M-12"; D3="$Y-$M-11"; D4="$Y-$M-14"; D5="$Y-$M-20"
PAST="$(date -v-1y +%Y)-03-02"
NEXT_M="$(date -v1d -v+1m +%Y-%m)-03"
NEXT2_M="$(date -v1d -v+2m +%Y-%m)-15"

drag() { ab eval "(() => {
  const a = document.querySelector('[data-key=\"$1\"]'), b = document.querySelector('[data-key=\"$2\"]');
  a.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, button:0}));
  b.dispatchEvent(new MouseEvent('mouseover', {bubbles:true}));
  b.dispatchEvent(new MouseEvent('mouseup', {bubbles:true}));
  return 'ok'; })()" >/dev/null; }

mkdir -p "$SHOTS"
ab set viewport 1440 900 >/dev/null
reload
clear_test_keys
reload
expect "$(ab get count '.cal-item')" 3 "starter calendars"
expect "$(ab eval "JSON.parse(localStorage.getItem('planning-calendar.v1.smoke') || 'null') === null")" true "nothing saved before first edit"

echo "== ranges in Customer engagements =="
ab click ".cal-item:nth-child(3)" >/dev/null
drag "$D1" "$D2"
expect "$(ab get count '.day.sel')" 3 "selected days"
ab fill "#ed-title" "Acme workshop"
ab click "#ed-save" >/dev/null
expect "$(ab get count '.bar:not(.empty)')" 3 "bar segments after save"
drag "$D4" "$D3"
ab eval "document.querySelector('[data-key=\"$D5\"]').dispatchEvent(new MouseEvent('mousedown', {bubbles:true, button:0, shiftKey:true})); 1" >/dev/null
expect "$(ab get value '#ed-start')" "$D3" "start after shift-click"
expect "$(ab get value '#ed-end')" "$D5" "end after shift-click"
ab fill "#ed-title" "Globex onsite"
ab click "#ed-save" >/dev/null
expect "$(ab eval "document.querySelectorAll('[data-key=\"$D2\"] .bar:not(.empty)').length")" 2 "overlapping bars"
ab click "[data-key='$Y-$M-25']" >/dev/null
ab press Escape >/dev/null
expect "$(ab get count '.day.sel')" 0 "selection after esc"

echo "== roster: quick add, blank date, bulk paste =="
ab click ".cal-item:nth-child(1)" >/dev/null
expect "$(ab eval "!document.getElementById('modes').hidden")" true "roster toggle visible"
ab click "#modes [data-mode='roster']" >/dev/null
ab fill "#ra-name" "Alex Existing"
ab fill "#ra-role" "Sales Manager"
ab click "#ra-form [type=submit]" >/dev/null
ab click "#ra-bulk-toggle" >/dev/null
ab eval "document.getElementById('ra-bulk-text').value = 'Bea Old, AE, $PAST\nCara Now, SE, $D1\nDev Next, AE, $NEXT_M\nEli Later, CSM, $(date -v1d -v+2m +%m)/15/$(date -v1d -v+2m +%Y)\n2026-01-01'; 1" >/dev/null
ab click "#ra-bulk-add" >/dev/null
expect "$(ab get count 'tr.person')" 5 "people in roster"
expect "$(ab get value '#ra-bulk-text')" "2026-01-01" "unreadable line left in box"
expect "$(ab get text '.kpi.now .v')" 3 "on team today (blank + past + this month before today)"
echo "kpis: $(ab get text '.kpis')"
ab screenshot "$SHOTS/05-roster.png" >/dev/null

echo "== edit person moves counts =="
ab eval "[...document.querySelectorAll('tr.person')].find(r => r.textContent.includes('Dev Next')).click(); 1" >/dev/null
expect "$(ab eval "document.getElementById('ed-end-field').hidden")" true "end date hidden for roster"
ab fill "#ed-start" ""
ab click "#ed-save" >/dev/null
expect "$(ab get text '.kpi.now .v')" 4 "on team today after clearing Dev's date"

echo "== month view shows month-end headcount =="
ab click "#modes [data-mode='cal']" >/dev/null
echo "month title: $(ab get text '.month-title')"
ab screenshot "$SHOTS/01-month.png" >/dev/null

echo "== persistence across reload =="
reload
expect "$(ab eval "JSON.parse(localStorage.getItem('$KEY')).calendars[0].events.length")" 5 "people after reload"
expect "$(ab eval "JSON.parse(localStorage.getItem('$KEY')).calendars[2].events.length")" 2 "engagements after reload"

echo "== migration from v1 data keeps everything =="
ab eval "localStorage.setItem('$KEY', JSON.stringify({calendars:[{id:'a',name:'New hire start dates',color:'#22c55e',events:[{id:'x',title:'Old Hire',start:'$D1',end:'$D1',color:'#22c55e'}]},{id:'b',name:'Trips',color:'#3b82f6',events:[{id:'y',title:'Trip',start:'$D1',end:'$D4'}]}],activeId:'a',view:1,weekStart:0})); 1" >/dev/null
reload
expect "$(ab eval "JSON.parse(localStorage.getItem('$KEY')).calendars.length")" 2 "calendars kept through migration"
expect "$(ab eval "!document.getElementById('modes').hidden")" true "v1 new-hire calendar became a roster"
expect "$(ab get count '.bar:not(.empty)')" 1 "v1 event still renders"

echo "== unreadable data is set aside, not overwritten =="
ab eval "localStorage.setItem('$KEY', '{broken'); 1" >/dev/null
ab open "$PAGE" >/dev/null 2>&1 || true
ab dialog accept >/dev/null 2>&1 || true
ab wait --load domcontentloaded >/dev/null 2>&1 || true
ab eval "document.querySelector('.cal-item').click(); 1" >/dev/null
expect "$(ab eval "localStorage.getItem('$KEY') === '{broken'")" true "broken data untouched"
expect "$(ab eval "Object.keys(localStorage).some(k => k.startsWith('$KEY.unreadable-'))")" true "broken data copied aside"

echo "== backups restore =="
expect "$(ab eval "JSON.parse(localStorage.getItem('$KEY.snapshots')).length > 0")" true "snapshots exist"
ab click "#backups" >/dev/null
ab screenshot "$SHOTS/06-backups.png" >/dev/null
ab eval "window.confirm = () => true; [...document.querySelectorAll('#snap-list [data-snap]')].find(b => b.closest('li').textContent.includes('2 calendars')).click(); 1" >/dev/null
expect "$(ab eval "JSON.parse(localStorage.getItem('$KEY')).calendars.length")" 2 "restored snapshot"

echo "== views =="
ab click ".cal-item:nth-child(2)" >/dev/null
for v in 3 6 12 1; do
  ab click "#views [data-view='$v']" >/dev/null
  expect "$(ab get count '.month')" "$v" "months in view $v"
done

echo "== cleanup (test keys only) =="
clear_test_keys
[ -z "${FACTORY_DESKTOP_CDP_PORT:-}" ] && ab close >/dev/null || true
echo "SMOKE OK"
