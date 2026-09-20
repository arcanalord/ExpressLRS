export class HelpRegistry {
  constructor(data) {
    this.data = data;
    this.topics = new Map((data.topics || []).map(t => [t.id, t]));
    this.aliases = new Map();
    for (const topic of data.topics || []) {
      for (const alias of topic.aliases || []) this.aliases.set(String(alias).toLowerCase(), topic.id);
    }
  }
  get(topicId) { return this.topics.get(topicId) || this.topics.get(this.data.fallbackTopic); }
  resolve(value) {
    if (!value) return this.get(this.data.fallbackTopic);
    if (this.topics.has(value)) return this.topics.get(value);
    if (this.data.errorMap?.[value]) return this.get(this.data.errorMap[value]);
    const id = this.aliases.get(String(value).toLowerCase());
    return id ? this.get(id) : this.get(this.data.fallbackTopic);
  }
  list(category) { return [...this.topics.values()].filter(t => !category || t.category === category); }
  search(query) {
    const q = String(query || '').trim().toLowerCase();
    if (!q) return [];
    const score = topic => {
      const title = topic.title.toLowerCase();
      if (title === q) return 100;
      if (topic.id.toLowerCase() === q) return 95;
      if (title.includes(q)) return 80;
      if ((topic.keywords || []).some(x => String(x).toLowerCase().includes(q))) return 60;
      if ((topic.aliases || []).some(x => String(x).toLowerCase().includes(q))) return 50;
      if (topic.summary.toLowerCase().includes(q)) return 30;
      if (topic.body.toLowerCase().includes(q)) return 10;
      return 0;
    };
    return [...this.topics.values()].map(t => ({topic:t, score:score(t)})).filter(x => x.score>0)
      .sort((a,b) => b.score-a.score || a.topic.title.localeCompare(b.topic.title)).map(x => x.topic);
  }
}

export function topicFromLocation(locationLike, fallback) {
  try {
    const u = new URL(locationLike.href || String(locationLike), 'http://localhost');
    return u.searchParams.get('topic') || fallback;
  } catch (_) { return fallback; }
}
