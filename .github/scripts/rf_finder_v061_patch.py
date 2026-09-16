from pathlib import Path


def replace_line(lines, prefix, new_line):
    hits = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(hits) != 1:
        raise RuntimeError(f"{prefix!r}: expected 1 line, got {len(hits)}")
    lines[hits[0]] = new_line


def replace_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected 1 match, got {n}")
    return text.replace(old, new, 1)


# Android Web UI
p = Path('rf_finder/android/app/src/main/assets/index.html')
s = p.read_text(encoding='utf-8')
lines = s.splitlines()

replace_line(lines, '.rssi{', '.rssi{font:780 clamp(54px,14vw,78px)/1 ui-monospace,monospace;color:#43DEA0}.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:8px}.stats div{text-align:center}.stats span{display:block;color:var(--muted);font-size:13px}.stats b{font:650 15px ui-monospace,monospace}.meter{height:10px;border-radius:99px;background:#080A0C;overflow:hidden;margin-top:12px}.meter i{display:block;height:100%;width:0;background:var(--green)}.freqBig{font:700 19px ui-monospace,monospace}.tuneRow{display:grid;grid-template-columns:68px 1fr 68px;align-items:center;gap:8px;margin-top:8px}.rangeRow{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px}.rangeCell label{display:block;color:var(--muted);font-size:12px;margin-bottom:5px}.rangeCell input{width:100%;min-height:48px;border:1px solid var(--hair2);border-radius:12px;background:#0B0D10;padding:0 10px;text-align:center;font:700 18px ui-monospace,monospace}.tuneState{margin-top:7px;min-height:20px}.readFreq{margin-top:10px;padding-top:10px;border-top:1px solid var(--hair);display:flex;justify-content:space-between;gap:10px}.readFreq b{font:700 15px ui-monospace,monospace}')

rssip = '<div><article class="card"><div class="label">RSSI</div><div class="rssi"><span id="rssi">—</span><small style="font:600 17px system-ui;color:#75DDB6"> dBm</small></div><div class="stats"><div><span>МИН</span><b id="minRssi">—</b></div><div><span>СРЕД</span><b id="avgRssi">—</b></div><div><span>МАКС</span><b id="peakRssi">—</b></div></div><div class="meter"><i id="meter"></i></div></article>'
replace_line(lines, rssip, rssip[:-10] + '<div class="readFreq"><span class="muted">Рабочая RF</span><b id="fixedText">2440.000 МГц</b></div></article></div></div>')
replace_line(lines, '<article class="card section"><div class="head"><span class="label">ЧАСТОТА</span>', '')

replace_line(lines, '<div class="overviewControls section">', '<div class="overviewControls section"><article class="card"><div class="label">РАБОЧАЯ ЧАСТОТА, МГц</div><div class="tuneRow"><button id="freqMinus" class="btn">−0.1</button><input id="freqInput" class="num" type="number" inputmode="decimal" step="0.001" value="2440.000"><button id="freqPlus" class="btn">+0.1</button></div><div id="tuneState" class="muted tuneState">ввод с клавиатуры · Enter применить</div><div id="receiverRange" class="muted">заявлено приёмником: 2400–2480 МГц</div></article><article class="card"><div class="label">ДИАПАЗОН ОБЗОРА, МГц</div><div class="rangeRow"><div class="rangeCell"><label for="startInput">START</label><input id="startInput" type="number" inputmode="decimal" step="0.001" value="2400.000"></div><div class="rangeCell"><label for="stopInput">STOP</label><input id="stopInput" type="number" inputmode="decimal" step="0.001" value="2480.000"></div></div><div class="chips"><button class="chip active" data-span="80">±40</button><button class="chip" data-span="40">±20</button><button class="chip" data-span="20">±10</button><button class="chip" data-span="10">±5</button></div><div id="scanEstimate" class="muted" style="margin-top:8px">ручной START/STOP разрешён · —</div></article></div><button id="scan" class="scan">▶ СКАНИРОВАТЬ</button></section>')

