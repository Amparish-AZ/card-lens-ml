import os
from icrawler.builtin import BingImageCrawler, GoogleImageCrawler
import logging

SAVE_DIR = "Amparish/card-lens-main/ml/data/private/stock_business_cards/Camera"

# Turn off verbose logging
logging.getLogger('icrawler').setLevel(logging.ERROR)

def download_images():
    print(f"Downloading massive stock images to {SAVE_DIR}...")
    
    bing = BingImageCrawler(storage={'root_dir': SAVE_DIR}, downloader_threads=10)
    bing.crawl(keyword='business card photo', max_num=1000)

    bing2 = BingImageCrawler(storage={'root_dir': SAVE_DIR}, downloader_threads=10)
    bing2.crawl(keyword='site:unsplash.com business card', max_num=1000)
    
    bing3 = BingImageCrawler(storage={'root_dir': SAVE_DIR}, downloader_threads=10)
    bing3.crawl(keyword='site:pexels.com business card', max_num=1000)

    print("Download complete!")

if __name__ == '__main__':
    download_images()
