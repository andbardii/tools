const { SitemapStream, streamToPromise } = require('sitemap');
const { createWriteStream } = require('fs');
const links = [
  { url: '/home',  changefreq: 'daily', priority: 0.7 },
  { url: '/about',  changefreq: 'monthly' },
  // Aggiungi altre route qui
];

const sitemap = new SitemapStream({ hostname: 'https://www.tuo-sito.com' });

streamToPromise(sitemap).then(sitemap => console.log(sitemap.toString())).catch(e => console.error(e));
sitemap.pipe(createWriteStream('./path-to-your-public/sitemap.xml'));
links.forEach(link => sitemap.write(link));
sitemap.end();