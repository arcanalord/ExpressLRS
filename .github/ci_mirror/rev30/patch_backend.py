from pathlib import Path
import json,re,math,sys
root=Path(sys.argv[1]).resolve()
static=root/'apps/linux_web/static'

# version
(root/'VERSION').write_text('0.1.0-alpha.20-rev30\n',encoding='utf-8')

# seeds
seeds=root/'apps/shared/product/seeds'; seeds.mkdir(parents=True,exist_ok=True)
def wire(i,x,l,seg=21):
    return {'id':i,'start_m':[x,0.0,-l/2],'end_m':[x,0.0,l/2],'radius_m':0.001,'segments':seg}
def yagi_seed(n):
    ls=[0.52,0.48]+[0.45-0.01*i for i in range(n-2)]
    xs=[0.0,0.20]+[0.35+0.15*i for i in range(n-2)]
    wires=[wire('REF',xs[0],ls[0]),wire('DRV',xs[1],ls[1])]+[wire(f'DIR{i+1}',xs[i+2],ls[i+2]) for i in range(n-2)]
    return {'schema_version':'0.5','name':f'{n}-element Yagi template seed','frequency_hz':299792458.0,'wires':wires,'feeds':[{'wire_id':'DRV','segment':10,'voltage_re_v':1.0,'voltage_im_v':0.0}]}
for n in (5,7):
    (seeds/f'yagi_{n}el_seed.emnx').write_text(json.dumps(yagi_seed(n),ensure_ascii=False,indent=2),encoding='utf-8')
mox={'schema_version':'0.5','name':'Moxon experimental template seed','frequency_hz':299792458.0,
'wires':[
 {'id':'DRV','start_m':[0,0,-0.18],'end_m':[0,0,0.18],'radius_m':0.001,'segments':21},
 {'id':'DTOP','start_m':[0,0,0.18],'end_m':[0.055,0,0.18],'radius_m':0.001,'segments':7},
 {'id':'DBOT','start_m':[0,0,-0.18],'end_m':[0.055,0,-0.18],'radius_m':0.001,'segments':7},
 {'id':'REF','start_m':[0.14,0,-0.18],'end_m':[0.14,0,0.18],'radius_m':0.001,'segments':21},
 {'id':'RTOP','start_m':[0.14,0,0.18],'end_m':[0.085,0,0.18],'radius_m':0.001,'segments':7},
 {'id':'RBOT','start_m':[0.14,0,-0.18],'end_m':[0.085,0,-0.18],'radius_m':0.001,'segments':7}],
'feeds':[{'wire_id':'DRV','segment':10,'voltage_re_v':1.0,'voltage_im_v':0.0}]}
(seeds/'moxon_seed.emnx').write_text(json.dumps(mox,ensure_ascii=False,indent=2),encoding='utf-8')

# registry
def p(id,label,unit,default_lambda=None,default=None,min_lambda=None,max_lambda=None,min=None,max=None,step=None,binding=None,help=None):
    x={'id':id,'label':label,'ui_unit':unit}
    for k,v in [('default_lambda',default_lambda),('default',default),('min_lambda',min_lambda),('max_lambda',max_lambda),('min',min),('max',max),('step',step)]:
        if v is not None:x[k]=v
    if binding:x['binding']=binding
    if help:x['help']=help
    return x
common_diam=p('diameter_m','Диаметр провода','mm',default_lambda=.002,min_lambda=.0002,max_lambda=.02,step=.1,binding={'kind':'wire_diameter_all'})
common_seg=p('segments','Сегментов','count',default=21,min=3,max=101,step=2,binding={'kind':'wire_segments_all'})
registry={'schema_version':'0.2','product':'EMMana-Next','synthesis_method':'frequency-scale-seed-v1','parameter_ui':'registry-driven-v1','note':'Template parameters are external UI metadata; generated project remains pure EMNX.', 'templates':[]}
def add(x): registry['templates'].append(x)
add({'id':'halfwave-dipole','label':'Полуволновый диполь','status':'implemented','seed_model':'benchmarks/B01_halfwave_dipole_51seg.emnx','family':'dipole','solver_compatibility':['wire-mom'],'trust':'reference-validated','supports_optimizer':False,'parameters':[
 p('element_length_m','Общая длина','cm',default_lambda=.50,min_lambda=.30,max_lambda=.70,step=.1,binding={'kind':'wire_length','wire_id':'W1'}),common_diam,p('segments','Сегментов','count',default=51,min=5,max=151,step=2,binding={'kind':'wire_segments_all'})], 'outputs':['emnx-project'],'use_cases':['baseline','single-band wire antenna']})
