/*
Appwrite Function: search_users
Runtime: Node.js (>=18)
Description: Perform a safe user search using the Appwrite admin API key and
return only public fields, enforcing per-user prefs such as hideFromSearch and hideLastSeen.

Environment variables required (set in Appwrite Function settings):
- APPWRITE_ENDPOINT
- APPWRITE_PROJECT_ID
- APPWRITE_API_KEY

Execution payload (APPWRITE_FUNCTION_DATA): { "query": "...", "limit": 10 }

Returns JSON: { users: [ { id, name, nickname, prefs: { avatarUrl, hideFromSearch, hideLastSeen, ... }, lastSeen } ] }
*/

import fetch from 'node-fetch';

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT_ID;
const apiKey = process.env.APPWRITE_API_KEY;

async function main() {
  if (!endpoint || !projectId || !apiKey) {
    console.error('Missing required environment variables');
    console.log(JSON.stringify({ users: [] }));
    process.exit(1);
  }

  let payload = {};
  try {
    const raw = process.env.APPWRITE_FUNCTION_DATA || '{}';
    payload = JSON.parse(raw);
  } catch (e) {
    console.error('Invalid function payload', e);
    console.log(JSON.stringify({ users: [] }));
    process.exit(1);
  }

  const query = (payload.query || '').toString();
  const limit = Math.min(100, Number(payload.limit) || 10);

  try {
    const url = `${endpoint.replace(/\/+$/,'')}/v1/users?search=${encodeURIComponent(query)}&limit=${limit}`;
    const res = await fetch(url, { headers: { 'x-appwrite-project': projectId, 'x-appwrite-key': apiKey } });
    if (res.status < 200 || res.status >= 300) {
      const txt = await res.text();
      console.error('search_users failed', res.status, txt);
      console.log(JSON.stringify({ users: [] }));
      process.exit(1);
    }
    const parsed = await res.json();
    const usersRaw = (parsed && parsed.users) ? parsed.users : [];
    const usersOut = [];
    for (const u of usersRaw) {
      try {
        const prefs = (u.prefs && typeof u.prefs === 'object') ? u.prefs : {};
        if (prefs.hideFromSearch === true) continue;
        const lastSeen = (prefs.hideLastSeen === true) ? null : (prefs.lastSeen || null);
        const nickname = (prefs.nickname && prefs.nickname.toString().length > 0) ? prefs.nickname.toString() : (u.nickname || '');
        usersOut.push({ id: u.$id || u.id, name: u.name || nickname || '', nickname: nickname, prefs: { avatarUrl: prefs.avatarUrl, hideFromSearch: prefs.hideFromSearch, hideLastSeen: prefs.hideLastSeen }, lastSeen: lastSeen });
      } catch (e) {
        // ignore individual record parse errors
      }
    }

    console.log(JSON.stringify({ users: usersOut }));
    process.exit(0);
  } catch (e) {
    console.error('search_users exception', e);
    console.log(JSON.stringify({ users: [] }));
    process.exit(1);
  }
}

main();
