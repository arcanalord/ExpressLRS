import assert from 'node:assert/strict';
import { createNavigationController } from '../src/navigation-controller.js';
import { runAppBootstrap } from '../src/app-bootstrap.js';

class FakeClassList {
  constructor(initial=[]){this.values=new Set(initial);}
  toggle(name,force){if(force===undefined){if(this.values.has(name))this.values.delete(name);else this.values.add(name);}else if(force)this.values.add(name);else this.values.delete(name);}
  contains(name){return this.values.has(name);}
}
class FakeElement {
  constructor({screen='',view='',classes=[]}={}){this.dataset={screen,view};this.classList=new FakeClassList(classes);this.handlers={};}
  addEventListener(name,fn){this.handlers[name]=fn;}
  click(){this.handlers.click?.({currentTarget:this,target:this});}
}
const views=['chats','map','network','settings'].map((screen,i)=>new FakeElement({screen,classes:i===0?['is-active']:[]}));
const navs=['chats','map','network','settings'].map((view,i)=>new FakeElement({view,classes:i===0?['is-active']:[]}));
const openNetwork=new FakeElement();
const documentRef={
  querySelectorAll(selector){
    if(selector==='.view')return views;
    if(selector==='[data-nav] [data-view]')return navs;
    if(selector==='[data-open-network]')return [openNetwork];
    return [];
  }
};
let mapCalls=0,networkCalls=0,scrollCalls=0;
const controller=createNavigationController({
  documentRef,
  windowRef:{scrollTo(){scrollCalls++;}},
  onMap(){mapCalls++;},
  onNetwork(){networkCalls++;},
});
controller.wire();
navs[1].click();
assert.equal(controller.current(),'map');
assert.equal(mapCalls,1);
assert.equal(views[1].classList.contains('is-active'),true);
assert.equal(navs[1].classList.contains('is-active'),true);
openNetwork.click();
assert.equal(controller.current(),'network');
assert.equal(networkCalls,1);
assert.equal(scrollCalls,2);
controller.wire();
navs[3].click();
assert.equal(controller.current(),'settings');
assert.equal(scrollCalls,3,'wire() must be idempotent');

const order=[];
runAppBootstrap({
  initTheme:()=>order.push('theme'),
  bindRadioState:()=>order.push('radio'),
  renderInitial:()=>order.push('render'),
  restoreEngineeringUi:()=>order.push('engineering'),
  wireNavigation:()=>order.push('navigation'),
  wireEvents:()=>order.push('events'),
  openInitialHelp:()=>order.push('help'),
  consumePendingDeepLink:()=>order.push('deeplink'),
  autoConnect:()=>order.push('connect'),
  installDebug:()=>order.push('debug'),
  registerServiceWorker:()=>order.push('service-worker'),
});
assert.deepEqual(order,['theme','radio','render','engineering','navigation','events','help','deeplink','connect','debug','service-worker']);
console.log('NAVIGATION_BOOTSTRAP_PASS');
