#!/bin/bash --login

HOSTNAME=$(hostname)

function getCobaltEnv() {
  VARS=$(env | grep COBALT)
}

function getPBSEnv() {
  VARS=$(env | grep PBS)
}

function getSlurmEnv() {
  VARS=$(env | grep SLURM)
}


function saveSlurmEnv() {
  outfile="~/.slurmjob"
  echo "Saving SLURM_* to ~/.slurmjob"
  echo "${VARS[*]}" > ~/.slurmjob
  sed -i 's/^SLURM/export\ SLURM/g' ~/.slurmjob
  sed -i 's/(x2)//g' ~/.slurmjob
}

function saveCobaltEnv() {
  getCobaltEnv
  outfile="~/.cobaltjob"
  echo "Saving COBALT_* to ~/.cobaltjob"
  echo "${VARS[*]}" > ~/.cobaltjob
  sed -i 's/^COBALT/export\ COBALT/g' ~/.cobaltjob
  # sed -i 's/()'
}


getCOBALT_NODEFILE() {
  RUNNING_JOB_FILE="/var/tmp/cobalt-running-job"
  if [[ -f "$RUNNING_JOB_FILE" ]]; then
    JOBID=$(sed "s/:$USER//" /var/tmp/cobalt-running-job)
    COBALT_NODEFILE="/var/tmp/cobalt.${JOBID}"
    export JOBID="${JOBID}"
    export HOSTFILE="${HOSTFILE}"
    export COBALT_NODEFILE="${COBALT_NODEFILE}"
  fi
}

function savePBSenv() {

  # {
  #   echo "export PBS_ACCOUNT=${PBS_ACCOUNT}"
  #   echo "export PBS_JOBCOOKIE=${PBS_JOBCOOKIE}"
  #   echo "export PBS_JOBID=${PBS_JOBID}"
  #   echo "export PBS_MOMPORT=${PBS_MOMPORT}"
  #   echo "export PBS_NODENUM=${PBS_NODENUM}"
  #   echo "export PBS_O_HOST=${PBS_O_HOST}"
  #   echo "export PBS_O_LOGNAME=${PBS_O_LOGNAME}"
  #   echo "export PBS_O_PATH=${PBS_O_PATH}"
  #   echo "export PBS_O_SHELL=${PBS_O_SHELL}"
  #   echo "export PBS_O_TZ=${PBS_O_TZ}"
  #   echo "export PBS_QUEUE=${PBS_QUEUE}"
  #   echo "export PBS_ENVIRONMENT=${PBS_ENVIRONMENT}"
  #   echo "export PBS_JOBDIR=${PBS_JOBDIR}"
  #   echo "export PBS_JOBNAME=${PBS_JOBNAME}"
  #   echo "export PBS_NODEFILE=${PBS_NODEFILE}"
  #   echo "export PBS_O_HOME=${PBS_O_HOME}"
  #   echo "export PBS_O_LANG=${PBS_O_LANG}"
  #   echo "export PBS_O_MAIL=${PBS_O_MAIL}"
  #   echo "export PBS_O_QUEUE=${PBS_O_QUEUE}"
  #   echo "export PBS_O_SYSTEM=${PBS_O_SYSTEM}"
  #   echo "export PBS_O_WORKDIR=${PBS_O_WORKDIR}"
  #   echo "export PBS_TASKNUM=${PBS_TASKNUM}"
  # } >> "${JOBENV_FILE}}"
}

function envSave() {
  {
    echo "export HOSTFILE=${HOSTFILE}"
    echo "export ${FNAME}=${HOSTFILE}"
    echo "export NHOSTS=${NHOSTS}"
    echo "export NGPU_PER_HOST=${NGPU_PER_HOST}"
    echo "export NGPUS=${NGPUS}"
  } > "${JOBENV_FILE}"
  if [[ "${HOSTNAME}" == x3* ]]; then
    savePBSenv
  fi
}

# getPBSenv() {
#   export FNAME="$P{}"
# }

setup() {
  if [[ "${HOSTNAME}" == x3* ]]; then
    export FNAME="PBS_NODEFILE"
    export HOSTFILE="${PBS_NODEFILE}"
    export JOBENV_FILE="${HOME}/.jobenv-polaris"
    echo "${PBS_NODEFILE}" | rpbcopy
  elif [[ "${HOSTNAME}" == thetagpu* ]]; then
    getCOBALT_NODEFILE
    export FNAME="COBALT_NODEFILE"
    export HOSTFILE="${COBALT_NODEFILE}"
    export JOBENV_FILE="${HOME}/.jobenv-thetaGPU"
    echo "${COBALT_NODEFILE}" | rpbcopy
  fi
  NHOSTS=$(wc -l < "${HOSTFILE}")
  NGPU_PER_HOST=$(nvidia-smi -L | wc -l)
  NGPUS="$((${NHOSTS}*${NGPU_PER_HOST}))"  # noqa
  echo "----------------------------------------------------------------------"
  echo \
    "[DIST INFO]: " \
    "Writing Job info to ${JOBENV_FILE} "
  echo \
    "NHOSTS: $NHOSTS " \
    "NGPU_PER_HOST: $NGPU_PER_HOST " \
    "NGPUS: $NGPUS "
  export NHOSTS="${NHOSTS}"
  export NGPU_PER_HOST="${NGPU_PER_HOST}"
  export NGPUS="${NGPUS}"
  envSave
}


PrintAndCopy() {
  echo "Copying ${FNAME} to clipboard..."
  echo "${FNAME}: ${HOSTFILE}"
  cat "${HOSTFILE}"
  echo "${HOSTFILE}" | rpbcopy
  echo "export ${FNAME}=${HOSTFILE}" | rpbcopy
  echo "----------------------------------------------------------------------"
  echo "Run 'source getjobenv' in a new shell to automatically set env vars"
}

setup
PrintAndCopy
# vim: ft=bash
