export class AutoRouteSelector {
  constructor({ lan = null, internet = null } = {}) {
    this.lan = lan;
    this.internet = internet;
  }

  snapshot() {
    return {
      lan: this.lan?.snapshot?.() || { ready: false },
      internet: this.internet?.snapshot?.() || { ready: false },
    };
  }

  select() {
    if (this.lan?.isReady?.()) {
      return { id: 'wifi', label: 'Напрямую', transport: this.lan, reason: 'local-direct' };
    }
    if (this.internet?.isReady?.()) {
      return { id: 'ip', label: 'Интернет', transport: this.internet, reason: 'internet-relay' };
    }
    return { id: null, label: 'Нет маршрута', transport: null, reason: 'offline' };
  }

  async send(envelope, options = {}) {
    const route = this.select();
    if (!route.transport) return { ...route, queued: true };
    const result = await route.transport.send(envelope, options);
    return { ...route, ...result };
  }
}
