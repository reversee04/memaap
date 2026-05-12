const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '../src/services/admin.service.ts');
let content = fs.readFileSync(filePath, 'utf8');

// revert dbClient back to client globally
content = content.replace(/dbClient/g, 'client');

// wait, the logAdminAction signature has `client?: PoolClient`.
// The script replaced it to:
//   private static async logAdminAction(
//     context: AdminActionContext,
//     client?: PoolClient
//   ): Promise<void> {
//     const isLocalClient = !client;
//     const dbClient = client || await this.getPool().connect();
// So if I replace dbClient with client globally, it becomes:
//     const client = client || await this.getPool().connect();
// This will cause a redeclaration error.

// So let's fix it properly.
// I will just use `const _client = client || await this.getPool().connect();` inside logAdminAction.

// Let's reload from file
content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/const dbClient = client/g, 'const _client = client');
content = content.replace(/dbClient\./g, '_client.');

// But wait, my script `fix_ts.js` did:
// content = content.replace(/await client\.query\(query/g, 'await dbClient.query(query');
// Which changed EVERY `await client.query` in the file to `await dbClient.query`.
// So let's change `await dbClient.query` back to `await client.query` EVERYWHERE.
content = content.replace(/await dbClient\.query/g, 'await client.query');

// And in logAdminAction, we need to change `client` to `_client`.
content = content.replace(/const _client = client/g, 'const _client = client'); // ensure it's _client
// Replace the query specifically in logAdminAction
content = content.replace(/await client\.query\(query, \[\n\s*uuidv4\(\),\n\s*context\.adminId/g, 'await _client.query(query, [\n        uuidv4(),\n        context.adminId');
content = content.replace(/if \(isLocalClient\) client\.release\(\);/g, 'if (isLocalClient) _client.release();');

fs.writeFileSync(filePath, content);
