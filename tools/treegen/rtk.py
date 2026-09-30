import sys, json, base64, asyncio, os
from playwright.async_api import async_playwright
async def run(specs, only=None):
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/opt/pw-browsers/chromium', args=['--use-gl=swiftshader','--enable-webgl','--ignore-gpu-blocklist'])
        page=await b.new_page(viewport={'width':800,'height':600})
        page.on('pageerror',lambda e:print('ERR',e))
        await page.goto('http://localhost:8791/render.html')
        await page.wait_for_function('window.ready===true',timeout=60000)
        meta={}
        for name,spec in specs.items():
            if only and not any(name.startswith(o) for o in only): continue
            await page.evaluate("u=>window.loadGlb(u)",spec['glb'])
            url=await page.evaluate("s=>window.renderTree(s)",spec)
            open(f'outk/{name}.png','wb').write(base64.b64decode(url.split(',')[1]))
            meta[name]=await page.evaluate("window.lastMeta")
        json.dump(meta,open('outk/meta_%s.json'%('_'.join(only) if only else 'all'),'w'))
        await b.close()
if __name__=='__main__':
    os.makedirs('outk',exist_ok=True)
    asyncio.run(run(json.load(open(sys.argv[1])), sys.argv[2:] or None))
