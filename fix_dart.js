const fs = require('fs'); let content = fs.readFileSync('Frontend/lib/api_config.dart', 'utf8'); content = content.replace(/\0/g, ''); fs.writeFileSync('Frontend/lib/api_config.dart', content);
