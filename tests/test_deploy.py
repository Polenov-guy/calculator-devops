"""Exercise release state transitions without a Docker daemon or remote server."""
import os,pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
GOOD='ghcr.io/example/calculator@sha256:'+'a'*64
BAD='ghcr.io/example/calculator@sha256:'+'b'*64
class DeploymentTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.home=pathlib.Path(self.temp.name);self.bin=self.home/'bin';self.bin.mkdir();(self.home/'.state').mkdir();(self.home/'.env').write_text('GRAFANA_ADMIN_PASSWORD=test\n');self.log=self.home/'docker.log'
  docker=self.bin/'docker';docker.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$FAKE_LOG"
if [[ "$1" == pull ]]; then exit 0; fi
if [[ "$*" == *" port app "* ]]; then echo '0.0.0.0:80'; exit 0; fi
if [[ "$*" == *" up -d "* ]] && grep -q 'bbbbbbbb' "$APP_HOME/.deploy.env"; then exit 42; fi
exit 0
''');docker.chmod(0o755)
  py=self.bin/'python3';py.write_text('#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n');py.chmod(0o755)
  self.env=dict(os.environ,APP_HOME=str(self.home),FAKE_LOG=str(self.log),PATH=str(self.bin)+':'+os.environ['PATH'])
 def tearDown(self):self.temp.cleanup()
 def release(self,name):
  p=self.home/name;shutil.copytree(ROOT/'scripts',p/'scripts');shutil.copy(ROOT/'compose.yaml',p/'compose.yaml');return p
 def run_deploy(self,p,image):return subprocess.run(['bash',str(p/'scripts/deploy.sh'),image,'a'*40],env=self.env,capture_output=True,text=True)
 def test_success_records_release(self):
  p=self.release('new');r=self.run_deploy(p,GOOD);self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertEqual((self.home/'.state/current-release').read_text().strip(),str(p));self.assertIn(GOOD,(self.home/'.deploy.env').read_text())
 def test_failed_upgrade_restores_image_and_config(self):
  old=self.release('old');new=self.release('new');(self.home/'.state/current-release').write_text(str(old)+'\n');(self.home/'.deploy.env').write_text('APP_IMAGE='+GOOD+'\n');r=self.run_deploy(new,BAD);self.assertNotEqual(r.returncode,0);self.assertIn(GOOD,(self.home/'.deploy.env').read_text());self.assertEqual((self.home/'.state/current-release').read_text().strip(),str(old));self.assertIn(str(old/'compose.yaml'),self.log.read_text())
 def test_failed_first_deploy_is_not_recorded_as_success(self):
  p=self.release('first');r=self.run_deploy(p,BAD);self.assertNotEqual(r.returncode,0);self.assertFalse((self.home/'.state/current-release').exists());self.assertIn('stop app',self.log.read_text())
 def test_mutable_image_rejected(self):
  p=self.release('new');r=self.run_deploy(p,'ghcr.io/example/calculator:latest');self.assertNotEqual(r.returncode,0);self.assertFalse(self.log.exists())
if __name__=='__main__':unittest.main(verbosity=2)
