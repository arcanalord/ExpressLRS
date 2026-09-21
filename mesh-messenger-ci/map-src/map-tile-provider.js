export function mercatorPoint(position){
  const lat=Math.max(-85.05112878,Math.min(85.05112878,Number(position.latitude))),lon=Number(position.longitude);
  const x=(lon+180)/360;
  const sin=Math.sin(lat*Math.PI/180);
  const y=0.5-Math.log((1+sin)/(1-sin))/(4*Math.PI);
  return {x,y};
}

export class OsmTileProvider {
  constructor({documentRef=globalThis.document,navigatorRef=globalThis.navigator,onState=()=>{}}={}){
    this.document=documentRef;
    this.navigator=navigatorRef;
    this.onState=onState;
    this.state='loading';
    this.generation=0;
  }
  setState(next){
    if(this.state===next)return;
    this.state=next;
    this.onState(next);
  }
  chooseZoom(minX,maxX,minY,maxY){
    const canvas=this.document?.querySelector('#mapCanvas');
    const w=Math.max(320,canvas?.clientWidth||800),h=Math.max(320,canvas?.clientHeight||680);
    const spanX=Math.max(1e-7,maxX-minX),spanY=Math.max(1e-7,maxY-minY);
    const target=Math.min((w*.8)/(spanX*256),(h*.8)/(spanY*256));
    return Math.max(2,Math.min(18,Math.floor(Math.log2(Math.max(1,target)))));
  }
  markOffline(){
    this.setState('offline');
    const layer=this.document?.querySelector('#mapTileLayer');
    const grid=this.document?.querySelector('#mapGrid');
    const attribution=this.document?.querySelector('#mapAttribution');
    if(layer)layer.hidden=true;
    if(grid)grid.hidden=false;
    if(attribution)attribution.hidden=true;
  }
  render({minX,maxX,minY,maxY,pad=10,span=80}){
    const layer=this.document?.querySelector('#mapTileLayer');
    const grid=this.document?.querySelector('#mapGrid');
    const attribution=this.document?.querySelector('#mapAttribution');
    if(!layer)return;
    const generation=++this.generation;
    layer.innerHTML='';
    if(this.navigator?.onLine===false){this.markOffline();return;}
    const z=this.chooseZoom(minX,maxX,minY,maxY),n=2**z;
    const tx0=Math.max(0,Math.floor(minX*n)-1),tx1=Math.min(n-1,Math.floor(maxX*n)+1);
    const ty0=Math.max(0,Math.floor(minY*n)-1),ty1=Math.min(n-1,Math.floor(maxY*n)+1);
    let pending=0,loaded=0,failed=0;
    this.setState('loading');
    layer.hidden=false;if(grid)grid.hidden=false;if(attribution)attribution.hidden=false;
    const settle=()=>{
      if(generation!==this.generation)return;
      if(loaded>0){
        this.setState('online');
        if(grid)grid.hidden=true;
      } else if(pending===failed){
        this.setState('fallback');
        layer.hidden=true;
        if(grid)grid.hidden=false;
        if(attribution)attribution.hidden=true;
      }
    };
    for(let ty=ty0;ty<=ty1;ty++)for(let tx=tx0;tx<=tx1;tx++){
      pending++;
      const img=this.document.createElement('img');
      img.className='map-tile';img.alt='';img.decoding='async';img.loading='eager';img.referrerPolicy='origin';
      const left=pad+(((tx/n)-minX)/(maxX-minX))*span,top=pad+(((ty/n)-minY)/(maxY-minY))*span;
      const right=pad+((((tx+1)/n)-minX)/(maxX-minX))*span,bottom=pad+((((ty+1)/n)-minY)/(maxY-minY))*span;
      img.style.left=`${left}%`;img.style.top=`${top}%`;img.style.width=`${right-left}%`;img.style.height=`${bottom-top}%`;
      img.addEventListener('load',()=>{loaded++;settle();},{once:true});
      img.addEventListener('error',()=>{failed++;img.remove();settle();},{once:true});
      img.src=`https://tile.openstreetmap.org/${z}/${tx}/${ty}.png`;
      layer.appendChild(img);
    }
    setTimeout(()=>{
      if(generation!==this.generation||loaded>0)return;
      this.setState('fallback');
      layer.hidden=true;
      if(grid)grid.hidden=false;
      if(attribution)attribution.hidden=true;
    },4500);
  }
}