replace_line(lines, 'const ui=', "const ui={usb:$('usb'),device:$('device'),compassStatus:$('compassStatus'),rose:$('rose'),target:$('target'),bearing:$('bearingValue'),bearingLabel:$('bearingLabel'),turn:$('turn'),bestH:$('bestHeading'),bestP:$('bestPass'),rssi:$('rssi'),min:$('minRssi'),avg:$('avgRssi'),peak:$('peakRssi'),meter:$('meter'),fixed:$('fixedText'),freq:$('freqInput'),tuneState:$('tuneState'),receiverRange:$('receiverRange'),start:$('startInput'),stop:$('stopInput'),coverage:$('coverage'),history:$('history'),spectrum:$('spectrum'),waterfall:$('waterfall'),scanText:$('scanText'),scanState:$('scanState'),scan:$('scan'),markerF:$('markerFreq'),markerD:$('markerDbm'),go:$('goBearing'),estimate:$('scanEstimate'),signalClass:$('signalClass'),signalEvidence:$('signalEvidence'),bw:$('bwText'),profile:$('profile'),gain:$('gain'),avgSamples:$('avgSamples'),settle:$('settleUs'),step:$('stepKhz'),dwell:$('dwellMs'),diag:$('diagGrid'),log:$('log'),wfCount:$('waterfallCount'),elrs:$('elrsDetect'),elrsResult:$('elrsResult'),elrsEvidence:$('elrsEvidence'),packetLog:$('packetLog')};")
replace_line(lines, 'let lo=', "let lo=2400,hi=2480,fixed=2440,scanStart=2400,scanStop=2480,heading=null,compassAccuracy='UNRELIABLE',smoothing='normal',ema=null,peakHold=true,bestHeading=null,bestDb=-Infinity,bearingSamples=[],pendingTuneMHz=null,tuneAckTimer=null;")
replace_line(lines, 'let cap=', "let cap={bw:812500,minStep:100000,maxStep:10000000,minDwell:1,maxDwell:100,minAvg:1,maxAvg:32,maxSettle:50000,maxPoints:801,packetProbe:false},fwDiag={},lastP={duration:null,points:null},probeOn=false,packetRows=[],elrsConfirmed=false,elrsBearing=false;")
replace_line(lines, 'function bounds()', "function bounds(){let a=Number(scanStart),b=Number(scanStop);if(!Number.isFinite(a)||!Number.isFinite(b)||a===b)return[2400,2480];if(a>b)[a,b]=[b,a];return[a,b]}")
replace_line(lines, 'function renderWindow()', "function renderWindow(){const[a,b]=bounds(),span=b-a,points=Math.floor(span*1e6/currentStepHz())+1;ui.start.value=fmt(a,3);ui.stop.value=fmt(b,3);ui.scanText.textContent=fmt(a,3)+'–'+fmt(b,3)+' МГц · span '+fmt(span,3);const over=points>cap.maxPoints;ui.estimate.textContent=(over?'⚠ ':'')+points+' точек · step '+fmt(currentStepHz()/1e6,3)+' МГц'+(over?' · лимит головы '+cap.maxPoints:'');ui.estimate.className='muted'+(over?' warn':'')}")

# analyzeSweeps is one long line: add local span derived from manual bounds.
for i, line in enumerate(lines):
    if line.startswith('function analyzeSweeps()'):
        lines[i] = replace_once(line, "const union=new Set(),peaks=[];", "const span=Math.abs(bounds()[1]-bounds()[0]);const union=new Set(),peaks=[];", 'analyze span')
        break
else:
    raise RuntimeError('analyzeSweeps line missing')

