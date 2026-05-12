const fs = require('fs');
const path = require('path');

const servicesDir = path.join(__dirname, '../src/services');
const files = fs.readdirSync(servicesDir).filter(f => f.endsWith('.ts'));

files.forEach(file => {
  const filePath = path.join(servicesDir, file);
  let content = fs.readFileSync(filePath, 'utf8');
  
  // Fix catch (error) -> catch (error: any)
  content = content.replace(/catch\s*\(\s*error\s*\)\s*\{/g, 'catch (error: any) {');
  
  // Fix imports in admin.service.ts
  if (file === 'admin.service.ts') {
    content = content.replace(/from '\.\/user\.repository'/g, "from '../repositories/user.repository'");
    content = content.replace(/from '\.\/hospital\.repository'/g, "from '../repositories/hospital.repository'");
    content = content.replace(/from '\.\/emergency-request\.repository'/g, "from '../repositories/emergency-request.repository'");
    
    // Fix logger
    content = content.replace(/private readonly logger = winston/g, 'private static readonly logger = winston');
    
    // Fix logAdminAction to handle optional client
    content = content.replace(/private static async logAdminAction\([\s\S]*?client:\s*PoolClient[\s\S]*?\): Promise<void> \{([\s\S]*?)try \{/, 
`private static async logAdminAction(
    context: AdminActionContext,
    client?: PoolClient
  ): Promise<void> {
    const isLocalClient = !client;
    const dbClient = client || await this.getPool().connect();
    try {`);
    
    content = content.replace(/await client\.query\(query/g, 'await dbClient.query(query');
    
    content = content.replace(/\}\s*catch\s*\(error:\s*any\)\s*\{\s*this\.logger\.error\('Failed to log admin action:', error\);\s*\/\/[^\n]*\n\s*\}/,
`} catch (error: any) {
      this.logger.error('Failed to log admin action:', error);
    } finally {
      if (isLocalClient) dbClient.release();
    }`);
  }

  // Fix imports in auth.service.ts if needed
  if (file === 'auth.service.ts') {
    content = content.replace(/from '\.\/user\.repository'/g, "from '../repositories/user.repository'");
  }
  
  fs.writeFileSync(filePath, content);
});
