"""Exercise failure and restore boundaries using a fake Docker CLI and real archives."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class UpgradeToolsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'checkout'
        (self.root / 'scripts').mkdir(parents=True)
        self.data = Path(self.tmp.name) / 'external data'
        (self.data / 'tls').mkdir(parents=True)
        (self.data / 'tls/key').write_text('disposable-test-key')
        (self.data / 'db').mkdir()
        (self.data / 'db/live').write_text('must not be archived')
        (self.root / 'configs').mkdir()
        (self.root / 'configs/config').write_text('retained')
        (self.root / '.env').write_text('DATA_ROOT="' + str(self.data) + '"\n')
        for name in ['backup.sh', 'update.sh']:
            shutil.copy(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        bins = Path(self.tmp.name) / 'bin'
        bins.mkdir()
        docker = bins / 'docker'
        docker.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['CALLS'],'a') as f:f.write(json.dumps(args)+'\\n')
if args[:2]==['compose','config'] and '--format' in args:
 print(json.dumps({'services':{'init':{'volumes':[{'target':'/data','source':os.environ['DATA_PATH']}]}}}))
elif args[:2]==['compose','ps']:
 if '--status' in args:
  if os.environ.get('DB_RUNNING')=='1':print('db.openelis.org\\noe.openelis.org')
 else: print('old-container')
elif 'pg_dump' in args:sys.stdout.write('dump'+'.'*2048)
elif args[:2]==['compose','start'] and os.environ.get('START_FAIL')=='1':sys.exit(1)
elif args[:1]==['inspect']:
 text=args[args.index('-f')+1]
 print('healthy' if 'State.Health' in text else 'oe.openelis.org' if 'Labels' in text else 'old/image:release' if 'Config.Image' in text else 'sha256:original')
''')
        docker.chmod(0o755)
        identity=bins/'id';identity.write_text('#!/bin/sh\necho 0\n');identity.chmod(0o755)
        self.env={**os.environ,'PATH':str(bins)+os.pathsep+os.environ['PATH'], 'CALLS':str(Path(self.tmp.name)/'calls'), 'DATA_PATH':str(self.data),'DB_RUNNING':'1'}

    def run_tool(self,name,*args):
        return subprocess.run(['bash',str(self.root/'scripts'/name),*args],cwd=self.root,env=self.env,capture_output=True,text=True)

    def calls(self):
        return [json.loads(x) for x in Path(self.env['CALLS']).read_text().splitlines()]

    def test_update_refuses_missing_database_before_pull(self):
        self.env['DB_RUNNING']='0'
        result=self.run_tool('update.sh','--no-git')
        self.assertNotEqual(0,result.returncode)
        self.assertFalse(any(x[:2]==['compose','pull'] for x in self.calls()))
        self.assertFalse(any(x[:2]==['compose','up'] for x in self.calls()))

    def test_update_records_actual_container_image_and_retains_unselected_services(self):
        result=self.run_tool('update.sh','--no-git')
        self.assertEqual(0,result.returncode,result.stderr)
        recorded=next((self.root/'backups').glob('*/images-before.txt')).read_text()
        self.assertEqual('oe.openelis.org old/image:release sha256:original\n',recorded)
        self.assertFalse(any('--remove-orphans' in x for x in self.calls()))

    @unittest.skipUnless(os.uname().sysname=='Linux','uses Linux backup tools')
    def test_absolute_data_root_restores_without_nested_host_paths(self):
        result=self.run_tool('backup.sh')
        self.assertEqual(0,result.returncode,result.stderr)
        backup=next((self.root/'backups').iterdir())
        self.assertEqual(0o700,stat.S_IMODE(backup.stat().st_mode))
        for file in backup.iterdir():self.assertEqual(0,file.stat().st_mode & 0o077,file.name)
        dest=Path(self.tmp.name)/'restored';dest.mkdir()
        subprocess.run(['tar','-xzf',str(backup/'data.tar.gz'),'-C',str(dest)],check=True)
        self.assertEqual('disposable-test-key',(dest/'tls/key').read_text())
        self.assertFalse((dest/'db').exists())
        dump=next(x for x in self.calls() if 'pg_dump' in x)
        self.assertNotIn('--no-owner',dump)
        self.assertIn(['compose','stop','oe.openelis.org'],self.calls())
        self.assertIn(['compose','start','oe.openelis.org'],self.calls())
        subprocess.run(['sha256sum','-c','SHA256SUMS'],cwd=backup,check=True,capture_output=True)

    @unittest.skipUnless(os.uname().sysname=='Linux','uses Linux backup tools')
    def test_failed_archive_remains_private_and_resumes_writers(self):
        shutil.rmtree(self.root/'configs')
        result=self.run_tool('backup.sh')
        self.assertNotEqual(0,result.returncode)
        backup=next((self.root/'backups').iterdir())
        self.assertEqual(0o700,stat.S_IMODE(backup.stat().st_mode))
        self.assertFalse((backup/'SHA256SUMS').exists())
        self.assertIn(['compose','start','oe.openelis.org'],self.calls())
