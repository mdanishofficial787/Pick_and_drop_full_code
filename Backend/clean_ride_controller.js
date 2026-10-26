const fs = require('fs');
const file = __dirname + '/Controller/RideController.js';
let content = fs.readFileSync(file, 'utf8');

const badBlock = `        io.to(\`ride_\${rId}\`).emit("ride-updated", notifyPayload);





        }




        }

      }
    } catch (socketErr) {`;

const goodBlock = `        io.to(\`ride_\${rId}\`).emit("ride-updated", notifyPayload);
      }
    } catch (socketErr) {`;

if (content.includes(goodBlock)) {
  console.log("Already clean!");
} else {
  // normalize newlines
  const norm = content.replace(/\r\n/g, '\n');
  const target = `        io.to(\`ride_\${rId}\`).emit("ride-updated", notifyPayload);\n\n\n\n\n        }\n\n\n\n        }\n\n      }\n    } catch (socketErr) {`;
  if (norm.includes(target)) {
    const fixed = norm.replace(target, `        io.to(\`ride_\${rId}\`).emit("ride-updated", notifyPayload);\n      }\n    } catch (socketErr) {`);
    fs.writeFileSync(file, fixed);
    console.log("Successfully fixed RideController!");
  } else {
    console.log("Pattern not found, checking with regex...");
    const regex = /io\.to\(`ride_\${rId}`\)\.emit\("ride-updated", notifyPayload\);[\s\S]*?} catch \(socketErr\) {/;
    const repl = `io.to(\`ride_\${rId}\`).emit("ride-updated", notifyPayload);\n      }\n    } catch (socketErr) {`;
    const fixed = norm.replace(regex, repl);
    fs.writeFileSync(file, fixed);
    console.log("Regex replaced successfully!");
  }
}
