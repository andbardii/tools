"""Exercise the compiled application with an isolated SQLite database."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='privacy-helper-test-') as directory:
    env = {**os.environ, 'PORT': '3137', 'DATA_DIR': directory,
           'LOG_DIR': directory + '/logs', 'BACKUP_DIR': directory + '/backups',
           'DB_BACKUP_ENABLED': 'false'}
    process = subprocess.Popen(['node', 'src/server/dist/server/index.js'], cwd=root,
                               env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def request(path, body=None, method='GET'):
        req = urllib.request.Request('http://127.0.0.1:3137' + path,
              data=json.dumps(body).encode() if body is not None else None,
              headers={'Content-Type': 'application/json'}, method=method)
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.read()

    try:
        for attempt in range(50):
            if process.poll() is not None:
                raise RuntimeError(process.stdout.read().decode())
            try:
                request('/api/health')
                break
            except urllib.error.URLError:
                time.sleep(.1)
        html = request('/').decode()
        asset = re.search(r'src="(/assets/[^\"]+\.js)"', html).group(1)
        assert len(request(asset)) > 1000
        assert b'<html' in request('/requests')
        assert json.loads(request('/api/brokers'))
        assert isinstance(json.loads(request('/api/brokers/search', {'email': 'test@example.com'}, 'POST')), list)
        item = json.loads(request('/api/requests', {'brokerName': 'Test Broker', 'userEmail': 'test@example.com', 'status': 'pending'}, 'POST'))
        assert json.loads(request('/api/requests/' + item['id'], {'status': 'completed'}, 'PUT'))['status'] == 'completed'
        try:
            request('/api/requests/999999', {'status': 'completed'}, 'PUT')
            raise AssertionError('Missing request should return 404')
        except urllib.error.HTTPError as error:
            assert error.code == 404
        try:
            request('/api/requests/' + item['id'], {'unexpectedColumn': 'bad'}, 'PUT')
            raise AssertionError('Unknown fields should return 400')
        except urllib.error.HTTPError as error:
            assert error.code == 400
        request('/api/requests/' + item['id'], method='DELETE')
        assert json.loads(request('/api/requests')) == []
        request('/api/settings/delete-all-data', {}, 'POST')
        assert json.loads(request('/api/requests')) == []
        request('/api/requests', {'brokerName': 'After clear', 'userEmail': 'test@example.com', 'status': 'pending'}, 'POST')
        assert len(json.loads(request('/api/requests'))) == 1
        print('PASS: health, frontend, JS asset, SPA route, broker search, request CRUD, validation')
    finally:
        process.terminate()
        output = process.communicate(timeout=5)[0].decode()
        if process.returncode not in (0, -15):
            print(output)
