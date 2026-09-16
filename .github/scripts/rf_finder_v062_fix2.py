from pathlib import Path

# Firmware: repair generated C++ string literals and keep TRACK UI quiet while hopping.
p=Path('rf_finder/firmware/src/main.cpp')
s=p.read_text(encoding='utf-8')
rep={
'Serial.printf("Q,STATE,TRACK,%s,%lu\n",':'Serial.printf("Q,STATE,TRACK,%s,%lu\\n",',
'Serial.printf("I,diag,irq_read_fail,%lu\n",':'Serial.printf("I,diag,irq_read_fail,%lu\\n",',
'Serial.printf("I,diag,irq_spurious,%lu\n",':'Serial.printf("I,diag,irq_spurious,%lu\\n",',
'Serial.printf("I,diag,source_reject,%lu\n",':'Serial.printf("I,diag,source_reject,%lu\\n",',
'Serial.printf("I,range,%lu,%lu\n", VERIFIED_MIN_FREQ_HZ, VERIFIED_MAX_FREQ_HZ);':'Serial.printf("I,range,%lu,%lu\\n", VERIFIED_MIN_FREQ_HZ, VERIFIED_MAX_FREQ_HZ);',
'Serial.printf("I,cap,experimental_range,%lu,%lu\n", EXPERIMENTAL_MIN_FREQ_HZ, EXPERIMENTAL_MAX_FREQ_HZ);':'Serial.printf("I,cap,experimental_range,%lu,%lu\\n", EXPERIMENTAL_MIN_FREQ_HZ, EXPERIMENTAL_MAX_FREQ_HZ);',
'Serial.printf("A,F,%lu,%s\n", fixedFreqHz, isVerifiedFrequency(fixedFreqHz) ? "VERIFIED" : "EXPERIMENTAL");':'Serial.printf("A,F,%lu,%s\\n", fixedFreqHz, isVerifiedFrequency(fixedFreqHz) ? "VERIFIED" : "EXPERIMENTAL");',
}
for old,new in rep.items():
    if old not in s:
        raise SystemExit('missing broken literal anchor: '+repr(old))
    s=s.replace(old,new,1)
old='''    probe.slotStartedMs = millis();
    Serial.printf("Q,STATE,SEARCH,%s,%lu\\n", pr.name, probe.activeProbeFreqHz);
    return true;'''
new='''    probe.slotStartedMs = millis();
    if (!probe.trackOnly) Serial.printf("Q,STATE,SEARCH,%s,%lu\\n", pr.name, probe.activeProbeFreqHz);
    return true;'''
if old not in s: raise SystemExit('probe slot UI anchor missing')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')

# Android UI: map firmware millis onto Android monotonic clock using the
# minimum observed transport offset. This removes most UART/queue lag from
# angle association without requiring clock sync messages.
p=Path('rf_finder/android/app/src/main/assets/index.html')
s=p.read_text(encoding='utf-8')
old="let lo=2400,hi=2480,expLo=2400,expHi=2500,fixed=2440,scanStart=2400,scanStop=2480,heading=null,compassAccuracy='UNRELIABLE',smoothing='normal',ema=null,peakHold=true,bestHeading=null,bestDb=-Infinity,bearingSamples=[],pendingTuneMHz=null,tuneAckTimer=null,headingHistory=[],rotationRateDps=0,passBins=Array.from({length:72},()=>[]);"
new="let lo=2400,hi=2480,expLo=2400,expHi=2500,fixed=2440,scanStart=2400,scanStop=2480,heading=null,compassAccuracy='UNRELIABLE',smoothing='normal',ema=null,peakHold=true,bestHeading=null,bestDb=-Infinity,bearingSamples=[],pendingTuneMHz=null,tuneAckTimer=null,headingHistory=[],rotationRateDps=0,passBins=Array.from({length:72},()=>[]),fwOffsets=[];"
if old not in s: raise SystemExit('state anchor missing')
s=s.replace(old,new,1)
old="function headingAt(t){if(!Number.isFinite(t)||!headingHistory.length)return heading;let best=headingHistory[0],bd=Math.abs(best.t-t);for(const x of headingHistory){const d=Math.abs(x.t-t);if(d<bd){best=x;bd=d}else if(x.t>t&&d>bd)break}return best.h}"
new=old+"\nfunction firmwareSampleTime(fwMs,rxT){fwMs=Number(fwMs);rxT=Number(rxT);if(!Number.isFinite(fwMs)||!Number.isFinite(rxT))return rxT;const off=rxT-fwMs;fwOffsets.push(off);if(fwOffsets.length>64)fwOffsets.shift();const base=Math.min(...fwOffsets);return fwMs+base}"
if old not in s: raise SystemExit('headingAt anchor missing')
s=s.replace(old,new,1)
old="updateRssi(db,headingAt(Number(rxT)),Number(rxT));return}"
new="const sampleT=firmwareSampleTime(Number(p[3]),Number(rxT));updateRssi(db,headingAt(sampleT),sampleT);return}"
if old not in s: raise SystemExit('R timing anchor missing')
s=s.replace(old,new,1)
old="if(elrsBearing&&flags==='ELRS_UID_MATCH'){const db=Number(p[5]);if(Number.isFinite(db))updateRssi(db,headingAt(Number(rxT)),Number(rxT))}return}"
new="if(elrsBearing&&flags==='ELRS_UID_MATCH'){const db=Number(p[5]),sampleT=firmwareSampleTime(Number(p[1]),Number(rxT));if(Number.isFinite(db))updateRssi(db,headingAt(sampleT),sampleT)}return}"
if old not in s: raise SystemExit('D timing anchor missing')
s=s.replace(old,new,1)
# Make TRACK state explicit in the compact evidence field.
old="if(st==='SEARCH'){setProbe(true);ui.elrsResult.textContent='ПОИСК ELRS…';ui.elrsEvidence.textContent=prof}"
new="if(st==='TRACK'){setProbe(true);ui.elrsResult.textContent='ПЕЛЕНГ ELRS…';ui.elrsEvidence.textContent='source-lock · '+prof}else if(st==='TRACK_PACKET'){ui.elrsEvidence.textContent='source-lock · packet '+prof}else if(st==='SEARCH'){setProbe(true);ui.elrsResult.textContent='ПОИСК ELRS…';ui.elrsEvidence.textContent=prof}"
if old not in s: raise SystemExit('Q state anchor missing')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('v0.6.2 fix2 applied')
