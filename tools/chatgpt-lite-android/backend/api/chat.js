import { streamText } from 'ai';

const DEFAULT_MODEL = 'openai/gpt-5.6-luna';
const ALLOWED_MODELS = new Set([
  'openai/gpt-5.6-luna',
  'openai/gpt-5.6-terra',
  'openai/gpt-5.6-sol',
]);

export const config = {
  maxDuration: 120,
};

export default {
  async fetch(request) {
    if (request.method === 'GET') {
      return Response.json({ ok: true, service: 'chat-lite', defaultModel: DEFAULT_MODEL });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    const expectedToken = process.env.CHAT_LITE_TOKEN?.trim();
    if (expectedToken) {
      const auth = request.headers.get('authorization') || '';
      if (auth !== `Bearer ${expectedToken}`) {
        return new Response('Unauthorized', { status: 401 });
      }
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response('Invalid JSON', { status: 400 });
    }

    const model = ALLOWED_MODELS.has(body?.model) ? body.model : DEFAULT_MODEL;
    const rawMessages = Array.isArray(body?.messages) ? body.messages : [];
    const messages = rawMessages
      .slice(-20)
      .filter(m => m && (m.role === 'user' || m.role === 'assistant'))
      .map(m => ({
        role: m.role,
        content: String(m.content || '').slice(0, 120000),
      }))
      .filter(m => m.content.length > 0);

    if (messages.length === 0) {
      return new Response('No messages', { status: 400 });
    }

    try {
      const result = streamText({
        model,
        messages,
        system: 'You are a concise, capable assistant. Reply in the language used by the user unless asked otherwise.',
        providerOptions: {
          gateway: {
            user: 'chat-lite-personal',
            tags: ['app:chat-lite', 'client:android'],
          },
        },
      });

      return result.toTextStreamResponse({
        headers: {
          'Cache-Control': 'no-store, no-transform',
          'X-Content-Type-Options': 'nosniff',
        },
      });
    } catch (error) {
      console.error('chat-lite error', error);
      return new Response('Generation failed', { status: 500 });
    }
  },
};
