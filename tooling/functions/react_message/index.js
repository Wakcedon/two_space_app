// Appwrite function: toggle reaction (emoji) for a message
// Variant C: server-side atomic toggle using server API key (read -> compute -> update) with retries

const { Client, Databases } = require('node-appwrite');

// Helper to read full stdin (Appwrite passes payload on stdin)
const readStdin = async () => {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
};

const run = async () => {
  try {
    const raw = (await readStdin()) || '';
    let payload = {};
    if (raw) {
      try { payload = JSON.parse(raw); } catch (e) { payload = {}; }
    }
    // Appwrite sometimes wraps user payload into { "data": {...} }
    const data = payload.data || payload || {};

    const messageId = data.messageId || data.$id || data.id;
    const emoji = data.emoji;
    const userId = data.userId;

    const APPWRITE_ENDPOINT = process.env.APPWRITE_FUNCTION_ENDPOINT || process.env.APPWRITE_ENDPOINT;
    const APPWRITE_PROJECT_ID = process.env.APPWRITE_FUNCTION_PROJECT_ID || process.env.APPWRITE_PROJECT_ID || process.env.APPWRITE_PROJECT;
    const APPWRITE_API_KEY = process.env.APPWRITE_API_KEY || process.env.APPWRITE_FUNCTION_API_KEY;
    const DATABASE_ID = process.env.APPWRITE_DATABASE_ID;
    const MESSAGES_ID = process.env.APPWRITE_MESSAGES_TABLE_ID || process.env.APPWRITE_MESSAGES_COLLECTION_ID;
    const useTables = !!process.env.APPWRITE_MESSAGES_TABLE_ID;
    const seg = useTables ? 'tables' : 'collections';
    const docSeg = useTables ? 'rows' : 'documents';

    if (!APPWRITE_ENDPOINT || !APPWRITE_PROJECT_ID || !APPWRITE_API_KEY || !DATABASE_ID || !MESSAGES_ID) {
      console.error(JSON.stringify({ success: false, error: 'Missing required environment variables. NEED: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID, APPWRITE_MESSAGES_TABLE_ID/APPWRITE_MESSAGES_COLLECTION_ID' }));
      process.exit(1);
    }

    if (!messageId || !emoji || !userId) {
      console.error(JSON.stringify({ success: false, error: 'Missing required payload fields: messageId, emoji, userId' }));
      process.exit(1);
    }

    const call = async (method, path, bodyObj) => {
      const url = `${APPWRITE_ENDPOINT.replace(/\/$/, '')}/v1${path}`.replace('/v1/v1','/v1');
      const headers = { 'Content-Type': 'application/json', 'X-Appwrite-Project': APPWRITE_PROJECT_ID, 'X-Appwrite-Key': APPWRITE_API_KEY };
      const resp = await fetch(url, { method, headers, body: bodyObj ? JSON.stringify(bodyObj) : undefined });
      const text = await resp.text();
      let parsed = null;
      try { parsed = JSON.parse(text); } catch(e) { parsed = text; }
      return { status: resp.status, body: parsed };
    };

    // Retry loop to reduce race window
    const maxAttempts = 4;
    let attempt = 0;
    let lastErr = null;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        // Read current document via REST
        const g = await call('GET', `/databases/${DATABASE_ID}/${seg}/${MESSAGES_ID}/${docSeg}/${encodeURIComponent(messageId)}`);
        if (g.status < 200 || g.status >= 300) throw new Error('message not found');
        const messageDoc = g.body;

        // Pull existing reactions map (emoji -> array of userIds)
        const existing = (messageDoc && messageDoc.reactions) ? messageDoc.reactions : {};
        const newReactions = JSON.parse(JSON.stringify(existing || {}));
        const arr = Array.isArray(newReactions[emoji]) ? newReactions[emoji] : [];

        const idx = arr.indexOf(userId);
        if (idx === -1) arr.push(userId); else arr.splice(idx, 1);
        if (arr.length === 0) delete newReactions[emoji]; else newReactions[emoji] = arr;

        // Patch update
        const upd = await call('PATCH', `/databases/${DATABASE_ID}/${seg}/${MESSAGES_ID}/${docSeg}/${encodeURIComponent(messageId)}`, { data: { reactions: newReactions } });
        if (upd.status < 200 || upd.status >= 300) throw new Error('update failed');

        console.log(JSON.stringify({ success: true, messageId: messageId, reactions: newReactions, document: upd.body }));
        process.exit(0);
      } catch (err) {
        lastErr = err;
        attempt < maxAttempts ? await new Promise(r => setTimeout(r, 200 * attempt)) : null;
      }
    }

    console.error(JSON.stringify({ success: false, error: 'Failed to toggle reaction after retries', details: lastErr && lastErr.message ? lastErr.message : lastErr }));
    process.exit(1);
  } catch (e) {
    console.error(JSON.stringify({ success: false, error: 'Unhandled exception', details: e && e.message ? e.message : String(e) }));
    process.exit(1);
  }
};

run();