add({'id':'quarterwave-monopole-pec','label':'GP 1/4 λ над PEC','status':'implemented','seed_model':'benchmarks/B02_quarterwave_monopole_over_pec.emnx','family':'monopole','solver_compatibility':['wire-mom'],'trust':'characterized','supports_optimizer':False,'parameters':[
 p('radiator_length_m','Длина вертикала','cm',default_lambda=.25,min_lambda=.15,max_lambda=.40,step=.1,binding={'kind':'wire_length_from_start','wire_id':'MONO'}),common_diam,p('segments','Сегментов','count',default=25,min=5,max=101,step=2,binding={'kind':'wire_segments_all'})], 'outputs':['emnx-project'],'use_cases':['ground-plane antenna','PEC reference']})

def yagi_params(n):
    arr=[p('reflector_length_m','Рефлектор','cm',default_lambda=.52,min_lambda=.42,max_lambda=.62,step=.1,binding={'kind':'wire_length','wire_id':'REF'}),
         p('driven_length_m','Активный элемент','cm',default_lambda=.48,min_lambda=.38,max_lambda=.58,step=.1,binding={'kind':'wire_length','wire_id':'DRV'}),
         p('director1_length_m','Первый директор','cm',default_lambda=.45,min_lambda=.34,max_lambda=.54,step=.1,binding={'kind':'wire_length','wire_id':'DIR1'}),
         p('reflector_driven_gap_m','REF → DRV','cm',default_lambda=.20,min_lambda=.07,max_lambda=.35,step=.1,binding={'kind':'center_gap_x','wire_a':'REF','wire_b':'DRV'}),
         p('driven_director_gap_m','DRV → DIR1','cm',default_lambda=.15,min_lambda=.06,max_lambda=.30,step=.1,binding={'kind':'center_gap_x','wire_a':'DRV','wire_b':'DIR1'})]
    if n>3:
        arr += [p('director_spacing_m','Шаг директоров','cm',default_lambda=.15,min_lambda=.06,max_lambda=.30,step=.1,binding={'kind':'yagi_director_spacing'}),
                p('director_step_m','Укорочение директора','mm',default_lambda=.01,min_lambda=0,max_lambda=.04,step=.1,binding={'kind':'yagi_director_step'})]
    arr += [common_diam,common_seg]
    return arr
add({'id':'yagi-3el','label':'Яги, 3 элемента','status':'implemented','seed_model':'benchmarks/B04_three_element_yagi_parametric.emnx','family':'yagi','element_count':3,'solver_compatibility':['wire-mom'],'trust':'characterized','supports_optimizer':True,'parameters':yagi_params(3),'outputs':['emnx-project'],'use_cases':['directional antenna','optimizer seed']})
add({'id':'yagi-5el','label':'Яги, 5 элементов','status':'implemented','seed_model':'apps/shared/product/seeds/yagi_5el_seed.emnx','family':'yagi','element_count':5,'solver_compatibility':['wire-mom'],'trust':'experimental','supports_optimizer':True,'parameters':yagi_params(5),'outputs':['emnx-project'],'use_cases':['directional antenna','optimizer seed','experimental template']})
add({'id':'yagi-7el','label':'Яги, 7 элементов','status':'implemented','seed_model':'apps/shared/product/seeds/yagi_7el_seed.emnx','family':'yagi','element_count':7,'solver_compatibility':['wire-mom'],'trust':'experimental','supports_optimizer':True,'parameters':yagi_params(7),'outputs':['emnx-project'],'use_cases':['directional antenna','optimizer seed','experimental template']})
add({'id':'square-loop','label':'Квадратная полноразмерная рамка','status':'implemented','seed_model':'benchmarks/T04_square_fullwave_loop.emnx','family':'square-loop','solver_compatibility':['wire-mom'],'trust':'experimental','supports_optimizer':False,'parameters':[
 p('side_m','Сторона рамки','cm',default_lambda=.25,min_lambda=.12,max_lambda=.40,step=.1,binding={'kind':'square_side'}),common_diam,p('segments','Сегментов на сторону','count',default=11,min=3,max=51,step=2,binding={'kind':'wire_segments_all'})], 'outputs':['emnx-project'],'use_cases':['single-band loop antenna','geometry-editor starter']})
