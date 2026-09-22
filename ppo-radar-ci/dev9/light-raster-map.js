const MAX_LAT = 85.05112878;
const clamp=(v,min,max)=>Math.min(max,Math.max(min,Number(v)));
const lonX=(lon)=>(Number(lon)+180)/360;
const latY=(lat)=>{
  const r=clamp(lat,-MAX_LAT,MAX_LAT)*Math.PI/180;
  return (1-Math.asinh(Math.tan(r))/Math.PI)/2;
};
export function tileRangeForBounds(bounds,z){
  const n=2**z;
  const x0=Math.floor(lonX(bounds.west)*n);
  const x1=Math.floor(lonX(bounds.east)*n);
  const y0=Math.floor(latY(bounds.north)*n);
  const y1=Math.floor(latY(bounds.south)*n);
  return {x0,x1,y0,y1,n};
}
export function chooseRasterZoom(bounds,width,height,{minZoom=5,maxZoom=15}={}){
  const dx=Math.max(1e-9,lonX(bounds.east)-lonX(bounds.west));
  const dy=Math.max(1e-9,latY(bounds.south)-latY(bounds.north));
  const zx=Math.log2(Math.max(1,Number(width))/(256*dx));
  const zy=Math.log2(Math.max(1,Number(height))/(256*dy));
  return Math.max(minZoom,Math.min(maxZoom,Math.floor(Math.min(zx,zy))));
}
export function createLightRasterBackdrop({
  container,
  bounds,
  tileUrl='https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution='© OpenStreetMap contributors',
  onState=null
}={}){
  if(!container) throw new Error('Light raster container is required');
  const layer=document.createElement('div');
  layer.className='light-raster-map';
  layer.setAttribute('aria-hidden','true');
  const credit=document.createElement('div');
  credit.className='light-raster-attribution';
  credit.textContent=attribution;
  layer.append(credit);
  container.prepend(layer);
  let generation=0;
  let active=true;
  const emit=(state,detail={})=>{try{onState?.({state,...detail});}catch{}};

  function render(){
    if(!active) return false;
    const width=Math.max(1,container.clientWidth);
    const height=Math.max(1,container.clientHeight);
    const z=chooseRasterZoom(bounds,width,height);
    const {x0,x1,y0,y1,n}=tileRangeForBounds(bounds,z);
    [...layer.querySelectorAll('img')].forEach(n=>n.remove());
    const west=lonX(bounds.west), east=lonX(bounds.east);
    const north=latY(bounds.north), south=latY(bounds.south);
    const spanX=Math.max(1e-9,east-west), spanY=Math.max(1e-9,south-north);
    const token=++generation;
    let loaded=0,failed=0,total=0;
    emit('LOADING',{z});
    for(let y=y0;y<=y1;y++) for(let x=x0;x<=x1;x++){
      const wrapped=((x%n)+n)%n;
      const left=((x/n)-west)/spanX*width;
      const right=(((x+1)/n)-west)/spanX*width;
      const top=((y/n)-north)/spanY*height;
      const bottom=(((y+1)/n)-north)/spanY*height;
      const img=document.createElement('img');
      img.alt='';
      img.decoding='async';
      img.loading='eager';
      img.referrerPolicy='origin';
      img.style.left=`${left}px`;
      img.style.top=`${top}px`;
      img.style.width=`${Math.max(1,right-left)+0.5}px`;
      img.style.height=`${Math.max(1,bottom-top)+0.5}px`;
      img.addEventListener('load',()=>{if(token!==generation)return;loaded++; if(loaded===1) emit('ONLINE',{z,loaded,failed,total});},{once:true});
      img.addEventListener('error',()=>{if(token!==generation)return;failed++;img.remove(); if(failed>=total&&loaded===0) emit('ERROR',{z,loaded,failed,total});},{once:true});
      img.src=tileUrl.replace('{z}',String(z)).replace('{x}',String(wrapped)).replace('{y}',String(y));
      layer.insertBefore(img,credit);
      total++;
    }
    setTimeout(()=>{if(token===generation&&loaded===0)emit('DEGRADED',{z,loaded,failed,total});},4500);
    return true;
  }
  return {
    mount(){active=true;layer.hidden=false;render();return true;},
    resize(){return render();},
    hide(){layer.hidden=true;},
    show(){layer.hidden=false;},
    destroy(){active=false;generation++;layer.remove();},
    describe(){return {provider:'LIGHT_RASTER_OSM',attribution};}
  };
}