replace_line(lines, 'function setProbe(on)', "function setProbe(on){probeOn=on;if(on)ui.elrs.textContent='■ STOP ELRS';else if(elrsConfirmed)ui.elrs.textContent='ПЕЛЕНГ ELRS';else ui.elrs.textContent='ELRS DETECT';ui.elrs.disabled=!on&&(!Number.isFinite(markerMHz)||!cap.packetProbe);ui.go.disabled=on||!Number.isFinite(markerMHz);ui.scan.disabled=on}")
replace_line(lines, 'function startElrs()', "function startElrs(){if(!Number.isFinite(markerMHz)||!cap.packetProbe)return;if(scanOn)stopScan();elrsBearing=false;elrsConfirmed=false;packetRows=[];renderPacketLog();setProbe(true);ui.elrsResult.textContent='ПОИСК ELRS…';ui.elrsEvidence.textContent=fmt(markerMHz)+' МГц · 80ch FHSS scan';requestTune(markerMHz);setTimeout(()=>send('Q,ELRS,'+Math.round(markerMHz*1e6)+',80000000,10000'),180)}")
# Insert new function directly after startElrs.
idx = next(i for i, line in enumerate(lines) if line.startswith('function startElrs()'))
lines.insert(idx + 1, "function startElrsBearing(){if(!elrsConfirmed||!Number.isFinite(markerMHz))return;resetStats();resetPass();elrsBearing=true;packetRows=[];renderPacketLog();setProbe(true);ui.elrsResult.textContent='ПЕЛЕНГ ELRS…';ui.elrsEvidence.textContent='RSSI подтверждённых packet RX · 30с';document.querySelector('[data-view=\"bearing\"]').click();send('Q,ELRS,'+Math.round(markerMHz*1e6)+',80000000,30000')}")
replace_line(lines, 'function stopElrs()', "function stopElrs(){send('Q,X');setProbe(false);elrsBearing=false}")
replace_line(lines, 'function setCenter(', "function setScanRange(a,b){a=Number(a);b=Number(b);if(!Number.isFinite(a)||!Number.isFinite(b)||a===b){ui.estimate.textContent='Нужны разные START и STOP';ui.estimate.className='muted warn';return false}scanStart=Math.min(a,b);scanStop=Math.max(a,b);renderWindow();drawSpectrum();drawWaterfall();return true}")
replace_line(lines, 'function showTune(', "function showTune(mhz){fixed=mhz;ui.freq.value=fmt(mhz,3);ui.fixed.textContent=fmt(mhz,3)+' МГц';ui.tuneState.textContent='применено · '+fmt(mhz,3)+' МГц';ui.tuneState.className='muted tuneState'}")
replace_line(lines, 'function requestTune(', "function requestTune(v){const mhz=Number(v);if(!Number.isFinite(mhz)||mhz<=0){ui.tuneState.textContent='Некорректная частота';ui.tuneState.className='muted tuneState warn';return}pendingTuneMHz=Math.round(mhz*1000)/1000;ui.freq.value=fmt(pendingTuneMHz,3);ui.tuneState.textContent='ожидание подтверждения…';ui.tuneState.className='muted tuneState';clearTimeout(tuneAckTimer);send('F,'+Math.round(pendingTuneMHz*1e6));resetStats();resetPass();tuneAckTimer=setTimeout(()=>{if(pendingTuneMHz!==null){ui.tuneState.textContent='Нет подтверждения от приёмника';ui.tuneState.className='muted tuneState warn';log('! FREQ ACK TIMEOUT '+fmt(pendingTuneMHz,3)+' МГц');pendingTuneMHz=null}},1800)}")
replace_line(lines, 'function acceptTune(', "function acceptTune(mhz){pendingTuneMHz=null;clearTimeout(tuneAckTimer);showTune(mhz)}")

# Snapshot fields/version.
for i, line in enumerate(lines):
    if line.startswith('function snapshot()'):
        line = line.replace("app:'0.6.0-dev1'", "app:'0.6.1-dev1'")
        line = line.replace('center_mhz:center,span_mhz:span,', 'fixed_mhz:fixed,scan_start_mhz:bounds()[0],scan_stop_mhz:bounds()[1],')
        lines[i] = line
        break

