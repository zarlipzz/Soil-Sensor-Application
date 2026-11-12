
# Terminal Workflow Rules

## Execution
- Use PowerShell on Windows.
- Execute commands in the project workspace.
- Run one foreground command at a time.
- Wait for completion before starting dependent commands.
- Capture stdout, stderr and exit code.
- Never assume a command succeeded without checking its exit code.

## Process Management
- Never launch duplicate Flutter commands.
- Check existing processes before retrying.
- Do not start another analyze/build/test while the same task is running.
- Avoid unnecessary background processes.
- If a process hangs, inspect it and report the cause.
- Do not kill unrelated user processes.

## Flutter Validation
- Run flutter analyze once after code changes.
- Fix actionable errors before proceeding.
- Run relevant tests after fixing errors.
- Run flutter build apk --debug only when needed.
- Do not repeatedly execute commands that produce identical failures.

## Error Recovery
1. Capture the complete error.
2. Identify the root cause.
3. Inspect relevant source files.
4. Make the smallest necessary change.
5. Run the affected validation again.
6. Stop after repeated identical failures and report the blocker.

## Completion Report
Always report:
- Files modified
- Commands executed
- Exit codes
- Analyze/test/build results
- Remaining errors
- Any manual action required

Never claim success without verification.
