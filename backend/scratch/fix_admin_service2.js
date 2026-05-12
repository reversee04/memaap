const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '../src/services/admin.service.ts');
let content = fs.readFileSync(filePath, 'utf8');

// replace _client back to client globally
content = content.replace(/_client/g, 'client');

// Now in logAdminAction, we need to fix it:
// private static async logAdminAction(
//   context: AdminActionContext,
//   client?: PoolClient
// ): Promise<void> {
//   const isLocalClient = !client;
//   const client = client || await this.getPool().connect();

// That's a syntax error (client redeclared).
// Let's replace the whole logAdminAction method
content = content.replace(/private static async logAdminAction\([\s\S]*?client:\s*PoolClient[\s\S]*?\): Promise<void> \{([\s\S]*?)try \{/, 
`private static async logAdminAction(
    context: AdminActionContext,
    transactionClient?: PoolClient
  ): Promise<void> {
    const isLocalClient = !transactionClient;
    const client = transactionClient || await this.getPool().connect();
    try {`);

// But since we already ran the script before, it currently looks like:
// private static async logAdminAction(
//   context: AdminActionContext,
//   client?: PoolClient
// ): Promise<void> {
//   const isLocalClient = !client;
//   const client = client || await this.getPool().connect();
//   try {

// Let's just regex replace the exact broken part
content = content.replace(/private static async logAdminAction\(\s*context: AdminActionContext,\s*client\?: PoolClient\s*\): Promise<void> \{\s*const isLocalClient = !client;\s*const client = client \|\| await this\.getPool\(\)\.connect\(\);\s*try \{/g, 
`private static async logAdminAction(
    context: AdminActionContext,
    transactionClient?: PoolClient
  ): Promise<void> {
    const isLocalClient = !transactionClient;
    const client = transactionClient || await this.getPool().connect();
    try {`);

fs.writeFileSync(filePath, content);
