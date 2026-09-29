import asyncio, sys, os, json, requests
os.environ['REQUESTS_CA_BUNDLE']='/root/.ccr/ca-bundle.crt'
from playwright.async_api import async_playwright
sess=requests.Session()
found=[]
async def handler(route, request):
    h={k:v for k,v in request.headers.items() if k.lower() not in ('host','content-length','accept-encoding')}
    try:
        r=await asyncio.to_thread(sess.request, request.method, request.url, headers=h, data=request.post_data_buffer, allow_redirects=False, timeout=60)
    except Exception as e:
        await route.abort(); return
    if '/file/' in request.url:
        try:
            j=r.json(); print('FILE JSON',j); 
            if 'url' in j:
                fn=f"{GAME}_{len(found)}.zip"; found.append(fn)
                def grab(u=j['url'],fn=fn):
                    with sess.get(u,stream=True,timeout=1500) as resp:
                        print('status',resp.status_code)
                        with open(fn,'wb') as f:
                            for c in resp.iter_content(1<<20): f.write(c)
                    print('saved',fn,os.path.getsize(fn))
                await asyncio.to_thread(grab)
        except Exception: pass
    hd={k:v for k,v in r.headers.items() if k.lower() not in ('content-encoding','transfer-encoding','content-length')}
    await route.fulfill(status=r.status_code, headers=hd, body=r.content)
async def main(game):
    global GAME; GAME=game
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/opt/pw-browsers/chromium')
        ctx=await b.new_context(accept_downloads=True)
        page=await ctx.new_page()
        await page.route('**/*', handler)
        await page.goto(f'https://polyyai.itch.io/{game}/purchase',timeout=90000)
        await page.click('a.direct_download_btn')
        await page.wait_for_selector('a.download_btn',timeout=90000)
        n=len(await page.query_selector_all('a.download_btn'))
        for i in range(n):
            await page.click(f'a.download_btn >> nth={i}')
            await page.wait_for_timeout(3000)
        await b.close()
asyncio.run(main(sys.argv[1]))
