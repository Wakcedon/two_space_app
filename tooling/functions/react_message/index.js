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
    const MESSAGES_COLLECTION_ID = process.env.APPWRITE_MESSAGES_COLLECTION_ID;

    if (!APPWRITE_ENDPOINT || !APPWRITE_PROJECT_ID || !APPWRITE_API_KEY || !DATABASE_ID || !MESSAGES_COLLECTION_ID) {
      console.error(JSON.stringify({ success: false, error: 'Missing required environment variables. NEED: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID, APPWRITE_MESSAGES_COLLECTION_ID' }));
      process.exit(1);
    }

    if (!messageId || !emoji || !userId) {
      console.error(JSON.stringify({ success: false, error: 'Missing required payload fields: messageId, emoji, userId' }));
      process.exit(1);
    }

    const client = new Client()
      .setEndpoint(APPWRITE_ENDPOINT)
      .setProject(APPWRITE_PROJECT_ID)
      .setKey(APPWRITE_API_KEY);

    const databases = new Databases(client);

    // Retry loop to reduce race window
    const maxAttempts = 4;
    let attempt = 0;
    let lastErr = null;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        // Read current document
        const messageDoc = await databases.getDocument(DATABASE_ID, MESSAGES_COLLECTION_ID, messageId);

        // Pull existing reactions map (emoji -> array of userIds)
        const existing = messageDoc.reactions || {};
        // clone to avoid mutating fetched object
        const newReactions = JSON.parse(JSON.stringify(existing));
        const arr = Array.isArray(newReactions[emoji]) ? newReactions[emoji] : [];

        const idx = arr.indexOf(userId);
        if (idx === -1) {
          // Add reaction
          arr.push(userId);
        } else {
          // Remove reaction
          arr.splice(idx, 1);
        }

        // If array becomes empty, remove the emoji key to keep document tidy
        if (arr.length === 0) {
          delete newReactions[emoji];
        } else {
          newReactions[emoji] = arr;
        }

        // Perform update: set only the reactions field (minimize risk of overwriting other fields)
        const updated = await databases.updateDocument(DATABASE_ID, MESSAGES_COLLECTION_ID, messageId, { reactions: newReactions });

        // Success — output updated reactions and document id
        console.log(JSON.stringify({ success: true, messageId: messageId, reactions: newReactions, document: updated }));
        process.exit(0);
      } catch (err) {
        lastErr = err;
        // If it's a conflict-like error, retry a few times; otherwise break
        attempt < maxAttempts ? await new Promise(r => setTimeout(r, 200 * attempt)) : null;
      }
    }

    // If reached here — all retries failed
    console.error(JSON.stringify({ success: false, error: 'Failed to toggle reaction after retries', details: lastErr && lastErr.message ? lastErr.message : lastErr }));
    process.exit(1);
  } catch (e) {
    console.error(JSON.stringify({ success: false, error: 'Unhandled exception', details: e && e.message ? e.message : String(e) }));
    process.exit(1);
  }
};

run();
