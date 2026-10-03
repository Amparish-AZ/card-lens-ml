import os
from icrawler.builtin import BingImageCrawler, BaiduImageCrawler, GoogleImageCrawler
import logging

SAVE_DIR = "Amparish/card-lens-main/ml/data/private/stock_business_cards/Camera"
os.makedirs(SAVE_DIR, exist_ok=True)

# Turn off verbose logging
logging.getLogger('icrawler').setLevel(logging.ERROR)

def download_images():
    print(f"Downloading images to {SAVE_DIR}...")
    
    # Bing Crawler
    bing_crawler = BingImageCrawler(storage={'root_dir': SAVE_DIR})
    bing_crawler.crawl(keyword='site:pexels.com business card held in hand real', max_num=200)
    
    bing_crawler2 = BingImageCrawler(storage={'root_dir': SAVE_DIR})
    bing_crawler2.crawl(keyword='site:unsplash.com real business card', max_num=200)

    # Google Crawler
    google_crawler = GoogleImageCrawler(storage={'root_dir': SAVE_DIR})
    google_crawler.crawl(keyword='business card held in hand real photo', max_num=200)

    print("Download complete!")

if __name__ == '__main__':
    download_images()
