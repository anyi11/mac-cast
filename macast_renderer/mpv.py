# Copyright (c) 2021 by xfangfang. All Rights Reserved.
# Modified & optimized by anyi11 (https://github.com/anyi11/mac-cast)
#
# MPV Renderer and gui Setting
#

import os
import sys
import json
import time
import socket
import random
import subprocess
import logging
import threading
import cherrypy
import gettext
from enum import Enum

from macast.utils import Setting, SETTING_DIR
from macast.renderer import Renderer, RendererSetting
from macast.gui import App, MenuItem

if os.name == 'nt':
    import _winapi
    from multiprocessing.connection import PipeConnection

logger = logging.getLogger("MPVRenderer")
logger.setLevel(logging.DEBUG)


class ObserveProperty(Enum):
    volume = 1
    time_pos = 2
    pause = 3
    mute = 4
    duration = 5
    track_list = 6
    speed = 7
    sub = 8


class MPVRenderer(Renderer):
    """
      When the DLNA client accesses, MPVRenderer will returns the state value
    corresponding to "out" section in the action specified in the service XML
    file by default.
      When some "service_action" methods are implemented
    (such as "RenderingControl_SetVolume"), the DLNA client's access will be
    automatically directed to these methods
    """

    def __init__(self, lang=gettext.gettext, path="mpv"):
        super(MPVRenderer, self).__init__(lang)
        global _
        _ = lang
        mpv_rand = random.randint(0, 9999)
        if os.name == 'nt':
            self.mpv_sock = Setting.get_base_path(r"\\.\pipe\macast_mpvsocket{}".format(mpv_rand))
        else:
            self.mpv_sock = os.path.join(SETTING_DIR, 'macast_mpvsocket{}'.format(mpv_rand))
        self.path = path
        self.proc = None
        self.title = Setting.get_friendly_name()
        self.mpv_thread = None
        self.ipc_thread = None
        self.ipc_sock = None
        self.pause = False  # changed with pause action
        self.playing = False  # changed with start and stop
        self.ipc_running = False
        self.ipc_once_connected = False
        # As long as IPC has been connected, the ipc_once_connected is True
        # When the ipc_once_connected is True, it shows that there is no error
        # in the starting parameters of MPV, and there is no need to wait for
        # one second to restart MPV.
        self.history = []
        self.history_index = -1
        self.navigating = False
        self.command_lock = threading.Lock()
        self.renderer_setting = MPVRendererSetting()
        self.mpv_version_newer = True
        try:
            out = subprocess.check_output([self.path, '--version'], stderr=subprocess.STDOUT)
            out_str = out.decode('utf-8', errors='ignore')
            import re
            m = re.search(r'mpv\s+(\d+)\.(\d+)', out_str)
            if m:
                major = int(m.group(1))
                minor = int(m.group(2))
                if major == 0 and minor < 33:
                    self.mpv_version_newer = False
                    logger.info(f"Detected old mpv version: {major}.{minor}. Using old loadfile syntax.")
                else:
                    logger.info(f"Detected modern mpv version: {major}.{minor}. Using new loadfile syntax.")
        except Exception as e:
            logger.error(f"Failed to detect mpv version, defaulting to modern syntax: {e}")


    def set_media_stop(self):
        self.send_command(['stop'])

    def set_media_pause(self):
        self.send_command(['set_property', 'pause', True])
        self.set_media_text('Pause')

    def set_media_resume(self):
        self.send_command(['set_property', 'pause', False])
        self.set_media_text('Resume')

    def set_media_volume(self, data):
        """ data : int, range from 0 to 100
        """
        self.send_command(['set_property', 'volume', data])
        self.set_media_text(f'Volume: {data}')

    def set_media_mute(self, data):
        """ data : bool
        """
        self.send_command(['set_property', 'mute', "yes" if data else "no"])
        self.set_media_text(f'Mute: {data}')

    def set_media_url(self, url, start="0"):
        """ data : string
        """
        if not self.navigating:
            if self.history_index >= 0 and self.history_index < len(self.history) - 1:
                self.history = self.history[:self.history_index + 1]
            if not self.history or self.history[-1]['url'] != url:
                self.history.append({'url': url, 'title': 'Macast'})
                self.history_index = len(self.history) - 1
        self.navigating = False
        self.update_history_properties()

        options = {'start': start}
        player_size = Setting.get(SettingProperty.PlayerSize,
                                  default=SettingProperty.PlayerSize_Normal.value)
        if player_size == SettingProperty.PlayerSize_FullScreen.value:
            options['fullscreen'] = 'yes'
        options_str = ','.join([f'{i}={options[i]}' for i in options])
        if self.mpv_version_newer:
            self.send_command(['loadfile', url, 'replace', -1, options_str])
        else:
            self.send_command(['loadfile', url, 'replace', options_str])

    def set_media_title(self, data):
        """ data : string
        """
        self.title = data
        self.send_command(['set_property', 'title', data])
        if self.history_index >= 0 and self.history_index < len(self.history):
            self.history[self.history_index]['title'] = data

    def play_prev(self):
        logger.info("play_prev triggered")
        if self.history_index > 0:
            self.history_index -= 1
            self.navigating = True
            item = self.history[self.history_index]
            logger.info(f"Navigating to prev video: {item}")
            self.set_media_url(item['url'])
            self.set_media_title(item['title'])
            self.set_media_text(f"Previous: {item['title']}", 2000)
        else:
            logger.info("No previous video in history")
            self.set_media_text("No previous video", 2000)

    def play_next(self):
        logger.info("play_next triggered")
        if self.history_index < len(self.history) - 1:
            self.history_index += 1
            self.navigating = True
            item = self.history[self.history_index]
            logger.info(f"Navigating to next video: {item}")
            self.set_media_url(item['url'])
            self.set_media_title(item['title'])
            self.set_media_text(f"Next: {item['title']}", 2000)
        else:
            logger.info("No next video in history")
            self.set_media_text("No next video", 2000)

    def ensure_uosc_fonts(self):
        try:
            if os.name == 'nt':
                mpv_config_dir = os.path.expandvars(r'%APPDATA%\mpv')
            else:
                mpv_config_dir = os.path.expanduser('~/.config/mpv')
            
            user_fonts_dir = os.path.join(mpv_config_dir, 'fonts')
            if not os.path.exists(user_fonts_dir):
                os.makedirs(user_fonts_dir, exist_ok=True)
            
            local_fonts_dir = Setting.get_base_path('fonts')
            logger.info(f"Local fonts path: {local_fonts_dir}, user fonts path: {user_fonts_dir}")
            if os.path.exists(local_fonts_dir):
                import shutil
                for f in os.listdir(local_fonts_dir):
                    if f.endswith('.otf') or f.endswith('.ttf'):
                        src = os.path.join(local_fonts_dir, f)
                        dst = os.path.join(user_fonts_dir, f)
                        if not os.path.exists(dst) or os.path.getsize(src) != os.path.getsize(dst):
                            shutil.copy2(src, dst)
                            logger.info(f"Successfully copied font {f} to {dst}")
            else:
                logger.error(f"Local fonts directory does not exist: {local_fonts_dir}")
        except Exception as e:
            logger.error(f"Error copying uosc fonts to user directory: {e}")


    def set_media_position(self, data):
        """ data : position, 00:00:00
        """
        self.send_command(['seek', data, 'absolute'])

    def set_media_sub_file(self, data):
        self.send_command(['sub-add', data['url'], 'select', data['title']])

    def set_media_sub_show(self, data: bool):
        self.send_command(['set_property', 'sub-visibility', "yes" if data else "no"])

    def set_media_text(self, data: str, duration: int = 1000):
        self.send_command(['show-text', data, duration])

    def set_media_speed(self, data: float = 1):
        """
        :param data: range(0.01 - 100)
        :return:
        """
        self.send_command(['set_property', 'speed', data])

    def update_history_properties(self):
        has_prev = "yes" if self.history_index > 0 else "no"
        has_next = "yes" if self.history_index < len(self.history) - 1 else "no"
        logger.info(f"Updating mpv user-data history properties: has-prev={has_prev}, has-next={has_next}")
        self.send_command(['set_property', 'user-data/macast/has-prev', has_prev])
        self.send_command(['set_property', 'user-data/macast/has-next', has_next])

    def set_observe(self):
        """Set several property that needed observe
        """
        self.send_command(
            ['observe_property', ObserveProperty.volume.value, 'volume'])
        self.send_command(
            ['observe_property', ObserveProperty.time_pos.value, 'time-pos'])
        self.send_command(
            ['observe_property', ObserveProperty.pause.value, 'pause'])
        self.send_command(
            ['observe_property', ObserveProperty.mute.value, 'mute'])
        self.send_command(
            ['observe_property', ObserveProperty.duration.value, 'duration'])
        self.send_command(
            ['observe_property', ObserveProperty.track_list.value,
             'track-list'])
        self.send_command(
            ['observe_property', ObserveProperty.speed.value,
             'speed'])
        self.send_command(
            ['observe_property', ObserveProperty.sub.value,
             'sub-visibility'])

        self.set_media_volume(Setting.get(SettingProperty.PlayerDefaultVolume, 100))
        self.update_history_properties()

    def update_state(self, res):
        """Update player state from mpv
        """
        res = json.loads(res)
        if 'id' in res:
            if res['id'] == ObserveProperty.volume.value:
                logger.info(res)
                if 'data' in res and res['data'] is not None:
                    self.set_state_volume(int(res['data']))
            elif res['id'] == ObserveProperty.time_pos.value:
                if 'data' not in res or res['data'] is None:
                    position = '00:00:00'
                else:
                    sec = int(res['data'])
                    position = '%d:%02d:%02d' % (sec // 3600, (sec % 3600) // 60, sec % 60)
                self.set_state_position(position)
            elif res['id'] == ObserveProperty.pause.value:
                logger.info(res)
                if self.playing is False:
                    return
                if res['data'] and res['data'] is not None:
                    self.pause = True
                    self.set_state_pause()
                else:
                    self.pause = False
                    self.set_state_play()
            elif res['id'] == ObserveProperty.mute.value:
                self.set_state_mute(res['data'])
            elif res['id'] == ObserveProperty.duration.value:
                if 'data' not in res or res['data'] is None:
                    duration = '00:00:00'
                else:
                    sec = int(res['data'])
                    duration = '%d:%02d:%02d' % (sec // 3600, (sec % 3600) // 60, sec % 60)
                    cherrypy.engine.publish('mpv_update_duration', duration)
                    logger.info("update duration " + duration)
                    if self.protocol.get_state_transport_state() == 'PLAYING':
                        logger.debug("Living media")
                self.set_state_duration(duration)
            elif res['id'] == ObserveProperty.track_list.value:
                if res['data'] and res['data'] is not None:
                    tracks = len(res['data'])
                    self.set_state('CurrentTrack', 0 if tracks == 0 else 1)
                    self.set_state('NumberOfTracks', tracks)
            elif res['id'] == ObserveProperty.speed.value:
                data = res.get('data', None)
                if data is not None:
                    self.set_state_speed(data)
            elif res['id'] == ObserveProperty.sub.value:
                data = res.get('data', None)
                if data is not None:
                    self.set_state_subtitle(data)
        elif 'event' in res:
            logger.info(res)
            if res['event'] == 'end-file':
                cherrypy.engine.publish('renderer_av_stop')
                self.playing = False
                if 'reason' not in res:
                    self.set_state_stop()
                elif res['reason'] == 'error':
                    self.set_state_transport_error()
                elif res['reason'] == 'eof':
                    # NO_MEDIA_PRESENT
                    self.set_state_eof()
                else:
                    self.set_state_stop()
                if res.get('file_error', False):
                    cherrypy.engine.publish('app_notify',
                                            "File error",
                                            res['file_error'])
            elif res['event'] == 'start-file':
                self.playing = True
                # self.set_state_transport('TRANSITIONING')
                cherrypy.engine.publish('renderer_av_uri', self.protocol.get_state_url())
            elif res['event'] == 'client-message':
                args = res.get('args', [])
                logger.info(f"Received client-message: {args}")
                if args:
                    if args[0] == 'macast-prev':
                        self.play_prev()
                    elif args[0] == 'macast-next':
                        self.play_next()
            elif res['event'] == 'seek':
                pass
                # self.set_state_transport('TRANSITIONING')
            elif res['event'] == 'idle':
                # video comes to end
                self.playing = False
                self.set_state_stop()
            elif res['event'] == 'playback-restart':
                # video is ready to play
                if self.pause:
                    self.set_state_pause()
                else:
                    self.set_state_play()
        else:
            logger.debug(res)

    def send_command(self, command):
        """Sending command to mpv
        """
        logger.debug("send command: " + str(command))
        data = {"command": command}
        msg = json.dumps(data) + '\n'
        with self.command_lock:
            try:
                if os.name == 'nt':
                    self.ipc_sock.send_bytes(msg.encode())
                else:
                    self.ipc_sock.sendall(msg.encode())
                return True
            except Exception as e:
                logger.error('sendCommand: ' + str(e))
                return False

    def start_ipc(self):
        """Start ipc thread
        Communicating with mpv
        """
        if self.ipc_running:
            logger.error("mpv ipc is already runing")
            return
        self.ipc_running = True
        while self.ipc_running and self.running and self.mpv_thread.is_alive():
            try:
                time.sleep(0.5)
                logger.error("mpv ipc socket start connect: {}".format(self.mpv_sock))
                if os.name == 'nt':
                    handler = _winapi.CreateFile(
                        self.mpv_sock,
                        _winapi.GENERIC_READ | _winapi.GENERIC_WRITE, 0,
                        _winapi.NULL, _winapi.OPEN_EXISTING,
                        _winapi.FILE_FLAG_OVERLAPPED, _winapi.NULL)
                    self.ipc_sock = PipeConnection(handler)
                else:
                    self.ipc_sock = socket.socket(socket.AF_UNIX,
                                                  socket.SOCK_STREAM)
                    self.ipc_sock.connect(self.mpv_sock)
                cherrypy.engine.publish('mpvipc_start')
                cherrypy.engine.publish('renderer_start')
                self.ipc_once_connected = True
                self.set_observe()
            except Exception as e:
                logger.error("mpv ipc socket reconnecting: {}".format(str(e)))
                continue
            res = b''
            msgs = None
            while self.ipc_running:
                try:
                    if os.name == 'nt':
                        data = self.ipc_sock.recv_bytes(1048576)
                    else:
                        data = self.ipc_sock.recv(1048576)
                    if data == b'':
                        break
                    res += data
                    if data[-1] != 10:
                        continue
                except Exception as e:
                    logger.debug(e)
                    break
                try:
                    msgs = res.decode().strip().split('\n')
                    for msg in msgs:
                        self.update_state(msg)
                except Exception as e:
                    logger.error("decode error: {}".format(e))
                    logger.error(f"decode error data: {msg}")
                    logger.error(f"decode error data list: {msgs}")
                finally:
                    res = b''
            self.ipc_sock.close()
            logger.error("mpv ipc stopped")

    def start_mpv(self):
        """Start mpv thread
        """
        self.ensure_uosc_fonts()
        error_time = 3
        while self.running and error_time > 0:
            self.set_state_speed('1')
            # mpv default params
            params = [
                self.path,
                '--input-ipc-server={}'.format(self.mpv_sock),
                '--image-display-duration=inf',
                '--idle=yes',
                '--no-terminal',
                '--on-all-workspaces',
                '--hwdec=yes',
                '--save-position-on-quit=yes',
                '--script-opts=osc-timetotal=yes,osc-layout=bottombar,' +
                'osc-title=${title},osc-showwindowed=yes,' +
                'osc-seekbarstyle=bar,osc-visibility=auto'
            ]

            lock_size = Setting.get(SettingProperty.PlayerLockSize,
                                    default=SettingProperty.PlayerLockSize_False.value)
            if lock_size == SettingProperty.PlayerLockSize_True.value:
                params.append('--no-auto-window-resize')
                params.append('--keepaspect-window=no')
                if sys.platform == 'darwin':
                    params.append('--vo=gpu')

            ontop = Setting.get(SettingProperty.PlayerOntop,
                                default=SettingProperty.PlayerOntop_True.value)
            if ontop:
                params.append('--ontop')

            # set player position
            player_position = Setting.get(SettingProperty.PlayerPosition,
                                          default=SettingProperty.PlayerPosition_RightTop.value)
            player_position_data = [[2, 5], [2, 98], [98, 5], [98, 98], [50, 50]]
            x = player_position_data[player_position][0]
            y = player_position_data[player_position][1]
            params.append('--geometry={}%:{}%'.format(x, y))

            # set lua scripts
            scripts_path = Setting.get_base_path('scripts')
            if os.path.exists(scripts_path):
                has_modernz = os.path.exists(os.path.join(scripts_path, 'modernz.lua'))
                has_uosc = os.path.exists(os.path.join(scripts_path, 'uosc', 'main.lua'))

                if has_modernz:
                    # Use ModernZ OSC — beautiful modern OSC from GitHub (Samillion/ModernZ)
                    params.append('--osc=no')
                    params.append('--osd-bar=no')
                    modernz_lang = 'zh-hans' if Setting.get_locale().lower().startswith('zh') else 'default'
                    params.append('--script-opts='
                                  f'modernz-language={modernz_lang},'
                                  'modernz-layout=compact,'
                                  'modernz-icon_theme=fluent,'
                                  'modernz-icon_style=mixed,'
                                  'modernz-hidetimeout=3000,'
                                  'modernz-fadeduration=150,'
                                  'modernz-fadein=yes,'
                                  'modernz-playlist_prev_mbtn_left_command=script-message macast-prev,'
                                  'modernz-playlist_next_mbtn_left_command=script-message macast-next,'
                                  'modernz-deadzonesize=0.5,'
                                  'modernz-visibility=auto,'
                                  'modernz-osc_color=#0D0D0D,'
                                  'modernz-seekbarfg_color=#00AEEC,'
                                  'modernz-seekbarbg_color=#404040,'
                                  'modernz-seek_handle_color=#00AEEC,'
                                  'modernz-seek_handle_border_color=#FFFFFF,'
                                  'modernz-hover_effect_color=#00AEEC,'
                                  'modernz-nibble_color=#00AEEC,'
                                  'modernz-nibble_current_color=#FFFFFF,'
                                  'modernz-playpause_color=#FFFFFF,'
                                  'modernz-middle_buttons_color=#FFFFFF,'
                                  'modernz-side_buttons_color=#AAAAAA,'
                                  'modernz-time_color=#FFFFFF,'
                                  'modernz-title_color=#FFFFFF,'
                                  'modernz-seekbar_height=medium,'
                                  'modernz-seek_handle_size=1.06,'
                                  'modernz-playpause_size=38,'
                                  'modernz-midbuttons_size=28,'
                                  'modernz-sidebuttons_size=25,'
                                  'modernz-time_font_size=18,'
                                  'modernz-title_font_size=28,'
                                  'modernz-osc_height=81,'
                                  'modernz-osc_fade_strength=85,'
                                  'modernz-show_title=no,'
                                  'modernz-window_top_bar=no,'
                                  'modernz-window_controls=no,'
                                  'modernz-subtitles_button=no,'
                                  'modernz-audio_tracks_button=no,'
                                  'modernz-screenshot_button=no,'
                                  'modernz-download_button=no,'
                                  'modernz-info_button=no,'
                                  'modernz-ontop_button=no,'
                                  'modernz-loop_button=no,'
                                  'modernz-shuffle_button=no,'
                                  'modernz-speed_button=no,'
                                  'modernz-jump_buttons=no,'
                                  'modernz-chapter_skip_buttons=no,'
                                  'modernz-playlist_button=no,'
                                  'modernz-track_nextprev_buttons=yes,'
                                  'modernz-volume_control=yes,'
                                  'modernz-fullscreen_button=yes,'
                                  'modernz-persistent_progress=no,'
                                  'modernz-osc_on_start=no,'
                                  'modernz-showonpause=yes,'
                                  'modernz-keeponpause=bottombar,'
                                  'modernz-tick_delay=0.016,'
                                  'modernz-tick_delay_follow_display_fps=yes,'
                                  'modernz-slider_rounded_corners=yes,'
                                  'modernz-hover_effect="size,color"')
                elif has_uosc:
                    params.append('--osc=no')
                    params.append('--osd-bar=no')
                    params.append('--script-opts='
                                  'uosc-controls=[play-pause,command:skip_previous:script-binding click_binding/prev?Previous Video,command:skip_next:script-binding click_binding/next?Next Video,cycle:volume_up:mute:no/yes=volume_off!?Mute,space,cycle:fullscreen:fullscreen:no/yes=fullscreen_exit!?Fullscreen],'
                                  'uosc-timeline_style=line,'
                                  'uosc-timeline_size=36,'
                                  'uosc-autohide=no,'
                                  'uosc-flash_duration=3000,'
                                  'uosc-color=[foreground=00aeec,foreground_text=ffffff,background=181818],'
                                  'uosc-opacity=[timeline=1,controls=0,top_bar=0]')
                for f in os.listdir(scripts_path):
                    path = os.path.join(scripts_path, f)
                    # Skip modernz-locale.json (not a lua script)
                    if os.path.isfile(path) and f.endswith('.lua'):
                        params.append('--script={}'.format(path))
                    elif os.path.isdir(path) and os.path.exists(os.path.join(path, 'main.lua')):
                        if not (has_modernz and f == 'uosc'):  # skip uosc dir when using modernz
                            params.append('--script={}'.format(path))


            # set fonts directory
            fonts_path = Setting.get_base_path('fonts')
            if os.path.exists(fonts_path):
                params.append('--sub-fonts-dir={}'.format(fonts_path))

            # set player size
            player_size = Setting.get(SettingProperty.PlayerSize,
                                      default=SettingProperty.PlayerSize_Normal.value)
            if player_size <= SettingProperty.PlayerSize_Large.value:
                params.append('--autofit={}%'.format(
                    int(15 - 2.5 * player_size + 7.5 * player_size ** 2)))
            elif player_size == SettingProperty.PlayerSize_Auto.value:
                params.append('--autofit-larger=90%')
            elif player_size == SettingProperty.PlayerSize_FullScreen.value:
                params.append('--fullscreen')

            # set darwin only options
            if sys.platform == 'darwin':
                params += [
                    '--ontop-level=system',
                    '--on-all-workspaces',
                    '--macos-app-activation-policy=accessory',
                ]

            # set hardware
            hw = Setting.get(SettingProperty.PlayerHW,
                             default=SettingProperty.PlayerHW_Enable.value)
            if hw == SettingProperty.PlayerHW_Disable.value:
                params.remove('--hwdec=yes')
            elif hw == SettingProperty.PlayerHW_Force.value:
                params.append('--macos-force-dedicated-gpu=yes')

            # start mpv
            logger.info("mpv starting with params: {}".format(params))
            cherrypy.engine.publish('mpv_start')
            try:
                def log_stderr(pipe):
                    try:
                        with pipe:
                            for line in iter(pipe.readline, b''):
                                logger.error("mpv stderr: {}".format(line.decode(errors='replace').strip()))
                    except Exception as e:
                        logger.error("log_stderr error: {}".format(e))

                self.proc = subprocess.Popen(
                    params,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    stdin=subprocess.PIPE,
                    env=Setting.get_system_env())
                
                t = threading.Thread(target=log_stderr, args=(self.proc.stderr,), daemon=True)
                t.start()
                self.proc.wait()
            except Exception as e:
                logger.error(e)
            logger.info("mpv stopped")
            if self.running and not self.ipc_once_connected:
                # There should be a problem with the MPV startup parameters
                time.sleep(1)
                error_time -= 1
                logger.error("mpv restarting")
        if error_time <= 0:
            # some thing wrong with mpv
            cherrypy.engine.publish("app_notify", "Macast", "MPV Can't start")
            logger.error("mpv cannot start")
            threading.Thread(target=lambda: Setting.stop_service(), name="MPV_STOP_SERVICE").start()

    def start(self):
        """Start mpv and mpv ipc
        """
        super(MPVRenderer, self).start()
        logger.info("starting mpv and mpv ipc")
        self.mpv_thread = threading.Thread(target=self.start_mpv, name="MPV_THREAD")
        self.mpv_thread.start()
        self.ipc_thread = threading.Thread(target=self.start_ipc, name="MPV_IPC_THREAD")
        self.ipc_thread.start()

    def stop(self):
        """Stop mpv and mpv ipc
        """
        super(MPVRenderer, self).stop()
        logger.info("stoping mpv and mpv ipc")
        # stop mpv
        self.send_command(['quit'])
        if self.proc is not None:
            self.proc.terminate()
        try:
            os.waitpid(-1, 1)
        except Exception as e:
            logger.error(e)
        self.mpv_thread.join()
        # stop mpv ipc
        self.ipc_running = False
        self.ipc_thread.join()

    def reload(self):
        """Reload MPV
        If the MPV is playing content before reloading the player,
        then continue playing the previous content after the reload
        """
        uri = self.protocol.get_state_url()

        def loadfile():
            logger.debug("mpv loadfile")
            protocols = cherrypy.engine.publish('get_protocol')
            if len(protocols) > 0:
                protocol = protocols.pop()
                position = protocol.get_state_position()
                if self.mpv_version_newer:
                    self.send_command(['loadfile', uri, 'replace', -1, f'start={position}'])
                else:
                    self.send_command(['loadfile', uri, 'replace', f'start={position}'])
            else:
                self.send_command(['loadfile', uri, 'replace'])
            self.send_command(['set_property', 'title', self.title])
            cherrypy.engine.unsubscribe('mpvipc_start', loadfile)

        def restart():
            self.stop()
            self.start()

        if self.protocol.get_state_transport_state() == 'PLAYING':
            cherrypy.engine.subscribe('mpvipc_start', loadfile)

        threading.Thread(target=restart, args=()).start()


class SettingProperty(Enum):
    PlayerHW = 100
    PlayerHW_Disable = 0
    PlayerHW_Enable = 1
    PlayerHW_Force = 2

    PlayerSize = 200
    PlayerSize_Small = 0
    PlayerSize_Normal = 1
    PlayerSize_Large = 2
    PlayerSize_Auto = 3
    PlayerSize_FullScreen = 4

    PlayerPosition = 300
    PlayerPosition_LeftTop = 0
    PlayerPosition_LeftBottom = 1
    PlayerPosition_RightTop = 2
    PlayerPosition_RightBottom = 3
    PlayerPosition_Center = 4

    PlayerOntop = 400
    PlayerOntop_False = 0
    PlayerOntop_True = 1

    PlayerDefaultVolume = 500

    PlayerLockSize = 600
    PlayerLockSize_False = 0
    PlayerLockSize_True = 1


class MPVRendererSetting(RendererSetting):
    def __init__(self):
        self.playerPositionItem = None
        self.playerSizeItem = None
        self.playerHWItem = None
        self.playerLockSizeItem = None
        Setting.load()
        self.setting_player_size = Setting.get(SettingProperty.PlayerSize,
                                               SettingProperty.PlayerSize_Normal.value)
        self.setting_player_position = Setting.get(SettingProperty.PlayerPosition,
                                                   SettingProperty.PlayerPosition_RightTop.value)
        self.setting_player_hw = Setting.get(SettingProperty.PlayerHW,
                                             SettingProperty.PlayerHW_Enable.value)
        self.setting_player_ontop = Setting.get(SettingProperty.PlayerOntop,
                                                SettingProperty.PlayerOntop_True.value)
        self.setting_player_lock_size = Setting.get(SettingProperty.PlayerLockSize,
                                                    SettingProperty.PlayerLockSize_False.value)

    def build_menu(self):
        self.playerPositionItem = MenuItem(_("Player Position"),
                                           children=App.build_menu_item_group([
                                               _("LeftTop"),
                                               _("LeftBottom"),
                                               _("RightTop"),
                                               _("RightBottom"),
                                               _("Center")
                                           ], self.on_renderer_position_clicked))
        self.playerSizeItem = MenuItem(_("Player Size"),
                                       children=App.build_menu_item_group([
                                           _("Small"),
                                           _("Normal"),
                                           _("Large"),
                                           _("Auto"),
                                           _("Fullscreen")
                                       ], self.on_renderer_size_clicked))
        self.playerOntopItem = MenuItem(_("Player Ontop"), self.on_renderer_ontop_clicked)

        lock_size_title = _("Lock Player Size")
        if lock_size_title == "Lock Player Size" and Setting.get_locale().lower().startswith('zh'):
            lock_size_title = "固定播放器大小"
        self.playerLockSizeItem = MenuItem(lock_size_title, self.on_renderer_lock_size_clicked)

        has_dedicated_gpu = False
        # Force dedicated GPU only works on MacOS
        if sys.platform == 'darwin':
            try:
                res, gpu_info = Setting.system_shell(
                    ['system_profiler', '-json', '-timeout', '10', 'SPDisplaysDataType'])
                if res == 0:
                    gpu_info = json.loads(gpu_info)
                    has_dedicated_gpu = len(gpu_info['SPDisplaysDataType']) > 1
                    logger.error("GPU list:")
                    for gpu in gpu_info['SPDisplaysDataType']:
                        logger.error('GPU:' + gpu['sppci_model'])
            except Exception as e:
                logger.error("Error get gpu info")

        if has_dedicated_gpu:
            self.playerHWItem = MenuItem(_("Hardware Decode"),
                                         children=App.build_menu_item_group([
                                             _("Hardware Decode"),
                                             _("Force Dedicated GPU")
                                         ], self.on_renderer_hw_clicked))
            if self.setting_player_hw == SettingProperty.PlayerHW_Disable.value:
                self.playerHWItem.items()[1].enabled = False
            else:
                self.playerHWItem.items()[0].checked = True
            self.playerHWItem.items()[1].checked = (
                    self.setting_player_hw == SettingProperty.PlayerHW_Force.value)
        else:
            self.playerHWItem = MenuItem(_("Hardware Decode"),
                                         self.on_renderer_hw_toggled)
            if self.setting_player_hw != SettingProperty.PlayerHW_Disable:
                self.playerHWItem.checked = True
        self.playerPositionItem.items()[self.setting_player_position].checked = True
        self.playerSizeItem.items()[self.setting_player_size].checked = True
        self.playerOntopItem.checked = True if self.setting_player_ontop == 1 else False
        self.playerLockSizeItem.checked = True if self.setting_player_lock_size == 1 else False

        return [
            MenuItem(_("Player Settings"), enabled=False),
            self.playerPositionItem,
            self.playerSizeItem,
            self.playerHWItem,
            self.playerOntopItem,
            self.playerLockSizeItem,
        ]

    def reloadPlayer(self):
        cherrypy.engine.publish('app_notify',
                                _("Reload Player"),
                                _("please wait"),
                                sound=False)
        cherrypy.engine.publish('reload_renderer')

    def on_renderer_ontop_clicked(self, item):
        item.checked = not item.checked
        Setting.set(SettingProperty.PlayerOntop, 1 if item.checked else 0)
        self.reloadPlayer()

    def on_renderer_position_clicked(self, item):
        for i in self.playerPositionItem.items():
            i.checked = False
        item.checked = True
        Setting.set(SettingProperty.PlayerPosition, item.data)
        self.reloadPlayer()

    def on_renderer_hw_toggled(self, item):
        item.checked = not item.checked
        Setting.set(SettingProperty.PlayerHW, 1 if item.checked else 0)
        self.reloadPlayer()

    def on_renderer_hw_clicked(self, item):
        item.checked = not item.checked
        if item.data == 0:
            # click Hardware Decode
            if item.checked:
                # Change to Default Hardware Decode
                Setting.set(SettingProperty.PlayerHW, SettingProperty.PlayerHW_Enable.value)
                self.playerHWItem.items()[1].enabled = True
            else:
                # Change to Software Decode
                Setting.set(SettingProperty.PlayerHW, SettingProperty.PlayerHW_Disable.value)
                self.playerHWItem.items()[1].checked = False
                self.playerHWItem.items()[1].enabled = False
        else:
            # click Force Dedicated GPU Decode
            if item.checked:
                # Change to Force Dedicated GPU Decode
                Setting.set(SettingProperty.PlayerHW, SettingProperty.PlayerHW_Force.value)
            else:
                # Change to Default Hardware Decode
                Setting.set(SettingProperty.PlayerHW, SettingProperty.PlayerHW_Enable.value)
        self.reloadPlayer()

    def on_renderer_size_clicked(self, item):
        for i in self.playerSizeItem.items():
            i.checked = False
        item.checked = True
        Setting.set(SettingProperty.PlayerSize, item.data)
        if item.data == SettingProperty.PlayerSize_Auto.value:
            # set player position to center
            for i in self.playerPositionItem.items():
                i.checked = False
            self.playerPositionItem.items()[4].checked = True
            Setting.set(SettingProperty.PlayerPosition, SettingProperty.PlayerPosition_Center.value)
        self.reloadPlayer()
