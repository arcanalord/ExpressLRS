export function createOpenMapTilesBasicStyle({sourceUrl, attribution=''} = {}) {
  return {
    version: 8,
    sources: {
      basemap: {
        type: 'vector',
        url: sourceUrl,
        attribution,
      },
    },
    layers: [
      { id:'background', type:'background', paint:{'background-color':'#eef2f4'} },
      { id:'landcover', type:'fill', source:'basemap', 'source-layer':'landcover', paint:{'fill-color':'#dfe8dd','fill-opacity':0.72} },
      { id:'landuse', type:'fill', source:'basemap', 'source-layer':'landuse', paint:{'fill-color':'#e7e1d5','fill-opacity':0.56} },
      { id:'water', type:'fill', source:'basemap', 'source-layer':'water', paint:{'fill-color':'#a9cee5'} },
      { id:'waterway', type:'line', source:'basemap', 'source-layer':'waterway', paint:{'line-color':'#91c3e2','line-width':1.2} },
      { id:'building', type:'fill', source:'basemap', 'source-layer':'building', minzoom:12, paint:{'fill-color':'#d7d2ca','fill-outline-color':'#c0bbb4'} },
      { id:'roads-casing', type:'line', source:'basemap', 'source-layer':'transportation', minzoom:6, paint:{'line-color':'#ffffff','line-width':['interpolate',['linear'],['zoom'],6,1.1,16,5.4]} },
      { id:'roads', type:'line', source:'basemap', 'source-layer':'transportation', minzoom:6, paint:{'line-color':'#c3b9aa','line-width':['interpolate',['linear'],['zoom'],6,0.6,16,3.1]} },
      { id:'boundaries', type:'line', source:'basemap', 'source-layer':'boundary', paint:{'line-color':'#9aa5ad','line-width':0.8,'line-dasharray':[3,2]} },
    ],
  };
}
