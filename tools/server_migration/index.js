/*
Simple migration script (dry-run by default).
Configure the environment variables before running:
  APPWRITE_ENDPOINT (e.g. https://HOST/v1)
  APPWRITE_PROJECT
  APPWRITE_DATABASE_ID
  APPWRITE_CHATS_COLLECTION_ID
  APPWRITE_MESSAGES_COLLECTION_ID
  APPWRITE_API_KEY

This script will:
 - list all chat docs
 - for each direct chat with two members compute canonical id (sorted pair)
 - if canonical doc missing, create it
 - reassign messages from old chat id to canonical chat id
 - optionally delete or mark old chat

Run:
  npm install
  node index.js --dry-run=false
*/

const axios = require('axios');
const crypto = require('crypto');

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT;
const DB = process.env.APPWRITE_DATABASE_ID;
const CHATS = process.env.APPWRITE_CHATS_COLLECTION_ID;
const MESSAGES = process.env.APPWRITE_MESSAGES_COLLECTION_ID;
const API_KEY = process.env.APPWRITE_API_KEY;

if (!EP || !PROJECT || !DB || !CHATS || !MESSAGES || !API_KEY) {
  console.error('Missing required env vars. See header of script.');
  process.exit(1);
}

const client = axios.create({
  baseURL: EP.replace(/\/v1\/?$/, '') + '/v1',
  headers: {
    'x-appwrite-project': PROJECT,
    'x-appwrite-key': API_KEY,
    'content-type': 'application/json'
  },
  timeout: 30000,
});

async function listAllChats() {
  const docs = [];
  let offset = 0;
  const limit = 100;
  while (true) {
    const res = await client.get(`/databases/${DB}/collections/${CHATS}/documents?limit=${limit}&offset=${offset}`);
    if (!res.data || !Array.isArray(res.data.documents)) break;
    docs.push(...res.data.documents);
    if (res.data.documents.length < limit) break;
    offset += limit;
  }
  return docs;
}

function canonicalId(a, b) {
  const pair = [a, b].sort();
  let id = `dm_${pair[0]}_${pair[1]}`;
  if (id.length > 36) {
    // fallback to hash
    const hash = crypto.createHash('sha1').update(`${pair[0]}_${pair[1]}`).digest('hex');
    id = `dm_${hash.substring(0, 16)}`;
  }
  return id;
}

async function getDocument(collectionId, id) {
  try {
    const res = await client.get(`/databases/${DB}/collections/${collectionId}/documents/${id}`);
    return res.data;
  } catch (e) {
    return null;
  }
}

async function createDoc(collectionId, id, data) {
  const body = { documentId: id, data };
  const res = await client.post(`/databases/${DB}/collections/${collectionId}/documents`, body);
  return res.data;
}

async function listMessagesForChat(chatId) {
  const docs = [];
  let offset = 0; const limit = 100;
  while (true) {
    const res = await client.get(`/databases/${DB}/collections/${MESSAGES}/documents?limit=${limit}&offset=${offset}&filters=chatId%3D%3D${encodeURIComponent(chatId)}`);
    if (!res.data || !Array.isArray(res.data.documents)) break;
    docs.push(...res.data.documents);
    if (res.data.documents.length < limit) break;
    offset += limit;
  }
  return docs;
}

async function updateMessageChatId(messageId, newChatId) {
  const body = { data: { chatId: newChatId } };
  return await client.patch(`/databases/${DB}/collections/${MESSAGES}/documents/${messageId}`, body);
}

async function migrate(dryRun = true) {
  const chats = await listAllChats();
  console.log(`Found ${chats.length} chat documents`);
  for (const c of chats) {
    try {
      const type = (c.data && c.data.type) || c.type;
      const members = (c.data && c.data.members) || c.members || [];
      if (!Array.isArray(members) || members.length !== 2) continue;
      const a = members[0].toString();
      const b = members[1].toString();
      const canon = canonicalId(a, b);
      if (canon === c.$id || canon === c.id) continue; // already canonical
      const existing = await getDocument(CHATS, canon);
      if (existing) {
        console.log(`Canonical ${canon} exists for ${c.$id} -> will reassign messages`);
      } else {
        console.log(`Canonical ${canon} missing for ${c.$id} -> will create`);
      }
      if (!dryRun) {
        if (!existing) {
          const createData = Object.assign({}, c.data || {});
          createData.members = [a, b].sort();
          createData.createdAt = createData.createdAt || new Date().toISOString();
          await createDoc(CHATS, canon, createData);
          console.log(`Created canonical chat ${canon}`);
        }
        // reassign messages
        const msgs = await listMessagesForChat(c.$id);
        console.log(`Found ${msgs.length} messages to reassign from ${c.$id} -> ${canon}`);
        for (const m of msgs) {
          await updateMessageChatId(m.$id, canon);
        }
        // Optionally delete or mark old chat
        // await client.delete(`/databases/${DB}/collections/${CHATS}/documents/${c.$id}`);
      }
    } catch (e) {
      console.error('Error migrating chat', c.$id, e.toString());
    }
  }
  console.log('Migration finished');
}

const argv = require('minimist')(process.argv.slice(2));
const dryRun = argv['dry-run'] !== 'false';

migrate(dryRun).catch((e) => { console.error(e); process.exit(1); });
