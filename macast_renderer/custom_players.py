import os
import subprocess
import logging
import gettext
from macast.renderer import Renderer

logger = logging.getLogger("CustomRenderer")

class SystemPlayerRenderer(Renderer):
    def __init__(self, lang=gettext.gettext):
        super(SystemPlayerRenderer, self).__init__(lang)
        self.title = "System Default Player"

    def set_media_url(self, url, start="0"):
        logger.info(f"Opening URL with system default application: {url}")
        subprocess.Popen(['open', url])

    def set_media_stop(self):
        pass


class IINAPlayerRenderer(Renderer):
    def __init__(self, lang=gettext.gettext):
        super(IINAPlayerRenderer, self).__init__(lang)
        self.title = "IINA Player"

    def set_media_url(self, url, start="0"):
        logger.info(f"Opening URL with IINA: {url}")
        subprocess.Popen(['open', '-a', 'IINA', url])

    def set_media_stop(self):
        pass


class QuickTimePlayerRenderer(Renderer):
    def __init__(self, lang=gettext.gettext):
        super(QuickTimePlayerRenderer, self).__init__(lang)
        self.title = "QuickTime Player"

    def set_media_url(self, url, start="0"):
        logger.info(f"Opening URL with QuickTime Player: {url}")
        subprocess.Popen(['open', '-a', 'QuickTime Player', url])

    def set_media_stop(self):
        pass
