import os, pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='qjob-suite-test-') as td:
 p=pathlib.Path(td)
 for d in ['config','user','bin','work','scratch']: (p/d).mkdir()
 (p/'user/qjob.conf').write_text(f"partition=test\nQJOB_MODULE_INIT=''\nstorage=''\nQJOB_STORAGE_GRES=false\nQJOB_SCRATCH_ROOT='{p}/scratch'\nclean_tmp=success\n")
 (p/'env').write_text('module() { echo "$*" >> "$TEST_MODULE_LOG"; }; export -f module\n')
 mock='''#!/bin/bash
printf '%s\\n' "$0" "$@" > invoked.txt
[[ -f aux.dat && -f .hidden ]] || exit 81
[[ $OMP_NUM_THREADS == 1 && $OMP_THREAD_LIMIT == 1 ]] || [[ ${0##*/} == xcfour ]] || exit 82
[[ ! -f fail ]] || exit 37
case ${0##*/} in
xcfour) [[ -f ZMAT && -f GENBAS && $OMP_NUM_THREADS == 2 ]] || exit 83 ;;
dalton) [[ -f water.mol ]] || exit 84 ;;
esac
printf hidden > .restart
printf 'native completion\\n'
'''
 for binary in ['xcfour','molpro','nwchem','pw.x','ph.x','cp2k.psmp','dalton']:
  f=p/'bin'/binary; f.write_text(mock); f.chmod(0o755)
 f=p/'bin/mpirun'; f.write_text('#!/bin/bash\n[[ $1 == -np && $2 == 2 ]] || exit 85\nshift 2\nexec "$@"\n'); f.chmod(0o755)
 work=p/'work'; os.chdir(work)
 for name in ['water.inp','water.dal','water.mol','GENBAS','aux.dat','.hidden']: pathlib.Path(name).write_text('input')
 env=os.environ.copy(); env.update(PATH=str(p/'bin')+':'+env['PATH'],QJOB_CONFIG_DIR=str(p/'config'),QJOB_USER_CONFIG_DIR=str(p/'user'),QJOB_PROFILE='wcss',BASH_ENV=str(p/'env'),TEST_MODULE_LOG=str(p/'modules'))
 for cmd in ['Cfour','Molpro','QuantumEspresso','Nwchem','Dalton','Cp2k']:
  inp='water.dal' if cmd=='Dalton' else 'water.inp'
  args=[str(root/'bin'/cmd),'-c','2','-C','aux.dat .hidden GENBAS']
  debug=subprocess.run(args+['--debug',inp],env=env,capture_output=True,text=True,check=True)
  subprocess.run(['bash','-n'],input=debug.stdout,text=True,check=True)
  assert ('#SBATCH --cpus-per-task=2' if cmd=='Cfour' else '#SBATCH --ntasks-per-node=2') in debug.stdout
  for fail in [False,True]:
   if fail: pathlib.Path('fail').touch()
   runargs=args.copy()
   if fail: runargs[runargs.index('aux.dat .hidden GENBAS')]='aux.dat .hidden GENBAS fail'
   run=subprocess.run(runargs+['--local',inp],env=env,capture_output=True,text=True)
   assert (run.returncode!=0)==fail, (cmd,run.stdout,run.stderr)
   dirs=list(work.glob('water-qjob-*')); assert len(dirs)==1
   result=dirs[0]; assert (result/'stderr.log').exists() and (result/'stdout.log').exists()
   if not fail: assert (result/'.restart').exists()
   if fail: assert 'exit status 37' in run.stderr and list((p/'scratch').iterdir()), (cmd, run.stderr)
   import shutil
   shutil.rmtree(result)
   if fail:
    pathlib.Path('fail').unlink()
    for d in (p/'scratch').iterdir(): shutil.rmtree(d)
  bad=subprocess.run(args+['--debug','-n','2',inp],env=env,capture_output=True); assert bad.returncode
  print('PASS',cmd,'allocation, staging, logs, hidden results, native failure, scratch retention, node limit')
 subprocess.run([str(root/'bin/QuantumEspresso'),'--local','--program','ph.x','-c','2','-C','aux.dat .hidden','water.inp'],env=env,check=True,capture_output=True)
 assert 'ph.x' in next(work.glob('water-qjob-*')).joinpath('invoked.txt').read_text()
 print('PASS QuantumEspresso --program ph.x')
