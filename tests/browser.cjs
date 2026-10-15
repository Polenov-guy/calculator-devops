// Optional UI test. Requires npm package playwright and an installed Chromium.
// BASE_URL=http://127.0.0.1:8080 node tests/browser.cjs
const {chromium}=require('playwright');
(async()=>{
 const browser=process.env.CDP_URL ? await chromium.connectOverCDP(process.env.CDP_URL) : await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{}),args:['--no-sandbox']});
 try {
 const page=await browser.newPage({viewport:{width:1365,height:1000}}),errors=[];
 page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(process.env.BASE_URL||'http://127.0.0.1:8080');
 await page.locator('#status').filter({hasText:'Сервис работает'}).waitFor();
 await page.locator('#a').fill('12,5');await page.locator('#b').fill('2');await page.locator('[data-op="multiply"]').click();await page.locator('#submit').click();
 await page.waitForFunction(()=>document.querySelector('#result').textContent==='25');
 await page.reload();await page.waitForFunction(()=>document.querySelector('#history').textContent.includes('25'));
 await page.locator('[data-op="divide"]').click();await page.locator('#a').fill('1');await page.locator('#b').fill('0');await page.locator('#submit').click();
 await page.waitForFunction(()=>document.querySelector('#error').textContent.includes('деление на ноль'));
 await page.locator('[data-op="add"]').click();await page.locator('#a').fill('24');await page.locator('#b').fill('18');await page.locator('#submit').click();await page.waitForFunction(()=>document.querySelector('#result').textContent==='42');
 await page.screenshot({path:'docs/calculator-desktop.png',fullPage:true});
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:'docs/calculator-mobile.png',fullPage:true});
 if(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth))throw new Error('Mobile overflow');
 if(errors.length)throw new Error(errors.join('\n'));
 console.log('PASS browser: calculation, decimal comma, reload history, error display, mobile layout; no JS errors');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
