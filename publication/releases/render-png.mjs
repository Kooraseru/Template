import fs from 'node:fs';
import { Resvg } from '@resvg/resvg-js';
fs.mkdirSync('/output', { recursive: true });
for (const file of fs.readdirSync('/input').filter(file => file.endsWith('.svg'))) {
  const renderer = new Resvg(fs.readFileSync(`/input/${file}`), {
    font: { loadSystemFonts: false, fontFiles: ['/app/JetBrainsMono-Regular.ttf'], defaultFontFamily: 'JetBrains Mono' },
  });
  fs.writeFileSync(`/output/${file.replace(/\.svg$/, '.png')}`, renderer.render().asPng());
}
