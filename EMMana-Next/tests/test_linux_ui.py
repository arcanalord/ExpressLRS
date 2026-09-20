#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,socket,subprocess,sys,tempfile,time,urllib.request,urllib.error
from pathlib import Path

def free_port():
    s=socket.socket();s.bind(('127.0.0.1',0));p=s.getsockname()[1];s.close();return p

def get(url,timeout=5):
    with urllib.request.urlopen(url,timeout=timeout) as r:return r.read(),r.headers.get_content_type()
def get_json(url,timeout=5):return json.loads(get(url,timeout)[0])
def post_json(url,obj,timeout=120):
    req=urllib.request.Request(url,data=json.dumps(obj).encode(),headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r:return json.load(r)
    except urllib.error.HTTPError as e:
        body=e.read().decode('utf-8',errors='replace')
        raise RuntimeError(f'HTTP {e.code} from {url}: {body}') from e
def start_server(root,emnext,cache):
    port=free_port(); proc=subprocess.Popen([sys.executable,str(root/'apps/linux_web/server.py'),'--host','127.0.0.1','--port',str(port),'--binary',str(emnext.resolve()),'--cache-dir',str(cache.resolve())],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    base=f'http://127.0.0.1:{port}'
    for _ in range(80):
        try:
            if get_json(base+'/api/health',1).get('ok'):return proc,base
        except Exception:time.sleep(.1)
    proc.kill();out,err=proc.communicate();raise RuntimeError('server failed\n'+out+'\n'+err)
def stop(proc):
    proc.terminate()
    try:proc.wait(5)
    except subprocess.TimeoutExpired:proc.kill();proc.wait(5)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--root',required=True);ap.add_argument('--emnext',required=True);ns=ap.parse_args();root=Path(ns.root);emnext=Path(ns.emnext)
    b01=json.loads((root/'benchmarks/B01_halfwave_dipole_51seg.emnx').read_text());b02=json.loads((root/'benchmarks/B02_quarterwave_monopole_over_pec.emnx').read_text());soil=json.loads((root/'benchmarks/B02A_horizontal_dipole_over_real_ground.emnx').read_text());b08=json.loads((root/'benchmarks/B08_copper_dipole.emnx').read_text());optp=json.loads((root/'benchmarks/B04_three_element_yagi_parametric.emnx').read_text())
    with tempfile.TemporaryDirectory(prefix='emnext-ui-cache-') as td:
        cache=Path(td);proc,base=start_server(root,emnext,cache)
        try:
            html,ctype=get(base+'/');text=html.decode('utf-8');assert ctype=='text/html' and 'help-trigger' in text and 'ground-mode' in text and 'mobile-menu' in text and 'measurement-file' in text and 'measurement-compare' in text and 'measurement-chart' in text and 'variant-save' in text and 'measurement-bind' in text and 'report-generate' in text and 'report-preview' in text and 'geometry-canvas' in text and 'geometry-add' in text and 'geometry-feed' in text and 'geometry-delete' in text and 'data-view-tab="geometry"' in text
            reg=get_json(base+'/api/help-registry');assert reg['fallbackTopic']=='emmana-next.overview' and reg['errorMap']['NEC2_NOT_RUN']=='emmana-next.error.nec2-not-run' and any(t['id']=='emmana-next.measurement.compare' for t in reg['topics']) and any(t['id']=='emmana-next.workflow.report' for t in reg['topics']) and len(reg['topics'])>=12
            product=get_json(base+'/api/product-registry');assert product['layer']=='product-domain' and any(x['id']=='analysis-plan' for x in product['workflow'])
            templates=get_json(base+'/api/templates');assert any(x['id']=='halfwave-dipole' and x['status']=='implemented' for x in templates['templates'])
            materials=get_json(base+'/api/materials');assert any(x['id']=='copper' for x in materials['conductors'])
            contract=get_json(base+'/api/measurement-contract');assert contract['title']=='EMMana-Next Measurement Set v0.1'
            assert get_json(base+'/api/design-variant-contract')['title']=='EMMana-Next DesignVariant v0.1'
            assert get_json(base+'/api/measurement-set-contract')['title']=='EMMana-Next Measurement Set v0.2'
            assert get_json(base+'/api/engineering-report-contract')['title']=='EMMana-Next Engineering Report v0.1'
            touchstone_text='# MHz S RI R 50\n285 0.10 0\n300 0.20 0\n315 0.10 0\n'
            parsed=post_json(base+'/api/measurement/parse',{'format':'touchstone-s1p','source_name':'smoke.s1p','text':touchstone_text},30);assert parsed['ok'] and len(parsed['measurement']['samples'])==3 and abs(parsed['measurement']['samples'][1]['frequency_hz']-300e6)<1
            syn=get_json(base+'/api/template/halfwave-dipole?frequency_hz=150000000');assert syn['template_id']=='halfwave-dipole' and abs(syn['project']['frequency_hz']-150000000)<1e-6 and syn['project']['schema_version']=='0.5'
            syncheck=post_json(base+'/api/model-check',{'project':syn['project'],'kernel':'reduced'},30);assert syncheck['ok'] and 'MODEL OK' in syncheck['stdout']
            examples=get_json(base+'/api/examples')['examples'];names={x['file'] for x in examples};assert 'B02_quarterwave_monopole_over_pec.emnx' in names and 'B01_halfwave_dipole_51seg.emnx' in names
            trust=get_json(base+'/api/reference-status');assert trust['independent_reference']['engine']=='nec2c'
            check=post_json(base+'/api/model-check',{'project':b01,'kernel':'reduced'},30);assert check['ok'] and 'MODEL OK' in check['stdout']
            solved=post_json(base+'/api/solve',{'project':b01,'kernel':'reduced'},120);assert solved['ok'] and not solved['cache_hit'];r=solved['result'];z=r['feeds'][0]['impedance_ohm'];assert r['schema_version']=='0.6' and r['linear_residual_relative']<1e-10 and abs(z['re']-84.7543157332)<1e-6 and abs(z['im']-46.7280584134)<1e-6
            mono=post_json(base+'/api/solve',{'project':b02,'kernel':'reduced'},120)['result'];mz=mono['feeds'][0]['impedance_ohm'];assert abs(mz['re']-42.9303)<0.02 and abs(mz['im']-23.0997)<0.02 and mono['environment_model']=='pec-image-v1' and abs(mono['power_balance_relative_error'])<1e-4
            gr=post_json(base+'/api/solve',{'project':soil,'kernel':'reduced'},120)['result'];assert gr['environment_model']=='homogeneous-halfspace-image-v1' and gr['ground_dissipated_power_w']>=0 and 0<gr['efficiency']<=1
            lr=post_json(base+'/api/solve',{'project':b08,'kernel':'reduced'},120)['result'];assert lr['dissipated_power_w']>0 and 0<lr['efficiency']<1
            cached=post_json(base+'/api/solve',{'project':b01,'kernel':'reduced'},120);assert cached['cache_hit'] and cached['cache_source']=='memory'
            swreq={'project':b01,'kernel':'reduced','start_hz':285e6,'stop_hz':315e6,'points':3,'parallel_workers':2};sw=post_json(base+'/api/sweep',swreq,180);assert sw['ok'] and len(sw['sweep']['samples'])==3 and sw['sweep']['execution_workers']==2 and sw['sweep']['max_linear_residual_relative']<1e-10;cmp=post_json(base+'/api/measurement/compare',{'measurement':parsed['measurement'],'sweep':sw['sweep']},30);assert cmp['ok'] and cmp['comparison']['overlap']['points']>=1 and cmp['comparison']['summary']['delta_r_ohm']['count']>=1
            variant=post_json(base+'/api/variant/create',{'project':b01,'variant_id':'b01-smoke-v1','name':'B01 smoke variant'},30);assert variant['ok'] and variant['variant']['model_ref']['model_hash']
            bound=post_json(base+'/api/measurement/bind',{'variant':variant['variant'],'measurement':parsed['measurement'],'raw_text':touchstone_text,'measurement_id':'b01-smoke-vna','calibration':{'type':'SOL','reference_plane_note':'feed connector'},'provenance':{'instrument_or_source':'smoke fixture'}},30);assert bound['ok'] and bound['measurement_set']['variant_ref']['variant_id']=='b01-smoke-v1'
            report=post_json(base+'/api/report/generate',{'variant':variant['variant'],'measurement_set':bound['measurement_set'],'sweep':sw['sweep'],'measurement':parsed['measurement'],'comparison':cmp['comparison']},30);assert report['ok'] and 'Engineering Report' in report['report']['markdown'] and report['report']['measurement_ref']['measurement_id']=='b01-smoke-vna'
            optreq={'project':optp,'kernel':'reduced','population':4,'generations':1,'local_iterations':0,'seed':42,'algorithm':'pso','weights':{'match':50,'gain':25,'front_to_back':15,'size':10},'gain_guardrail_db':0.5,'max_vswr':2.0,'band_start_hz':0,'band_stop_hz':0,'band_points':1,'quantization_step_m':.001,'manufacturing_tolerance_m':.001,'robust_objective_samples':1,'monte_carlo_samples':2,'parallel_workers':2};opt=post_json(base+'/api/optimize',optreq,300);oo=opt['optimizer'];assert opt['ok'] and oo['schema_version']=='0.8' and oo['best']['metrics']['feasible'] and oo['pareto_front'] and oo['monte_carlo_audit']['samples']==2
            appjs,_=get(base+'/app.js');apptext=appjs.decode('utf-8');assert 'importMeasurement' in apptext and 'compareMeasurement' in apptext and 'drawMeasurementComparison' in apptext and 'escapeHtml' in apptext and 'saveVariant' in apptext and 'bindMeasurement' in apptext and 'generateReport' in apptext and 'downloadReport' in apptext and 'renderGeometry' in apptext and 'addGeometryWire' in apptext and 'deleteGeometryWire' in apptext and 'assignGeometryFeed' in apptext and 'geometryPointerMove' in apptext
            assert get_json(base+'/api/cache')['entries']>=3
        finally:stop(proc)
        proc2,base2=start_server(root,emnext,cache)
        try:
            disk=post_json(base2+'/api/solve',{'project':b01,'kernel':'reduced'},120);assert disk['cache_hit'] and disk['cache_source']=='disk'
            print('Linux UI smoke PASS:',z,'B02',mz,'help topics',len(reg['topics']),'cache',get_json(base2+'/api/cache')['entries'])
        finally:stop(proc2)
    return 0
if __name__=='__main__':raise SystemExit(main())
