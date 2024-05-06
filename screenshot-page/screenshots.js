const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  
  // Imposta la dimensione della finestra visualizzata
  await page.setViewport({ width: 1800, height: 800 });

  // Vai alla pagina desiderata
  await page.goto('https://comunitaenergeticarinnovabile.net/auth/login');

  // Ottieni l'altezza totale della pagina all'interno del browser
  const pageHeight = await page.evaluate(() => {
    return document.documentElement.scrollHeight;
  });

  // Imposta l'altezza della pagina per consentire di scorrere fino alla fine
  await page.setViewport({ width: 1800, height: pageHeight });

  // Fai uno screenshot dell'intera pagina
  await page.screenshot({ path: 'screenshot.png', fullPage: true });

  await browser.close();
})();
