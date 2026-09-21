export function createNavigationController({
  documentRef=globalThis.document,
  windowRef=globalThis.window,
  initialView='chats',
  onNetwork=()=>{},
  onMap=()=>{},
}={}){
  let currentView=initialView;
  let wired=false;
  const all=(selector)=>[...(documentRef?.querySelectorAll?.(selector)||[])];

  function current(){return currentView;}

  function setView(name){
    currentView=name;
    all('.view').forEach(view=>view.classList.toggle('is-active',view.dataset.screen===name));
    all('[data-nav] [data-view]').forEach(button=>button.classList.toggle('is-active',button.dataset.view===name));
    try{windowRef?.scrollTo?.({top:0,behavior:'instant'});}catch{}
    if(name==='network')onNetwork();
    if(name==='map')onMap();
    return currentView;
  }

  function wire(){
    if(wired)return;
    wired=true;
    all('[data-nav] [data-view]').forEach(button=>button.addEventListener('click',()=>setView(button.dataset.view)));
    all('[data-open-network]').forEach(button=>button.addEventListener('click',()=>setView('network')));
  }

  return Object.freeze({current,setView,wire});
}
