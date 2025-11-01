/*
Appwrite Function: mirror_message
Node.js example that receives JSON { sourceChatId, payload }
and creates message documents for both sender (source chat) and recipient's chat (owner-specific).

Expected environment variables inside function:
- APPWRITE_ENDPOINT (https://.../v1)
- APPWRITE_PROJECT_ID
- APPWRITE_API_KEY (server/admin key)
- APPWRITE_DATABASE_ID
- APPWRITE_CHATS_COLLECTION_ID
- APPWRITE_MESSAGES_COLLECTION_ID

Note: Deploy this as an Appwrite Function and set proper environment variables.
*/

const fetch = require('node-fetch');

module.exports = async function (req, res) {
  try {
    const body = JSON.parse(req.payload || '{}');
    const sourceChatId = body.sourceChatId;
    const payload = body.payload || {};

    if (!sourceChatId || !payload) {
      return res.json({ error: 'invalid payload' }, 400);
    }

    const endpoint = process.env.APPWRITE_FUNCTION_ENDPOINT || process.env.APPWRITE_ENDPOINT;
    const project = process.env.APPWRITE_FUNCTION_PROJECT_ID || process.env.APPWRITE_PROJECT_ID;
    const apiKey = process.env.APPWRITE_API_KEY;
    const databaseId = process.env.APPWRITE_DATABASE_ID;
    const chatsCol = process.env.APPWRITE_CHATS_COLLECTION_ID;
    const messagesCol = process.env.APPWRITE_MESSAGES_COLLECTION_ID;

    if (!endpoint || !project || !apiKey || !databaseId || !chatsCol || !messagesCol) {
      return res.json({ error: 'server misconfigured' }, 500);
    }

    // Helper to call Appwrite REST
    const call = async (method, path, bodyObj) => {
      const url = `${endpoint.replace(/\/$/, '')}/v1${path}`.replace('/v1/v1','/v1');
      const headers = {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': project,
        'X-Appwrite-Key': apiKey,
      };
      const resp = await fetch(url, { method, headers, body: bodyObj ? JSON.stringify(bodyObj) : undefined });
      const text = await resp.text();
      let parsed = null;
      try { parsed = JSON.parse(text); } catch(e) { parsed = text; }
      return { status: resp.status, body: parsed };
    };

    // Get source chat document to find owner and peerId
    const g = await call('GET', `/databases/${databaseId}/collections/${chatsCol}/documents/${encodeURIComponent(sourceChatId)}`);
    if (g.status < 200 || g.status >= 300) return res.json({ error: 'source chat not found', detail: g }, 404);
    const sourceChat = g.body;
    const owner = sourceChat.owner || sourceChat.ownerId || sourceChat['owner'];
    const peerId = sourceChat.peerId || sourceChat.peer || (sourceChat.members && sourceChat.members.find(m => m !== owner));

    // Build message data
    const now = new Date().toISOString();
    const message = {
      ...payload,
      chatId: sourceChatId,
      createdAt: payload.createdAt || now,
      reactions: payload.reactions || [],
      deliveredTo: payload.deliveredTo || [],
      readBy: payload.readBy || [],
      fromUserId: payload.fromUserId || '',
      fromName: payload.fromName || '',
      fromAvatarUrl: payload.fromAvatarUrl || '',
    };

    // Create message for source chat
    const createSource = await call('POST', `/databases/${databaseId}/collections/${messagesCol}/documents`, { documentId: 'unique()', data: message });
    if (createSource.status < 200 || createSource.status >= 300) return res.json({ error: 'failed create source message', detail: createSource }, 500);

    // Try to find or create the peer's chat (owner = peerId, peerId = owner)
    let peerChatId = null;
    try {
      const candidateId = `dm_${peerId}_${owner}`;
      const g2 = await call('GET', `/databases/${databaseId}/collections/${chatsCol}/documents/${encodeURIComponent(candidateId)}`);
      if (g2.status >= 200 && g2.status < 300) {
        peerChatId = g2.body['$id'] || candidateId;
      }
    } catch(e) {}

    if (!peerChatId) {
      // Try to create peer chat with deterministic id
      try {
        const candidateId = `dm_${peerId}_${owner}`;
        const data = { members: [peerId, owner], owner: peerId, peerId: owner, name: '', avatarUrl: '', lastMessage: '', lastMessageTime: now, createdAt: now };
        const c3 = await call('POST', `/databases/${databaseId}/collections/${chatsCol}/documents`, { documentId: candidateId, data });
        if (c3.status >= 200 && c3.status < 300) peerChatId = candidateId;
      } catch (e) {}
    }

    // If we have peerChatId, create mirrored message for them
    if (peerChatId) {
      const mirror = { ...message, chatId: peerChatId };
      const cpeer = await call('POST', `/databases/${databaseId}/collections/${messagesCol}/documents`, { documentId: 'unique()', data: mirror });
      // ignore result if it fails; source message already created
    }

    // Return created source message as function result
    return res.json(createSource.body, 200);
  } catch (e) {
    console.error(e);
    return res.json({ error: 'exception', message: e.toString() }, 500);
  }
};