# Parser targeted edits.
for i, line in enumerate(lines):
    if line.startswith('function parse(line)'):
        line = replace_once(line, "if(p[0]==='D'&&p.length>=10){packetRows.push(p.slice(1).join(','));renderPacketLog();return}", "if(p[0]==='D'&&p.length>=10){packetRows.push(p.slice(1).join(','));renderPacketLog();if(elrsBearing){const db=Number(p[5]);if(Number.isFinite(db))updateRssi(db)}return}", 'D parse')
        line = replace_once(line, "}else if(st==='CONFIRMED'){setProbe(true);ui.elrsResult.textContent='ELRS ПОДТВЕРЖДЁН · '+prof;ui.elrsEvidence.textContent='3 согласованных SYNC · rate/UID evidence'}else if(st==='TIMEOUT'||st==='STOPPED'||st==='ERROR'){setProbe(false);if(st==='TIMEOUT')ui.elrsResult.textContent='ELRS НЕ ПОДТВЕРЖДЁН';else if(st==='ERROR')ui.elrsResult.textContent='Ошибка Packet Probe'}return}", "}else if(st==='CONFIRMED'){elrsConfirmed=true;ui.elrsResult.textContent='ELRS ПОДТВЕРЖДЁН · '+prof;ui.elrsEvidence.textContent=elrsBearing?'пакеты → RSSI → азимут':'3 согласованных SYNC · готов ПЕЛЕНГ ELRS';if(!elrsBearing){send('Q,X');setProbe(false)}else setProbe(true)}else if(st==='TIMEOUT'||st==='STOPPED'||st==='ERROR'){const wasBearing=elrsBearing;setProbe(false);elrsBearing=false;if(st==='TIMEOUT'&&!elrsConfirmed)ui.elrsResult.textContent='ELRS НЕ ПОДТВЕРЖДЁН';else if(st==='TIMEOUT'&&wasBearing)ui.elrsEvidence.textContent='пеленг завершён · можно повторить';else if(st==='ERROR')ui.elrsResult.textContent='Ошибка Packet Probe'}return}", 'Q state parse')
        line = replace_once(line, "if(p[1]==='range'&&p.length>=4){lo=Number(p[2])/1e6;hi=Number(p[3])/1e6;ui.freq.min=lo;ui.freq.max=hi;ui.center.min=lo;ui.center.max=hi;renderWindow()}", "if(p[1]==='range'&&p.length>=4){lo=Number(p[2])/1e6;hi=Number(p[3])/1e6;ui.receiverRange.textContent='заявлено приёмником: '+fmt(lo,3)+'–'+fmt(hi,3)+' МГц · вне диапазона можно ввести экспериментально';renderWindow()}", 'range parse')
        line = replace_once(line, "if(p[0]==='A'){if(p[1]==='F'&&p[2])acceptTune(Number(p[2])/1e6);", "if(p[0]==='E'){if(p[1]==='FREQ_RANGE'){pendingTuneMHz=null;clearTimeout(tuneAckTimer);ui.tuneState.textContent='Приёмник отклонил частоту · заявлено '+fmt(lo,3)+'–'+fmt(hi,3)+' МГц';ui.tuneState.className='muted tuneState warn'}else if(p[1]==='SWEEP_ARGS'){ui.scanState.textContent='диапазон отклонён firmware';ui.scanState.className='muted warn';scanOn=false;ui.scan.classList.remove('stop');ui.scan.textContent='▶ СКАНИРОВАТЬ'}return}if(p[0]==='A'){if(p[1]==='F'&&p[2])acceptTune(Number(p[2])/1e6);", 'generic errors')
        lines[i] = line
        break
else:
    raise RuntimeError('parse line missing')

