import sys, json, base64, asyncio
from playwright.async_api import async_playwright
async def run(specs):
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/opt/pw-browsers/chromium', args=['--use-gl=swiftshader','--enable-webgl','--ignore-gpu-blocklist'])
        page=await b.new_page(viewport={'width':800,'height':600})
        page.on('pageerror',lambda e:print('ERR',e))
        page.on('console',lambda m:print('C:',m.text[:200]) if 'GL Driver' not in m.text and 'favicon' not in m.text else None)
        await page.goto('http://localhost:8791/render.html')
        await page.wait_for_function('window.ready===true',timeout=60000)
        for name,spec in specs.items():
            if spec.get('glb'): await page.evaluate("u=>window.loadGlb(u)",spec['glb'])
            url=await page.evaluate("s=>window.renderTree(s)",spec)
            open(f'out/{name}.png','wb').write(base64.b64decode(url.split(',')[1])); print('ok',name)
        await b.close()
if __name__=='__main__':
    import os; os.makedirs('out',exist_ok=True)
    asyncio.run(run(json.load(open(sys.argv[1]))))
