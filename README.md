# TAFFi Test Run GitHub Action

This is a GitHub Action to run tests using TAFFi test automation runner.

The action runs tests with TAFFi using the following high-level steps:

1. Set NO_PROXY environment variable to avoid using proxy for certain communication, for example between TAFFi client and server
    - Action input [`noProxy`](#hostsdomains-not-to-be-proxied-noproxy) can be used to add more items to NO_PROXY
2. Login to verso-docker-dev-local Docker registry in Common Artifactory to be able to download TAFFi Docker images
    - Action inputs [`dockerRegistryUsername`](#username-for-docker-registry-dockerregistryusername) and [`dockerRegistryPassword`](#password-for-docker-registry-dockerregistrypassword) are used for login
3. Setup TAFFi config files
    - Action inputs [`jiraUsername`](#jira-username-jirausername), [`jiraPassword`](#jira-password-jirapassword), [`jiraProject`](#jira-project-jiraproject), [`jiraTestPlan`](#jira-test-plan-jiratestplan), [`testDir`](#test-asset-directory-testdir), [`resultsDir`](#test-result-directory-resultsdir), [`taffiServerTimeout`](#taffi-server-timeout-taffiservertimeout), [`testRunTool`](#test-tool-testruntool), [`testRunOptions`](#tests-run-options-testrunoptions), [`testRunTests`](#tests-to-run-testruntests), [`testRunConfigPath`](#test-toolrun-config-path-testrunconfigpath), [`testRunBaseDir`](#test-case-directory-testrunbasedir) and [`taffiServerCmd`](#taffi-server-command-taffiservercmd) are used for config
4. Set noProxy for Docker config of the runner
5. Run tests using TAFFi and the configs prepared in previous steps based on action input [`realRun`](#really-run-the-tests-realrun)
6. Archive test results as a build artifact
    - Action input resultsDir is used for results archival
    - The artifact name is currently `robot-output`

---
## Action inputs

### Username for Docker registry, `dockerRegistryUsername`
Username to be used to access the Docker registry in Telia Company JFrog Artifactory (verso-docker-dev-local.jfrog.teliacompany.io) for downloading the TAFFi Docker images.
```
Required: false
```

### Password for Docker registry, `dockerRegistryPassword`
Password to be used to access the Docker registry in Telia Company JFrog Artifactory (verso-docker-dev-local.jfrog.teliacompany.io) for downloading the TAFFi Docker images.
```
Required: false
```

### Hosts/domains not to be proxied, `noProxy`
String to be appended to the end of NO_PROXY environment variable.
```
Required: false
```

### Jira project, `jiraProject`
Jira project to which report the results. If not given, no reporting to jira using TAFFi is done.
```
Required: false
```

### Jira test plan, `jiraTestPlan`
Jira test plan to which report the results. If not given, no reporting to jira using TAFFi is done.
```
Required: false
```

### Jira username, `jiraUsername`
Username to be used to access Jira (https://devopsjira.verso.sonera.fi) for reporting test results. Required only if also both jiraProject and jiraTestPlan are provided, and thus test reporting is tried to be done.
```
Required: false
```

### Jira password, `jiraPassword`
Password to be used to access Jira (https://devopsjira.verso.sonera.fi) for reporting test results. Required only if also both jiraProject and jiraTestPlan are provided, and thus test reporting is tried to be done.
```
Required: false
```

### TAFFi server command, `taffiServerCmd`
Command to run before starting TAFFi server. Can be used for example installing some additional libraries etc. on the TAFFi server container before launching tests.
```
Required: false
```

### TAFFi server timeout, `taffiServerTimeout`
Timeout for waiting the TAFFi server to be reachable before starting the test run. During this time for example the command to run before starting TAFFi server (taffiServerCmd) is run.
```
Required: false
Default: 180
Type: number
```

### Test asset directory, `testDir`
Path to a directory below which all the files needed for test run are found from. Path must be relative to workspace directory.
```
Required: false
Default: ''
```

### Test result directory, `resultsDir`
Path to a directory where all the test results will be stored. Path must be relative to workspace directory.
```
Required: false
Default: 'output'
```

### Test tool, `testRunTool`
Test tool to run using TAFFi.
```
Required: false
Default: 'robot'
```

### Test case directory, `testRunBaseDir`
Path to the base directory where all tests to run are found. Must be relative to [`testDir`](#test-asset-directory-testdir) input.
```
Required: false
Default: 'robot/tests'
```

### Test tool/run config path, `testRunConfigPath`
Path to the test configuration file (or directory) (a test tool specific file/directory, for Robot it is an argument file in JSON format, see example from [telia-company/taffi-demo-app](https://github.com/telia-company/taffi-demo-app/blob/main/test/robot/robot.arguments.json) repo). Must be relative to [`testDir`](#test-asset-directory-testdir) input.
```
Required: false
Default: 'robot/tests/robot.arguments.json'
```

### Tests to run, `testRunTests`
List of tests/suites to run as space separated string. Quotes (") need to be escaped with a backslash (\\).
```
Required: false
Default: '.'
```

### Tests run options, `testRunOptions`
Tool specific commandline options to be given for test tool. Quotes (") need to be escaped with a backslash (\\).
```
Required: false
```

### Really run the tests?, `realRun`
Really run the tests or just do all but not the actual TAFFi run?
```
Required: false
Default: true
Type: boolean
```

---
## Example usage in a workflow

Here is an example on how the action can be used. In the example, robot test suites listed in robotTests workflow input would be executed. The default values for many action inputs will be used. Before starting the TAFFi server in the server container, Python dependencies listed in requirements file will be installed. More information about the TAFFi related options, for example paths inside the TAFFi server, can be found for example from [TAFFi Demo App](https://github.com/telia-company/taffi-demo-app) or from [TAFFi Docker run config file documentation](https://github.com/telia-company/taffi/blob/main/example-configs/README.md#taffi-docker-run-configuration)

```
jobs:
  run-robot-tests:
    runs-on: [medium, telia-managed, Linux, X64]
    steps:
      - uses: actions/checkout@v3
        with:
          ref: ${{ inputs.branch }}

      - uses: telia-actions/taffi-test-run@v2
        with:
          testRunTests: ${{ inputs.robotTests }}
          testRunOptions: --xunit xunit_robot.xml -i dashboardAND${{ inputs.testEnv }} ${{ inputs.robotOptions }}
          taffiServerCmd: pip install -r /taffi/tests/cicd/requirements.txt
          dockerRegistryUsername: ${{ secrets.COMMON_ARTIFACTORY_VERSO_READ_USERNAME }}
          dockerRegistryPassword: ${{ secrets.COMMON_ARTIFACTORY_VERSO_READ_PASSWORD }}
          jiraProject: ${{ inputs.jiraProject }}
          jiraTestPlan: ${{ inputs.jiraTestPlan }}
          jiraUsername: ${{ secrets.ARTIFACTORY_USERNAME }}
          jiraPassword: ${{ secrets.ARTIFACTORY_PASSWORD }}
```
