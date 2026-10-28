import select, base64, hashlib, json, os, shutil, signal, socket, struct, subprocess, sys, tempfile, threading, time
from importlib.machinery import SourceFileLoader
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "obs-status-guard")
guard = SourceFileLoader("guard", D).load_module()
PASSWORD, SALT, CHAL = "pw", "saltsalt", "challenge"

def frame(text, op=1):
    p = text.encode(); n = len(p)
    h = bytes([0x80 | op]) + (bytes([n]) if n < 126 else bytes([126]) + struct.pack(">H", n))
    return h + p                                   # server frames are unmasked

def read_frame(c):
    b0, b1 = c.recv(2); n = b1 & 0x7F
    if n == 126: n = struct.unpack(">H", c.recv(2))[0]
    mask = c.recv(4); data = b""
    while len(data) < n: data += c.recv(n - len(data))
    return json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


class Mock(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.port, self.live, self.dur, self.exit_event, self.auth_ok, self.conn = port, True, 5000, False, None, None
        self.srv = socket.socket(); self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.srv.bind(("127.0.0.1", port)); self.srv.listen(1); self.start()
    def run(self):
        while True:
            try: c, _ = self.srv.accept()
            except OSError: return
            self.conn = c
            try:
                req = b""
                while b"\r\n\r\n" not in req: req += c.recv(4096)
                key = [l.split(b": ")[1] for l in req.split(b"\r\n") if l.lower().startswith(b"sec-websocket-key")][0]
                acc = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
                c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + acc + b"\r\n\r\n")
                c.sendall(frame(json.dumps({"op": 0, "d": {"obsWebSocketVersion": "5.7.4", "rpcVersion": 1, "authentication": {"challenge": CHAL, "salt": SALT}}})))
                ident = read_frame(c)
                self.auth_ok = ident["d"].get("authentication") == guard.obs_auth(PASSWORD, SALT, CHAL)
                c.sendall(frame(json.dumps({"op": 2, "d": {"negotiatedRpcVersion": 1}})))
                while True:
                    m = read_frame(c)
                    if m["op"] == 6:
                        if self.exit_event:
                            c.sendall(frame(json.dumps({"op": 5, "d": {"eventType": "ExitStarted", "eventIntent": 1}})))
                        c.sendall(frame(json.dumps({"op": 7, "d": {"requestType": "GetStreamStatus", "requestId": m["d"]["requestId"],
                            "requestStatus": {"result": True, "code": 100}, "responseData": {"outputActive": self.live, "outputDuration": self.dur}}})))
            except Exception:
                pass
    def drop(self):
        try: self.conn.close()
        except Exception: pass

def setup(auto):
    home = tempfile.mkdtemp(prefix="guard-home-")
    os.makedirs(home + "/.config/omarchy"); os.makedirs(home + "/.config/obs-studio/plugin_config/obs-websocket"); os.makedirs(home + "/bin"); os.makedirs(home + "/run")
    port = 40000 + os.getpid() % 2000
    json.dump({"server_enabled": True, "server_port": port, "server_password": PASSWORD}, open(home + "/.config/obs-studio/plugin_config/obs-websocket/config.json", "w"))
    json.dump({"bar": {"layout": {"right": [{"id": "io.github.borferkic.obs-status-guard", "autoRestart": auto}]}}}, open(home + "/.config/omarchy/shell.json", "w"))
    # fake obs: comm must be "obs"; records its arguments when relaunched
    open(home + "/bin/obs", "w").write("#!/bin/sh\necho \"$@\" > %s/launched\nexec sleep 300\n" % home)
    os.chmod(home + "/bin/obs", 0o755)
    open(home + "/bin/uwsm-app", "w").write("#!/bin/sh\necho \"$@\" > %s/launched\n" % home)
    os.chmod(home + "/bin/uwsm-app", 0o755)
    return home, port

def start_daemon(home):
    env = dict(os.environ, HOME=home, XDG_RUNTIME_DIR=home + "/run", PATH=home + "/bin:/usr/bin:/bin", OBS_STATUS_GUARD_COMM="obsfake",
               XDG_DATA_HOME=home + "/.local/share", XDG_DATA_DIRS=home + "/no-such-dir")
    p = subprocess.Popen([sys.executable, "-I", D, "daemon"], env=env, stdout=subprocess.PIPE, text=True)
    return p

def fake_obs(home):
    # a process whose /proc comm is exactly "obs"
    shutil.copy("/usr/bin/sleep", home + "/obsfake"); return subprocess.Popen([home + "/obsfake", "300"])

def wait_state(p, want, timeout=8):
    end = time.time() + timeout; last = None
    while time.time() < end:
        if not select.select([p.stdout], [], [], 1)[0]: continue
        line = p.stdout.readline()
        if not line: break
        last = json.loads(line)
        if last["state"] == want: return last
    raise AssertionError("never reached %s, last=%s" % (want, last))

