'use strict';
(() => {
  const canvas=document.querySelector('#geometry-3d-canvas');
  if(!canvas)return;
  const ctx=canvas.getContext('2d');
  const summary=document.querySelector('#geometry-3d-summary');
  const reset=document.querySelector('#geometry-3d-reset');
  let current=null,yaw=-0.72,pitch=0.52,zoom=1,drag=null;

  const finite=v=>Number.isFinite(Number(v))?Number(v):0;
  const vec=p=>[finite(p?.[0]),finite(p?.[1]),finite(p?.[2])];

  function bounds(project){
    const pts=[];
    for(const w of project?.wires||[]){pts.push(vec(w.start_m),vec(w.end_m))}
    if(!pts.length)pts.push([-0.5,-0.5,-0.5],[0.5,0.5,0.5]);
    const min=[0,1,2].map(i=>Math.min(...pts.map(p=>p[i])));
    const max=[0,1,2].map(i=>Math.max(...pts.map(p=>p[i])));
    const center=min.map((v,i)=>(v+max[i])/2);
    const span=Math.max(...max.map((v,i)=>v-min[i]),0.001);
    return {min,max,center,span};
  }

  function fitCanvas(){
    const dpr=Math.min(window.devicePixelRatio||1,2);
    const rect=canvas.getBoundingClientRect();
    const w=Math.max(320,Math.round(rect.width*dpr));
    const h=Math.max(220,Math.round(rect.height*dpr));
    if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h}
    return {w,h,dpr};
  }

  function projector(project){
    const {w,h}=fitCanvas(),b=bounds(project),scale=Math.min(w,h)*0.34*zoom/b.span;
    const cy=Math.cos(yaw),sy=Math.sin(yaw),cp=Math.cos(pitch),sp=Math.sin(pitch);
    return {
      b,w,h,
      point(p){
        let [x,y,z]=vec(p);x-=b.center[0];y-=b.center[1];z-=b.center[2];
        const x1=cy*x-sy*y,y1=sy*x+cy*y;
        const y2=cp*y1-sp*z,z2=sp*y1+cp*z;
        const perspective=Math.max(.72,Math.min(1.28,1-y2/(b.span*8)));
        return {x:w/2+x1*scale*perspective,y:h/2-z2*scale*perspective,depth:y2};
      }
    };
  }

  function line(a,b,stroke,width=1,dash=[]){
    ctx.save();ctx.strokeStyle=stroke;ctx.lineWidth=width;ctx.setLineDash(dash);
    ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke();ctx.restore();
  }

  function label(text,p,color){
    ctx.save();ctx.fillStyle=color;ctx.font=`${Math.max(11,canvas.width/90)}px system-ui`;ctx.fillText(text,p.x+6,p.y-5);ctx.restore();
  }

  function drawGround(project,pr){
    const g=project?.ground||{};
    if((g.model||'free-space')==='free-space')return;
    const b=pr.b,s=b.span*.72,z=finite(g.plane_z_m);
    const c=[b.center[0],b.center[1],z];
    const pts=[
      [c[0]-s,c[1]-s,z],[c[0]+s,c[1]-s,z],
      [c[0]+s,c[1]+s,z],[c[0]-s,c[1]+s,z]
    ].map(pr.point);
    ctx.save();ctx.fillStyle='rgba(96,106,123,.08)';ctx.strokeStyle='#303846';ctx.lineWidth=1;
    ctx.beginPath();ctx.moveTo(pts[0].x,pts[0].y);for(let i=1;i<4;i++)ctx.lineTo(pts[i].x,pts[i].y);ctx.closePath();ctx.fill();ctx.stroke();ctx.restore();
  }

  function drawAxes(pr){
    const b=pr.b,len=b.span*.45,o=pr.point(b.center);
    const axes=[
      {name:'X',p:[b.center[0]+len,b.center[1],b.center[2]],c:'#d87878'},
      {name:'Y',p:[b.center[0],b.center[1]+len,b.center[2]],c:'#72b886'},
      {name:'Z',p:[b.center[0],b.center[1],b.center[2]+len],c:'#6f9fdf'}
    ];
    for(const a of axes){const p=pr.point(a.p);line(o,p,a.c,1.5);label(a.name,p,a.c)}
  }

  function feedPoint(project,w){
    const feed=(project?.feeds||[]).find(f=>f.wire_id===w.id);if(!feed)return null;
    const n=Math.max(1,Math.trunc(finite(w.segments)||1));
    const seg=Math.max(0,Math.min(n-1,Math.trunc(finite(feed.segment_index??feed.segment))));
    const t=(seg+.5)/n,a=vec(w.start_m),b=vec(w.end_m);
    return a.map((v,i)=>v+(b[i]-v)*t);
  }

  function render(project=current){
    if(project)current=project;
    if(!current)return;
    const pr=projector(current);
    ctx.clearRect(0,0,pr.w,pr.h);ctx.fillStyle='#0b0d11';ctx.fillRect(0,0,pr.w,pr.h);
    drawGround(current,pr);drawAxes(pr);
    const selected=document.querySelector('#geometry-wire-id')?.textContent?.trim();
    const wires=[...(current.wires||[])].map(w=>({w,a:pr.point(w.start_m),b:pr.point(w.end_m)}))
      .sort((u,v)=>(u.a.depth+u.b.depth)-(v.a.depth+v.b.depth));
    for(const item of wires){
      const active=item.w.id===selected;
      line(item.a,item.b,active?'#82b5ff':'#d8dee9',active?5:3);
      const fp=feedPoint(current,item.w);
      if(fp){const p=pr.point(fp);ctx.save();ctx.fillStyle='#63df93';ctx.beginPath();ctx.arc(p.x,p.y,7,0,Math.PI*2);ctx.fill();ctx.strokeStyle='#0b0d11';ctx.lineWidth=2;ctx.stroke();ctx.restore()}
    }
    const b=pr.b;
    summary.textContent=`${wires.length} wires · X ${(b.max[0]-b.min[0]).toFixed(3)} m · Y ${(b.max[1]-b.min[1]).toFixed(3)} m · Z ${(b.max[2]-b.min[2]).toFixed(3)} m`;
  }

  function resetView(){yaw=-0.72;pitch=0.52;zoom=1;render()}
  canvas.addEventListener('pointerdown',e=>{drag={id:e.pointerId,x:e.clientX,y:e.clientY};canvas.setPointerCapture?.(e.pointerId);canvas.classList.add('dragging');e.preventDefault()});
  canvas.addEventListener('pointermove',e=>{if(!drag||drag.id!==e.pointerId)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;drag.x=e.clientX;drag.y=e.clientY;yaw+=dx*.008;pitch=Math.max(-1.25,Math.min(1.25,pitch+dy*.008));render();e.preventDefault()});
  const stopDrag=e=>{if(!drag)return;drag=null;canvas.classList.remove('dragging');canvas.releasePointerCapture?.(e.pointerId)};
  canvas.addEventListener('pointerup',stopDrag);canvas.addEventListener('pointercancel',stopDrag);
  canvas.addEventListener('wheel',e=>{zoom=Math.max(.45,Math.min(3,zoom*Math.exp(-e.deltaY*.0012)));render();e.preventDefault()},{passive:false});
  reset?.addEventListener('click',resetView);
  document.querySelector('#geometry-canvas')?.addEventListener('pointerup',()=>requestAnimationFrame(()=>render()));
  window.addEventListener('resize',()=>render());
  window.renderGeometry3D=render;
  try{const raw=document.querySelector('#project-json')?.value;if(raw)render(JSON.parse(raw))}catch{}
})();
