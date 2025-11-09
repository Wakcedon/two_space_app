// index.js
const sdk = require('node-appwrite');

module.exports = async (req, res) => {
  try {
    const body = JSON.parse(req.payload || '{}');
    const { messageId, emoji, userId } = body;
    const endpoint = process.env.APPWRITE_FUNCTION_ENDPOINT || process.env.APPWRITE_ENDPOINT;
    const project = process.env.APPWRITE_FUNCTION_PROJECT_ID || process.env.APPWRITE_PROJECT_ID;
    const apiKey = process.env.APPWRITE_API_KEY;
    const databaseId = process.env.APPWRITE_DATABASE_ID;
    const messagesId = process.env.APPWRITE_MESSAGES_TABLE_ID || process.env.APPWRITE_MESSAGES_COLLECTION_ID;
    const useTables = !!process.env.APPWRITE_MESSAGES_TABLE_ID;
    const seg = useTables ? 'tables' : 'collections';
    const docSeg = useTables ? 'rows' : 'documents';

    if (!endpoint || !project || !apiKey || !databaseId || !messagesId) {
      return res.json({ success: false, error: 'server misconfigured' }, 500);
    }

    const call = async (method, path, bodyObj) => {
      const url = `${endpoint.replace(/\/$/, '')}/v1${path}`.replace('/v1/v1','/v1');
      const headers = { 'Content-Type': 'application/json', 'X-Appwrite-Project': project, 'X-Appwrite-Key': apiKey };
      const resp = await fetch(url, { method, headers, body: bodyObj ? JSON.stringify(bodyObj) : undefined });
      const text = await resp.text();
      let parsed = null;
      try { parsed = JSON.parse(text); } catch(e) { parsed = text; }
      return { status: resp.status, body: parsed };
    };

    // Read message
    const g = await call('GET', `/databases/${databaseId}/${seg}/${messagesId}/${docSeg}/${encodeURIComponent(messageId)}`);
    if (g.status < 200 || g.status >= 300) return res.json({ success: false, error: 'message not found', detail: g }, 404);
    const msg = g.body;
    const reactions = Array.isArray(msg.reactions) ? msg.reactions : [];
    reactions.push(emoji);
    // Update by PATCHing data
    const upd = await call('PATCH', `/databases/${databaseId}/${seg}/${messagesId}/${docSeg}/${encodeURIComponent(messageId)}`, { data: { reactions } });
    if (upd.status < 200 || upd.status >= 300) return res.json({ success: false, error: 'update failed', detail: upd }, 500);
    return res.json({ success: true });
  } catch (e) {
    console.error(e);
    return res.json({ success: false, error: e.toString() }, 500);
  }
};