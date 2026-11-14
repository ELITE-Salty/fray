#!/usr/bin/env python3
"""Local-only, same-origin Flutter web + Django runner. Not a production server."""
import argparse
import functools
import http.client
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port', type=int, default=8080)
parser.add_argument('--backend-port', type=int, default=8000)
args = parser.parse_args()
web = ROOT / 'apps/fray/build/web'
if not (web / 'index.html').exists():
    sys.exit('Build the web app first: cd apps/fray && flutter build web --no-web-resources-cdn')
python = ROOT / '.venv/bin/python'
if not python.exists():
    sys.exit('Create .venv and install backend/requirements.txt first; see README.md.')
env = {**os.environ, 'FRAY_DEBUG': '1', 'FRAY_HOSTS': 'localhost,127.0.0.1',
       'FRAY_ORIGINS': f'http://localhost:{args.port},http://127.0.0.1:{args.port}'}
subprocess.run([str(python), 'backend/manage.py', 'migrate', '--noinput'], cwd=ROOT, env=env, check=True)
backend = subprocess.Popen([str(python), 'backend/manage.py', 'runserver', f'127.0.0.1:{args.backend_port}', '--noreload'], cwd=ROOT, env=env)


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/') or self.path == '/metrics':
            self.proxy()
        else:
            super().do_GET()

    def do_POST(self):
        self.proxy()

    do_PATCH = do_POST
    do_DELETE = do_POST

    def proxy(self):
        if not (self.path.startswith('/api/') or self.path == '/metrics'):
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', 0))
        if length > 65536:
            self.send_error(413)
            return
        body = self.rfile.read(length) if length else None
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in ('host', 'connection', 'transfer-encoding', 'x-forwarded-proto')}
        headers['Host'] = f'127.0.0.1:{args.backend_port}'
        connection = http.client.HTTPConnection('127.0.0.1', args.backend_port, timeout=30)
        try:
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in ('connection', 'transfer-encoding', 'server', 'date'):
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(response.read())
        except (BrokenPipeError, ConnectionResetError):
            pass  # The browser closed the connection during a request.
        except OSError:
            self.send_error(502, 'Local backend unavailable')
        finally:
            connection.close()


server = None
try:
    for _ in range(100):
        if backend.poll() is not None:
            sys.exit('Django failed to start. Check the output above.')
        try:
            connection = http.client.HTTPConnection('127.0.0.1', args.backend_port, timeout=1)
            connection.request('GET', '/api/health')
            response = connection.getresponse()
            ready = response.status == 200
            response.read()
            connection.close()
            if ready:
                break
        except OSError:
            pass
        time.sleep(.1)
    else:
        sys.exit('Django did not become healthy in ten seconds.')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), functools.partial(Handler, directory=str(web)))
    print(f'\nFray is ready: http://localhost:{args.port}\nCtrl+C stops both servers.\n', flush=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    if server:
        server.server_close()
    backend.terminate()
    try:
        backend.wait(timeout=5)
    except subprocess.TimeoutExpired:
        backend.kill()
        backend.wait()