add({'id':'moxon','label':'Moxon rectangle','status':'implemented','seed_model':'apps/shared/product/seeds/moxon_seed.emnx','family':'moxon','solver_compatibility':['wire-mom'],'trust':'experimental','supports_optimizer':False,'parameters':[
 p('span_m','Высота элемента','cm',default_lambda=.36,min_lambda=.22,max_lambda=.55,step=.1,binding={'kind':'moxon_span'}),
 p('spacing_m','Расстояние DRV → REF','cm',default_lambda=.14,min_lambda=.07,max_lambda=.28,step=.1,binding={'kind':'moxon_spacing'}),
 p('end_gap_m','Зазор концов','cm',default_lambda=.03,min_lambda=.005,max_lambda=.12,step=.1,binding={'kind':'moxon_end_gap'}),common_diam,common_seg], 'outputs':['emnx-project'],'use_cases':['compact directional antenna','experimental geometry starter']})
for tid,label in [('lpda','Логопериодическая антенна'),('helix','Спиральная антенна')]: add({'id':tid,'label':label,'status':'planned','solver_compatibility':['wire-mom'],'trust':'experimental'})
add({'id':'patch','label':'Microstrip patch','status':'unsupported-current-solver','solver_compatibility':['surface/full-wave backend required'],'trust':'experimental'})
(root/'apps/shared/product/template-registry.json').write_text(json.dumps(registry,ensure_ascii=False,indent=2),encoding='utf-8')

