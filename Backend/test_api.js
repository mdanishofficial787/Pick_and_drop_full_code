const http = require('http');

http.get('http://127.0.0.1:3000/api/rides?status=assigned', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    console.log(JSON.parse(data));
  });
}).on('error', console.error);