replace_line(lines, "ui.usb.onclick=", "ui.usb.onclick=()=>native&&AndroidSerial.connect();$('newPass').onclick=resetPass;ui.freq.onchange=e=>requestTune(e.target.value);ui.freq.onkeydown=e=>{if(e.key==='Enter'){requestTune(e.target.value);e.target.blur()}};$('freqMinus').onclick=()=>requestTune((pendingTuneMHz ?? (Number(ui.freq.value)||fixed))-.1);$('freqPlus').onclick=()=>requestTune((pendingTuneMHz ?? (Number(ui.freq.value)||fixed))+.1);")
replace_line(lines, 'ui.center.onchange=', "const applyManualRange=()=>setScanRange(ui.start.value,ui.stop.value);ui.start.onchange=applyManualRange;ui.stop.onchange=applyManualRange;ui.start.onkeydown=ui.stop.onkeydown=e=>{if(e.key==='Enter'){applyManualRange();e.target.blur()}};document.querySelectorAll('[data-span]').forEach(b=>b.onclick=()=>{const sp=Number(b.dataset.span),c=Number(ui.freq.value)||fixed;setScanRange(c-sp/2,c+sp/2);document.querySelectorAll('[data-span]').forEach(x=>x.classList.toggle('active',x===b))});ui.scan.onclick=()=>scanOn?stopScan():startScan();ui.elrs.onclick=()=>probeOn?stopElrs():elrsConfirmed?startElrsBearing():startElrs();ui.go.onclick=()=>{if(!Number.isFinite(markerMHz))return;if(scanOn)stopScan();requestTune(markerMHz);document.querySelector('[data-view=\"bearing\"]').click()};ui.spectrum.onpointerup=e=>{const r=ui.spectrum.getBoundingClientRect(),[a,b]=bounds(),want=a+clamp((e.clientX-r.left)/r.width,0,1)*(b-a);let best=null,dist=Infinity;for(const[hz,db]of currentSweep){const f=hz/1e6,d=Math.abs(f-want);if(d<dist){dist=d;best=[f,db]}}chooseMarker(best?best[0]:want,best?best[1]:null)};")
for i, line in enumerate(lines):
    if line.startswith("window.addEventListener('resize'"):
        lines[i] = line.replace("applyProfile('normal');renderWindow();", "applyProfile('normal');showTune(fixed);renderWindow();")
        break

for i, line in enumerate(lines):
    if 'FPV Club RF Finder v0.6.0-dev1' in line:
        lines[i] = line.replace('FPV Club RF Finder v0.6.0-dev1 · RX-only · ELRS Packet Probe', 'FPV Club RF Finder v0.6.1-dev1 · RX-only · unified tuning + ELRS bearing')

s = '\n'.join(lines) + '\n'
p.write_text(s, encoding='utf-8')

# Android version
p = Path('rf_finder/android/app/build.gradle')
s = p.read_text(encoding='utf-8')
s = replace_once(s, 'versionCode 8', 'versionCode 9', 'versionCode')
s = replace_once(s, "versionName '0.6.0-dev1'", "versionName '0.6.1-dev1'", 'versionName')
p.write_text(s, encoding='utf-8')

# Firmware: keep scanning ELRS grid after confirmation so D packet RSSI can feed bearing.
p = Path('rf_finder/firmware/src/main.cpp')
s = p.read_text(encoding='utf-8')
s = replace_once(s, 'static constexpr char FW_VERSION[] = "0.6.0-dev1";', 'static constexpr char FW_VERSION[] = "0.6.1-dev1";', 'firmware version')
s = replace_once(s, 'if (!probe.confirmed && (uint32_t)(now - probe.slotStartedMs) >= 12UL) {\n        probe.channel = (uint8_t)((probe.channel + 1) % 80);\n        if (probe.channel == 0) probe.profile = (probe.profile + 1) % PROBE_PROFILE_COUNT;', 'if ((uint32_t)(now - probe.slotStartedMs) >= 12UL) {\n        probe.channel = (uint8_t)((probe.channel + 1) % 80);\n        if (probe.channel == 0 && !probe.confirmed) probe.profile = (probe.profile + 1) % PROBE_PROFILE_COUNT;', 'ELRS tracking loop')
p.write_text(s, encoding='utf-8')

print('v0.6.1-dev1 patch applied')
