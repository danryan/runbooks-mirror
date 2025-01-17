// For more information on how to configure options, consult
// https://gitlab.com/gitlab-com/runbooks/-/blob/master/reference-architectures/README.md.
{
  elasticacheMonitoring: false,
  minimumSamplesForMonitoring: 3600,
  rdsMonitoring: false,
  rdsInstanceRAMBytes: null,
  rdsMaxAllocatedStorageGB: null,

  // set useGitlabSSHD to true to enable monitoring of gitlab-sshd instead of
  // the legacy gitlab-shell approach.
  useGitlabSSHD: false,
}