# server backend
sp=root/'apps/linux_web/server.py'; s=sp.read_text(encoding='utf-8')
start=s.index('def scale_xyz(v, scale: float):')
end=s.index('\n\nclass Handler',start)
backend=r'''def scale_xyz(v, scale: float):
    return [float(x) * scale for x in v]

def wire_length(w):
    a,b=w["start_m"],w["end_m"]
    return math.sqrt(sum((float(b[i])-float(a[i]))**2 for i in range(3)))

def set_wire_length(w, length: float, anchor="center"):
    a=[float(x) for x in w["start_m"]]; b=[float(x) for x in w["end_m"]]
    dx=[b[i]-a[i] for i in range(3)]; old=math.sqrt(sum(x*x for x in dx))
    if old <= 0 or length <= 0: raise ValueError("wire length must be positive")
    u=[x/old for x in dx]
    if anchor=="start": w["end_m"]=[a[i]+u[i]*length for i in range(3)]; return
    c=[(a[i]+b[i])/2 for i in range(3)]; h=length/2
    w["start_m"]=[c[i]-u[i]*h for i in range(3)]; w["end_m"]=[c[i]+u[i]*h for i in range(3)]

def wire_center_x(w): return (float(w["start_m"][0])+float(w["end_m"][0]))/2

def set_wire_center_x(w, x):
    dx=float(x)-wire_center_x(w); w["start_m"][0]+=dx; w["end_m"][0]+=dx

def odd_segments(value):
    n=max(3,int(round(value))); return n if n%2 else n+1

def parameter_default(spec: dict, wavelength: float):
    if "default_lambda" in spec: return float(spec["default_lambda"])*wavelength
    return float(spec.get("default",0))

def parameter_bounds(spec: dict, wavelength: float):
    lo=float(spec["min_lambda"])*wavelength if "min_lambda" in spec else spec.get("min")
    hi=float(spec["max_lambda"])*wavelength if "max_lambda" in spec else spec.get("max")
    return (None if lo is None else float(lo),None if hi is None else float(hi))

def resolve_template_parameters(item: dict, target_frequency_hz: float, raw: dict) -> dict:
    wavelength=299792458.0/target_frequency_hz; out={}
    for spec in item.get("parameters",[]):
        name=spec["id"]; val=float(raw.get(name,parameter_default(spec,wavelength)))
        lo,hi=parameter_bounds(spec,wavelength)
        if lo is not None and val < lo-1e-12: raise ValueError(f"{name} below minimum")
        if hi is not None and val > hi+1e-12: raise ValueError(f"{name} above maximum")
        if spec.get("ui_unit")=="count": val=odd_segments(val)
        out[name]=val
    return out

def apply_template_binding(project: dict, binding: dict, value: float):
    wires={w["id"]:w for w in project.get("wires",[])}; kind=binding.get("kind")
    if kind=="wire_length": set_wire_length(wires[binding["wire_id"]],value); return
    if kind=="wire_length_from_start": set_wire_length(wires[binding["wire_id"]],value,"start"); return
    if kind=="wire_diameter_all":
        for w in wires.values(): w["radius_m"]=value/2
        return
    if kind=="wire_segments_all":
        n=odd_segments(value)
        for w in wires.values(): w["segments"]=n
        for feed in project.get("feeds",[]):
            if feed.get("mode","center") not in {"ground-terminal-start","ground-terminal-end"}: feed["segment"]=(n-1)//2
        return
    if kind=="center_gap_x": set_wire_center_x(wires[binding["wire_b"]],wire_center_x(wires[binding["wire_a"]])+value); return
    if kind=="yagi_director_spacing":
        dirs=sorted((w for k,w in wires.items() if k.startswith("DIR")),key=lambda w:int(w["id"][3:]))
        if dirs:
            x0=wire_center_x(dirs[0])
            for i,w in enumerate(dirs[1:],1): set_wire_center_x(w,x0+value*i)
        return
    if kind=="yagi_director_step":
        dirs=sorted((w for k,w in wires.items() if k.startswith("DIR")),key=lambda w:int(w["id"][3:]))
        if dirs:
            l0=wire_length(dirs[0])
            for i,w in enumerate(dirs[1:],1): set_wire_length(w,max(l0-value*i,l0*0.55))
        return
    if kind=="square_side":
        h=value/2; pts=[[-h,0,-h],[h,0,-h],[h,0,h],[-h,0,h]]
        order=["W1","W2","W3","W4"]
        for i,k in enumerate(order): wires[k]["start_m"]=pts[i]; wires[k]["end_m"]=pts[(i+1)%4]
        return
    if kind in {"moxon_span","moxon_spacing","moxon_end_gap"}:
        span=wire_length(wires["DRV"]); spacing=wire_center_x(wires["REF"])-wire_center_x(wires["DRV"])
        if kind=="moxon_span": span=value
        if kind=="moxon_spacing": spacing=value
        # current end gap from top fold endpoints
        current_gap=float(wires["RTOP"]["end_m"][0])-float(wires["DTOP"]["end_m"][0])
        gap=value if kind=="moxon_end_gap" else current_gap
        if gap<=0 or gap>=spacing: raise ValueError("Moxon end gap must be between 0 and spacing")
        z=span/2; fold=(spacing-gap)/2
        wires["DRV"]["start_m"]=[0,0,-z];wires["DRV"]["end_m"]=[0,0,z]
        wires["REF"]["start_m"]=[spacing,0,-z];wires["REF"]["end_m"]=[spacing,0,z]
        wires["DTOP"]["start_m"]=[0,0,z];wires["DTOP"]["end_m"]=[fold,0,z]
        wires["DBOT"]["start_m"]=[0,0,-z];wires["DBOT"]["end_m"]=[fold,0,-z]
        wires["RTOP"]["start_m"]=[spacing,0,z];wires["RTOP"]["end_m"]=[spacing-fold,0,z]
        wires["RBOT"]["start_m"]=[spacing,0,-z];wires["RBOT"]["end_m"]=[spacing-fold,0,-z]
        return
    raise ValueError(f"unsupported template binding: {kind}")

def refresh_yagi_design_contract(project: dict):
    wires={w["id"]:w for w in project.get("wires",[])}; ids=["REF","DRV"]+sorted([k for k in wires if k.startswith("DIR")],key=lambda x:int(x[3:]))
    variables=[]
    for wid in ids:
        l=wire_length(wires[wid]); variables.append({"id":wid.lower()+"_length","kind":"wire_length_m","wire_id":wid,"min":l*.88,"max":l*1.12})
    for wid in ids[1:]:
        x=wire_center_x(wires[wid]); variables.append({"id":wid.lower()+"_x","kind":"wire_center_x_m","wire_id":wid,"min":max(0,x*.78),"max":x*1.22+0.01})
    constraints=[]
    for a,b in zip(ids,ids[1:]):
        gap=wire_center_x(wires[b])-wire_center_x(wires[a]); constraints.append({"id":a.lower()+"_to_"+b.lower()+"_gap","kind":"min_center_x_gap_m","wire_a":a,"wire_b":b,"value":max(.005,gap*.55)})
    for a,b in zip(ids,ids[1:]):
        la,lb=wire_length(wires[a]),wire_length(wires[b]); constraints.append({"id":a.lower()+"_longer_"+b.lower(),"kind":"wire_length_order_min_delta_m","wire_a":a,"wire_b":b,"value":max(.001,(la-lb)*.25)})
    boom=max(wire_center_x(wires[k]) for k in ids)-min(wire_center_x(wires[k]) for k in ids)
    constraints.append({"id":"max_boom","kind":"max_boom_length_m","value":boom*1.25+.01})
    project["design_variables"]=variables; project["design_constraints"]=constraints

def synthesize_template(template_id: str, target_frequency_hz: float, raw_parameters: dict|None=None) -> dict:
    if not math.isfinite(target_frequency_hz) or target_frequency_hz <= 0: raise ValueError("frequency_hz must be positive")
    registry=load_json(TEMPLATE_REGISTRY); item=next((x for x in registry.get("templates",[]) if x.get("id")==template_id),None)
    if item is None: raise ValueError("unknown template")
    if item.get("status")!="implemented": raise ValueError("template is not implemented")
    project=load_json(ROOT/item["seed_model"]); seed_frequency=float(project["frequency_hz"]); scale=seed_frequency/target_frequency_hz
    for wire in project.get("wires",[]): wire["start_m"]=scale_xyz(wire["start_m"],scale);wire["end_m"]=scale_xyz(wire["end_m"],scale);wire["radius_m"]=float(wire["radius_m"])*scale
    ground=project.get("ground")
    if isinstance(ground,dict) and "plane_z_m" in ground: ground["plane_z_m"]=float(ground["plane_z_m"])*scale
    for feed in project.get("feeds",[]):
        if "source_span_m" in feed: feed["source_span_m"]=float(feed["source_span_m"])*scale
    params=resolve_template_parameters(item,target_frequency_hz,raw_parameters or {})
    for spec in item.get("parameters",[]): apply_template_binding(project,spec["binding"],params[spec["id"]])
    if item.get("family")=="yagi": refresh_yagi_design_contract(project)
    else: project.pop("design_variables",None); project.pop("design_constraints",None)
    project["schema_version"]="0.5"; project["frequency_hz"]=target_frequency_hz; project["name"]=f'{item["label"]} synthesized at {target_frequency_hz/1e6:.6f} MHz'
    return {"template_id":template_id,"method":registry["synthesis_method"],"seed_model":item["seed_model"],"scale":scale,"parameters":params,"supports_optimizer":bool(item.get("supports_optimizer")),"project":project}
'''
s=s[:start]+backend+s[end:]
old='''                qs=urllib.parse.parse_qs(parsed.query)\n                frequency_hz=float(qs.get("frequency_hz",["0"])[0])\n                self.send_json(synthesize_template(template_id,frequency_hz))'''
new='''                qs=urllib.parse.parse_qs(parsed.query)\n                frequency_hz=float(qs.get("frequency_hz",["0"])[0])\n                raw={k:v[0] for k,v in qs.items() if k!="frequency_hz" and v}\n                self.send_json(synthesize_template(template_id,frequency_hz,raw))'''
assert old in s
s=s.replace(old,new,1);sp.write_text(s,encoding='utf-8')
