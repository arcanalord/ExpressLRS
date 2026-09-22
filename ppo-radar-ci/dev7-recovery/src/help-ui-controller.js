function setText(node, value = '') {
  if (node) node.textContent = String(value ?? '');
}

function clear(node) {
  if (!node) return;
  if (typeof node.replaceChildren === 'function') node.replaceChildren();
  else node.textContent = '';
}

function safeCreate(documentRef, tag) {
  return documentRef?.createElement?.(tag) ?? null;
}

export function createHelpUiController({
  documentRef = globalThis.document,
  locationRef = globalThis.location,
  historyRef = globalThis.history,
  session,
  fallbackTopicId,
  resolveTopic,
  listTopics,
  searchTopics,
  buildDeepLink,
  clearDeepLink,
  elements = {},
  buildDiagnostics = () => ({}),
  onIssue = () => {}
} = {}) {
  if (!session) throw new Error('Help UI requires HelpSession');
  if (!fallbackTopicId) throw new Error('Help UI requires fallbackTopicId');
  if (typeof resolveTopic !== 'function') throw new Error('Help UI requires resolveTopic');
  if (typeof listTopics !== 'function') throw new Error('Help UI requires listTopics');
  if (typeof searchTopics !== 'function') throw new Error('Help UI requires searchTopics');

  const {
    sheet,
    quickTitle,
    quickSummary,
    quickSteps,
    why,
    topicList,
    topicContent,
    search,
    diagnosticsStatus
  } = elements;

  let activeTopicId = fallbackTopicId;
  let initialized = false;

  const replaceUrl = (searchText) => {
    try {
      if (!historyRef?.replaceState || !locationRef) return false;
      const path = `${locationRef.pathname ?? ''}${searchText ?? ''}${locationRef.hash ?? ''}`;
      historyRef.replaceState(historyRef.state ?? null, '', path || searchText || '');
      return true;
    } catch (error) {
      onIssue({ code:'HELP_URL_UPDATE_FAILED', error:String(error?.message ?? error) });
      return false;
    }
  };

  const renderTopicList = (items = listTopics()) => {
    clear(topicList);
    if (!topicList || !documentRef?.createElement) return;
    for (const item of items) {
      const button = safeCreate(documentRef, 'button');
      if (!button) continue;
      button.type = 'button';
      button.dataset.helpTopic = item.id;
      button.textContent = item.title;
      if (item.id === activeTopicId) button.classList?.add?.('active');
      button.addEventListener?.('click', () => open(item.id));
      topicList.append?.(button);
    }
  };

  const renderTopic = (ref) => {
    const topic = resolveTopic(ref);
    activeTopicId = topic.id;
    setText(quickTitle, topic.title);
    setText(quickSummary, topic.summary);
    setText(why, topic.why);

    clear(quickSteps);
    for (const step of topic.quickSteps ?? []) {
      const li = safeCreate(documentRef, 'li');
      if (!li) continue;
      li.textContent = step;
      quickSteps?.append?.(li);
    }

    clear(topicContent);
    if (topicContent && documentRef?.createElement) {
      const title = safeCreate(documentRef, 'h3');
      const body = safeCreate(documentRef, 'p');
      if (title) { title.textContent = topic.title; topicContent.append?.(title); }
      if (body) { body.textContent = topic.body; topicContent.append?.(body); }
      if ((topic.relatedTopics ?? []).length) {
        const related = safeCreate(documentRef, 'div');
        if (related) {
          related.className = 'help-related';
          for (const relatedId of topic.relatedTopics) {
            const relatedTopic = resolveTopic(relatedId);
            const button = safeCreate(documentRef, 'button');
            if (!button) continue;
            button.type = 'button';
            button.textContent = relatedTopic.title;
            button.addEventListener?.('click', () => open(relatedTopic.id));
            related.append?.(button);
          }
          topicContent.append?.(related);
        }
      }
    }

    renderTopicList(search?.value ? searchTopics(search.value) : listTopics());
    return topic;
  };

  const open = (ref = fallbackTopicId, { updateUrl = true, returnTo = null } = {}) => {
    const id = session.open(ref, { returnTo });
    const topic = renderTopic(id);
    sheet?.classList?.remove?.('hidden');
    if (updateUrl && typeof buildDeepLink === 'function') replaceUrl(buildDeepLink(topic.id, locationRef?.search ?? ''));
    return topic;
  };

  const navigate = (ref) => {
    const id = session.navigate(ref);
    const topic = renderTopic(id);
    if (typeof buildDeepLink === 'function') replaceUrl(buildDeepLink(topic.id, locationRef?.search ?? ''));
    return topic;
  };

  const close = ({ updateUrl = true } = {}) => {
    const returnTo = session.back();
    sheet?.classList?.add?.('hidden');
    if (updateUrl && typeof clearDeepLink === 'function') replaceUrl(clearDeepLink(locationRef?.search ?? ''));
    return returnTo;
  };

  const init = () => {
    if (initialized) return true;
    initialized = true;
    renderTopic(activeTopicId);
    search?.addEventListener?.('input', () => renderTopicList(searchTopics(search.value)));
    return true;
  };

  const diagnosticsText = () => {
    try { return JSON.stringify(buildDiagnostics() ?? {}, null, 2); }
    catch (error) {
      onIssue({ code:'HELP_DIAGNOSTICS_FAILED', error:String(error?.message ?? error) });
      setText(diagnosticsStatus, 'Диагностика временно недоступна.');
      return JSON.stringify({ error:'diagnostics unavailable' }, null, 2);
    }
  };

  return Object.freeze({
    init,
    open,
    navigate,
    close,
    openError:(code, options={})=>open(code, options),
    diagnosticsText,
    activeTopicId:()=>activeTopicId
  });
}
