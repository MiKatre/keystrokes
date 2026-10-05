#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

# Swift 6.4 beta CLT omits the Swift Testing macro plugin from its build plan.
task_swift_path="$(xcrun --find swift)"
task_testing_plugin="${task_swift_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
task_test_flags=(--disable-xctest)
if [[ -f "$task_testing_plugin" ]]; then
  task_test_flags+=(-Xswiftc -load-plugin-library -Xswiftc "$task_testing_plugin")
fi
exec swift test "${task_test_flags[@]}" "$@"
