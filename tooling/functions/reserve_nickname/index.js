// index.js
const sdk = require('node-appwrite');

module.exports = async (req, res) => {
  try {
    const body = JSON.parse(req.payload || '{}');
    const { messageId, emoji, userId } = body;
    const client = new sdk.Client();
    client.setEndpoint(process.env.APPWRITE_ENDPOINT).setProject(process.env.APPWRITE_PROJECT_ID).setKey(process.env.APPWRITE_API_KEY);
    const databases = new sdk.Databases(client);
    const dbId = process.env.APPWRITE_DATABASE_ID;
    const msgColl = process.env.APPWRITE_MESSAGES_COLLECTION_ID;

    // Read message
    const msg = await databases.getDocument(dbId, msgColl, messageId);
    const reactions = Array.isArray(msg.reactions) ? msg.reactions : [];
    // For simplicity we store reactions as array of emoji strings (duplicates allowed).
    // Better: store map emoji -> list of userIds.
    reactions.push(emoji);
    await databases.updateDocument(dbId, msgColl, messageId, { reactions });
    return res.json({ success: true });
  } catch (e) {
    console.error(e);
    return res.json({ success: false, error: e.toString() }, 500);
  }
};