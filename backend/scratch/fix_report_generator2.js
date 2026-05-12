const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '../src/services/report-generator.service.ts');
let content = fs.readFileSync(filePath, 'utf8');

// fix maxCount
content = content.replace(/Math\.max\(\.\.\.chartData\.map\(d => d\.value\)\)/g, 'Math.max(...chartData.map(d => d.value as any))');

// fix doc.rect
content = content.replace(/doc\.rect\(([^,]+), ([^,]+), ([^,]+), ([^,]+), \{ fill: '([^']+)' \}\);/g, 'doc.rect($1, $2, $3, $4).fill(\'$5\');');

// fix doc.output
content = content.replace(/resolve\(Buffer\.from\(doc\.output\(\)\)\);/g, `const chunks: any[] = [];
        doc.on('data', chunk => chunks.push(chunk));
        doc.on('end', () => resolve(Buffer.concat(chunks)));`);

fs.writeFileSync(filePath, content);
