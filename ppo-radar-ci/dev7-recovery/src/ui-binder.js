export const UI_BIND_LEVEL = Object.freeze({ CRITICAL:'CRITICAL', OPTIONAL:'OPTIONAL' });

export function createUiBinder({ root = globalThis.document, onIssue = () => {} } = {}) {
  const bound = new WeakMap();
  const issues = [];

  const resolve = (target) => {
    if (!target) return null;
    if (typeof target !== 'string') return target;
    if (!root?.querySelector) return null;
    return root.querySelector(target.startsWith('#') || target.startsWith('.') || target.startsWith('[') ? target : `#${target}`);
  };

  const bind = (target, eventName, handler, {
    level = UI_BIND_LEVEL.OPTIONAL,
    key = null,
    options = undefined
  } = {}) => {
    const node = resolve(target);
    const id = typeof target === 'string' ? target : (node?.id ? `#${node.id}` : 'element');
    const bindKey = key ?? `${eventName}:${id}`;
    if (!node?.addEventListener) {
      const issue = { code:'UI_ELEMENT_MISSING', level, target:id, eventName, key:bindKey };
      issues.push(issue); onIssue(issue);
      return false;
    }
    let keys = bound.get(node);
    if (!keys) { keys = new Set(); bound.set(node, keys); }
    if (keys.has(bindKey)) return true;
    const safeHandler = (event) => {
      try { return handler?.(event); }
      catch (error) {
        const issue = { code:'UI_HANDLER_ERROR', level, target:id, eventName, key:bindKey, error:String(error?.message ?? error) };
        issues.push(issue); onIssue(issue);
        return undefined;
      }
    };
    node.addEventListener(eventName, safeHandler, options);
    keys.add(bindKey);
    return true;
  };

  return Object.freeze({
    bind,
    bindCritical:(target,eventName,handler,opts={})=>bind(target,eventName,handler,{...opts,level:UI_BIND_LEVEL.CRITICAL}),
    bindOptional:(target,eventName,handler,opts={})=>bind(target,eventName,handler,{...opts,level:UI_BIND_LEVEL.OPTIONAL}),
    issues:()=>issues.map((item)=>Object.freeze({...item}))
  });
}

export function wireCriticalUi({
  binder,
  openHelp,
  restartReplay,
  toggleReplay,
  closeHelp,
  fallbackTopicId = 'ppo-radar.quick-start',
  onIssue = () => {}
} = {}) {
  if (!binder) throw new Error('wireCriticalUi requires binder');
  const results = {
    help:binder.bindCritical('#help','click',()=>openHelp?.(fallbackTopicId),{key:'critical:help'}),
    helpClose:binder.bindCritical('#help-close','click',()=>closeHelp?.(),{key:'critical:help-close'}),
    helpBack:binder.bindCritical('#help-back','click',()=>closeHelp?.(),{key:'critical:help-back'}),
    replayRestart:binder.bindCritical('#replay-restart','click',()=>restartReplay?.(),{key:'critical:replay-restart'}),
    replayToggle:binder.bindCritical('#replay-toggle','click',()=>toggleReplay?.(),{key:'critical:replay-toggle'})
  };
  const missing = Object.entries(results).filter(([,ok])=>!ok).map(([name])=>name);
  if (missing.length) onIssue({ code:'CRITICAL_UI_INCOMPLETE', missing });
  return Object.freeze({ ...results, ready:missing.length===0, missing });
}