def run():
    # 1. live, then abrupt kill -> crashed, then dismissed -> idle
    home, port = setup(False); m = Mock(port); o = fake_obs(home); d = start_daemon(home)
    st = wait_state(d, "live"); assert st["seconds"] == 5, st; assert m.auth_ok is True; print("ok live + auth, seconds =", st["seconds"])
    o.kill(); o.wait(); m.drop()
    st = wait_state(d, "crashed"); assert st["restarting"] is False; print("ok abrupt kill -> crashed")
    assert not os.path.exists(home + "/launched"); print("ok no relaunch while autoRestart is off")
    env = dict(os.environ, HOME=home, XDG_RUNTIME_DIR=home + "/run")
    subprocess.run([sys.executable, "-I", D, "dismiss"], env=env); wait_state(d, "idle"); print("ok dismiss -> idle")
    d.terminate(); d.wait()
    # 2. clean exit (ExitStarted) must not alarm
    home, port = setup(False); m.live, m.exit_event = True, False; m.drop(); o = fake_obs(home); d = start_daemon(home)
    wait_state(d, "live"); m.exit_event = True; time.sleep(1.5); o.kill(); o.wait()
    st = wait_state(d, "idle"); print("ok clean exit -> idle (no crash alarm)")
    d.terminate(); d.wait()
    # 3. stream stopped, OBS still open -> idle
    home, port = setup(False); m.live, m.exit_event = True, False; m.drop(); o = fake_obs(home); d = start_daemon(home)
    wait_state(d, "live"); m.live = False; wait_state(d, "idle"); print("ok stream stopped normally -> idle")
    d.terminate(); d.wait(); o.kill(); o.wait()
    # 4. autoRestart on: crash relaunches obs with the right flags
    home, port = setup(True); m.live, m.exit_event = True, False; m.drop(); o = fake_obs(home); d = start_daemon(home)
    wait_state(d, "live"); o.kill(); o.wait(); m.drop()
    st = wait_state(d, "crashed"); assert st["restarting"] is True, st       # "reopening..." while it waits
    time.sleep(3); assert not os.path.exists(home + "/launched"), "relaunched before the 5 s delay"
    print("ok no relaunch before 5 s")
    time.sleep(4)
    args = open(home + "/launched").read().strip(); assert args == "-- obs --startstreaming", args
    print("ok autoRestart relaunch args:", args)
    d.terminate(); d.wait(); subprocess.run(["pkill", "-f", home + "/obsfake"])
    # 4b. relaunch goes through the user's desktop entry (environment tweaks carry over)
    home, port = setup(True); m.live, m.exit_event = True, False; m.drop(); o = fake_obs(home)
    os.makedirs(home + "/.local/share/applications")
    open(home + "/.local/share/applications/com.obsproject.Studio.desktop", "w").write("[Desktop Entry]\nName=OBS\nExec=env LIBVA_DRIVER_NAME=iHD obs %U\n")
    d = start_daemon(home); wait_state(d, "live"); o.kill(); o.wait(); m.drop()
    wait_state(d, "crashed"); time.sleep(7)
    args = open(home + "/launched").read().strip()
    assert args == "-- env LIBVA_DRIVER_NAME=iHD obs --startstreaming", args
    print("ok relaunch uses the desktop entry Exec:", args)
    d.terminate(); d.wait()
    # 4c. after a relaunch OBS's main window (not its dialogs) goes to the chosen monitor
    home, port = setup(True); m.live, m.exit_event = True, False; m.drop(); o = fake_obs(home)
    cfg = json.load(open(home + "/.config/omarchy/shell.json")); cfg["bar"]["layout"]["right"][0]["obsMonitor"] = "DP-5"
    json.dump(cfg, open(home + "/.config/omarchy/shell.json", "w"))
    mons = [{"name": "HDMI-A-1", "id": 0, "x": 1080, "y": 0, "width": 3840, "height": 2160, "activeWorkspace": {"id": 1}},
            {"name": "DP-5", "id": 1, "x": 0, "y": 0, "width": 1920, "height": 1080, "activeWorkspace": {"id": 7}}]
    clients = [{"class": "com.obsproject.Studio", "title": "Missing Encoders", "address": "0xdead", "monitor": 0},
               {"class": "com.obsproject.Studio", "title": "OBS 33.0.0 (linux)", "address": "0xbeef", "monitor": 0},
               {"class": "com.obsproject.Studio", "title": "OBS 33.0.0 - Profile: x", "address": "0xabc", "monitor": 0}]
    open(home + "/bin/hyprctl", "w").write("#!/bin/sh\ncase \"$1\" in\nmonitors) echo '%s';;\nclients) echo '%s';;\ndispatch) echo \"$@\" >> %s/dispatched;;\nesac\n"
                                           % (json.dumps(mons), json.dumps(clients), home))
    os.chmod(home + "/bin/hyprctl", 0o755)
    os.makedirs(home + "/.config/obs-studio/.sentinel"); open(home + "/.config/obs-studio/.sentinel/run_stale", "w").close()
    d = start_daemon(home); wait_state(d, "live"); o.kill(); o.wait(); m.drop()
    wait_state(d, "crashed"); time.sleep(8)
    assert not os.path.exists(home + "/.config/obs-studio/.sentinel/run_stale"); print("ok stale crash sentinel removed before the relaunch")
    log = open(home + "/dispatched").read().strip().splitlines()
    assert log == ['dispatch hl.dsp.window.move({ workspace = "7", follow = false, window = "address:0xabc" })'], log
    print("ok OBS window moved to DP-5's workspace, dialog left alone, moved once:", log[0])
    d.terminate(); d.wait()
    # 5. monitoring switch: paused -> off (even if OBS dies, no crash alarm); resumed -> live again
    home, port = setup(False); m.live, m.exit_event = True, False; m.drop(); o = fake_obs(home); d = start_daemon(home)
    wait_state(d, "live")
    def set_monitoring(on):
        c = json.load(open(home + "/.config/omarchy/shell.json"))
        c["bar"]["layout"]["right"][0]["monitoring"] = on
        json.dump(c, open(home + "/.config/omarchy/shell.json", "w"))
    set_monitoring(False); wait_state(d, "off"); print("ok monitoring off -> off")
    o.kill(); o.wait(); m.drop(); time.sleep(3)
    assert json.load(open(home + "/run/obs-status-guard/state.json"))["state"] == "off"; print("ok no crash alarm while paused")
    o = fake_obs(home); set_monitoring(True); wait_state(d, "live"); print("ok monitoring back on -> live")
    d.terminate(); d.wait(); o.kill(); o.wait()
    print("ALL PASSED")

run()
