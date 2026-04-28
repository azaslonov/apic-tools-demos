# ADO URL Patterns

Reference for parsing Azure DevOps pipeline and test result URLs.

## Pipeline Result URLs

### Standard Format
```
https://dev.azure.com/msazure/One/_build/results?buildId={buildId}&view=results
```

### Legacy Format
```
https://msazure.visualstudio.com/One/_build/results?buildId={buildId}
```

### URL Parameters
| Parameter | Description |
|-----------|-------------|
| `buildId` | Unique build identifier (integer) |
| `view` | View type: `results`, `logs`, `artifacts` |

## Test Results URLs

### Test Results Tab
```
https://dev.azure.com/msazure/One/_build/results?buildId={buildId}&view=ms.vss-test-web.build-test-results-tab
```

### Specific Test Result
```
https://dev.azure.com/msazure/One/_build/results?buildId={buildId}&view=ms.vss-test-web.build-test-results-tab&runId={runId}&resultId={resultId}
```

### Test Attachments
```
https://dev.azure.com/msazure/One/_build/results?buildId={buildId}&view=ms.vss-test-web.build-test-results-tab&runId={runId}&resultId={resultId}&paneView=attachments
```

## Extraction Patterns

### Extract buildId
```python
import re

def extract_build_id(url):
    match = re.search(r'buildId=(\d+)', url)
    return int(match.group(1)) if match else None
```

### Extract runId and resultId
```python
def extract_test_ids(url):
    run_match = re.search(r'runId=(\d+)', url)
    result_match = re.search(r'resultId=(\d+)', url)
    return {
        'runId': int(run_match.group(1)) if run_match else None,
        'resultId': int(result_match.group(1)) if result_match else None
    }
```

## ADO MCP Tool Mapping

| URL Type | MCP Tool |
|----------|----------|
| Build results | `ado-pipelines_get_build_status` |
| Build logs | `ado-pipelines_get_build_log` |
| Test results | `ado-testplan_show_test_results_from_build_id` |

## Known API Limitations

### Test Results API Returns Minimal Data

The `ado-testplan_show_test_results_from_build_id` tool returns limited information:
- Returns `testCaseReferenceId` but NOT test names in batch results
- Test names must be extracted from **build logs**, not the test results API

**Workaround**: Use `ado-pipelines_get_build_log` to retrieve test execution logs, then extract test names from log content patterns like:
- `Failed: TestNamespace.TestClass.TestMethod`
- `Re-running the failed test(s)`
- Error stack traces containing test method names

### Build Log Structure

Test-related logs are typically split across multiple log IDs. Look for:
- Test execution output (contains passed/failed test names)
- Retry markers ("Re-running the failed test(s)")
- Error summaries with stack traces

## Common Projects

| Project | Description |
|---------|-------------|
| `One` | Main APIM project |

## Build Definition IDs

| Pipeline | Definition ID |
|----------|--------------|
| Main CI | 292578 |
