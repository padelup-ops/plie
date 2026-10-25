import sys
from playwright.sync_api import sync_playwright
def render(svg_path, png_path, size=1024):
    svg=open(svg_path).read()
    html=f"<html><body style='margin:0;background:#000'>{svg}</body></html>"
    with sync_playwright() as p:
        b=p.chromium.launch(); pg=b.new_page(viewport={'width':size,'height':size})
        pg.set_content(html); pg.wait_for_timeout(150)
        pg.screenshot(path=png_path, clip={'x':0,'y':0,'width':size,'height':size}); b.close()
if __name__=='__main__':
    render(sys.argv[1], sys.argv[2])
